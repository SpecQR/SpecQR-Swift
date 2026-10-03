#!/usr/bin/env python3
"""Reproduce independent Apple consumer tests with Xcode, using owned storage."""
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import time

evidence = Path(__file__).resolve().parent
package = evidence.parents[3]
scratch = package / ".build-xcode-apple-validation"
support = package / ".build-xcode-apple-validation-support"
env = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer",
           SPECQR_APPLE_BUILD_DIR=str(scratch), SPECQR_APPLE_CACHE_DIR=str(support),
           SWIFTPM_MODULECACHE_OVERRIDE=str(support / "swift-module-cache"))

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def command(args, log):
    log.write("$ " + shlex.join(args) + "\n")
    log.flush()
    return subprocess.run(args, cwd=package, env=env, stdout=log, stderr=subprocess.STDOUT).returncode

inputs = sorted((package / "Sources/SpecQR").rglob("*.swift"))
inputs += sorted((package / "Scripts/apple-validation").rglob("*.swift"))
inputs += [package / "Scripts/verify-apple.sh"]
hashes = {str(p.relative_to(package)): digest(p) for p in inputs}
(evidence / "input-sha256.json").write_text(json.dumps(hashes, indent=2) + "\n")
results = {"purpose": "Independent macOS public-API Swift Testing consumer execution",
           "environment": {key: env[key] for key in ["DEVELOPER_DIR", "SPECQR_APPLE_BUILD_DIR",
                                                      "SPECQR_APPLE_CACHE_DIR", "SWIFTPM_MODULECACHE_OVERRIDE"]},
           "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "lanes": []}
with (evidence / "environment.log").open("w") as log:
    for args in [["date", "-u"], ["sw_vers"], ["uname", "-m"], ["df", "-h", str(package)],
                 ["xcodebuild", "-version"], ["xcode-select", "-p"], ["xcrun", "--find", "swiftc"],
                 ["swift", "--version"]]:
        command(args, log)
for configuration in ["debug", "release"]:
    args = ["bash", "-x", "Scripts/verify-apple.sh", configuration]
    print("START " + configuration, flush=True)
    start = time.monotonic()
    with (evidence / (configuration + ".log")).open("w") as log:
        code = command(args, log)
    lane = {"configuration": configuration, "command": args, "exit_code": code,
            "elapsed_seconds": round(time.monotonic() - start, 2)}
    results["lanes"].append(lane)
    (evidence / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print("END " + configuration + " exit=" + str(code) + " seconds=" + str(lane["elapsed_seconds"]), flush=True)
    if code:
        sys.exit(code)
artifacts = sorted(p for p in scratch.rglob("*") if p.is_file()
                   and (p.suffix in [".swiftmodule", ".o", ".dylib"] or os.access(p, os.X_OK)))
results["artifacts_sha256"] = {str(p.relative_to(package)): digest(p) for p in artifacts}
results["inputs_unchanged"] = all(digest(package / p) == value for p, value in hashes.items())
if not results["inputs_unchanged"]:
    raise RuntimeError("Input source changed during tests")
with (evidence / "artifacts.log").open("w") as log:
    command(["file", *map(str, artifacts)], log)
results["completed_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
shutil.rmtree(scratch)
shutil.rmtree(support)
results["owned_temporary_storage_removed"] = True
(evidence / "results.json").write_text(json.dumps(results, indent=2) + "\n")
print("Independent consumer lanes passed; owned temporary storage removed.", flush=True)
