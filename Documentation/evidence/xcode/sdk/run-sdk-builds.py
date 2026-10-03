#!/usr/bin/env python3
"""Compile SpecQR against installed Apple SDKs; never execute target binaries.

Writes logs/metadata beside this script. Temporary files stay within the package.
Uses the process-local DEVELOPER_DIR; makes no Xcode/global preference changes.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import time

evidence = Path(__file__).resolve().parent
package = evidence.parents[3]
scratch = package / ".build-xcode-sdk"
support = package / ".build-xcode-sdk-support"
env = dict(os.environ)
env["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
env["CLANG_MODULE_CACHE_PATH"] = str(support / "clang-module-cache")
env["SWIFTPM_MODULECACHE_OVERRIDE"] = str(support / "swift-module-cache")
support.mkdir(exist_ok=True)

def run(command, log):
    log.write("$ " + shlex.join(command) + "\n")
    log.flush()
    return subprocess.run(command, cwd=package, env=env, stdout=log,
                          stderr=subprocess.STDOUT).returncode

def capture(command):
    return subprocess.check_output(command, cwd=package, env=env, text=True).strip()

def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

results = {
    "purpose": "Compile-only SDK validation; no iOS/tvOS/watchOS runtime execution",
    "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "environment": {key: env[key] for key in
                    ["DEVELOPER_DIR", "CLANG_MODULE_CACHE_PATH", "SWIFTPM_MODULECACHE_OVERRIDE"]},
    "source_sha256": {str(path.relative_to(package)): sha256(path)
                      for path in sorted((package / "Sources/SpecQR").rglob("*.swift"))},
    "package_sha256": sha256(package / "Package.swift"),
    "lanes": [],
}
with (evidence / "environment.log").open("w") as log:
    for command in [["date", "-u"], ["sw_vers"], ["uname", "-m"],
                    ["df", "-h", str(package)], ["xcodebuild", "-version"],
                    ["xcrun", "swift", "--version"], ["xcodebuild", "-showsdks"]]:
        run(command, log)

sdks = {}
for name in ["iphoneos", "appletvos", "watchos"]:
    sdk = capture(["xcrun", "--sdk", name, "--show-sdk-path"])
    sdks[name] = sdk
    results.setdefault("sdks", {})[name] = {
        "path": sdk,
        "version": capture(["xcrun", "--sdk", name, "--show-sdk-version"]),
        "build_version": capture(["xcrun", "--sdk", name, "--show-sdk-build-version"]),
        "settings": json.loads((Path(sdk) / "SDKSettings.json").read_text()),
    }

lanes = [("ios16-arm64", "iphoneos", "arm64-apple-ios16.0"),
         ("tvos16-arm64", "appletvos", "arm64-apple-tvos16.0"),
         ("watchos9-arm64_32", "watchos", "arm64_32-apple-watchos9.0"),
         ("watchos9-arm64", "watchos", "arm64-apple-watchos9.0")]
for name, sdk, triple in lanes:
    lane_scratch = scratch / name
    for configuration in ["debug", "release"]:
        lane_name = name + "-" + configuration
        command = ["xcrun", "swift", "build", "--target", "SpecQR", "--build-system", "native",
                   "--sdk", sdks[sdk], "--triple", triple, "-c", configuration, "-j", "2",
                   "--disable-index-store", "--scratch-path", str(lane_scratch),
                   "--cache-path", str(support / "cache"), "--config-path", str(support / "config"),
                   "--security-path", str(support / "security"), "--manifest-cache", "local", "-v"]
        print("START " + lane_name, flush=True)
        start = time.monotonic()
        with (evidence / (lane_name + ".log")).open("w") as log:
            code = run(command, log)
        lane = {"name": lane_name, "triple": triple, "configuration": configuration,
                "command": command, "exit_code": code,
                "elapsed_seconds": round(time.monotonic() - start, 2)}
        objects = sorted(path for path in lane_scratch.rglob("*.o")
                         if path.parent.name == "SpecQR.build" and configuration in path.parts)
        modules = sorted(path for path in lane_scratch.rglob("SpecQR.swiftmodule")
                         if path.is_file() and configuration in path.parts)
        lane["artifacts_sha256"] = {str(path.relative_to(package)): sha256(path)
                                    for path in objects + modules}
        lane["object_count"] = len(objects)
        lane["module_count"] = len(modules)
        if code == 0 and (not objects or not modules):
            raise RuntimeError("Build exited zero but required objects/module not found: " + lane_name)
        with (evidence / (lane_name + "-objects.log")).open("w") as log:
            if objects:
                run(["file", *map(str, objects)], log)
                run(["xcrun", "otool", "-l", str(objects[0])], log)
        object_metadata = (evidence / (lane_name + "-objects.log")).read_text()
        lane["object_architectures"] = sorted(set(re.findall(r"Mach-O (?:64-bit )?object (\S+)", object_metadata)))
        lane["effective_object_minimum_os"] = re.findall(r"^\s+minos (\S+)", object_metadata, re.M)
        lane["object_sdk_versions"] = re.findall(r"^\s+sdk (\S+)", object_metadata, re.M)
        results["lanes"].append(lane)
        (evidence / "results.json").write_text(json.dumps(results, indent=2) + "\n")
        print("END " + lane_name + " exit=" + str(code) + " seconds=" +
              str(lane["elapsed_seconds"]) + " objects=" + str(len(objects)), flush=True)
        if code != 0:
            print("Stopped at failed lane; inspect log before retrying.", flush=True)
            sys.exit(code)
    shutil.rmtree(lane_scratch)
shutil.rmtree(scratch)
shutil.rmtree(support)
results["completed_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
results["temporary_build_directories_removed"] = True
(evidence / "results.json").write_text(json.dumps(results, indent=2) + "\n")
print("All SDK compile lanes passed; owned build directories removed.", flush=True)
