Independent iOS simulator Vision control — 2026-10-03

Finding: Vision revisions 3/4 returned zero barcode observations for BOTH
SpecQR output and Apple's independently generated CoreImage QR output in this
iOS 27.0 simulator. These failures remain an explicit simulator limitation.
No SpecQR renderer defect was established by the comparison.

Exact tested payload: SpecQR Apple validation 12345
Runtime: iOS 27.0 build 24A434, Apple-silicon simulator, iPhone 17 model.
Compiler: Xcode 27.0 build 27A266a, Apple Swift 6.4 swiftlang-6.4.0.34.1.
Vision supported revisions: 1, 2, 3, 4; default/current revision: 4.

Five inputs, each tested with all 4 revisions and 2 compute-device modes:
1. Original SpecQR.generate(payload).cgImage(): 296x296, default margin 4 / scale 8.
2. SpecQR with margin 6 / scale 10 (410x410).
3. Same enlarged SpecQR drawn to explicit premultiplied RGBA CGContext.
4. Apple's CIFilter.qrCodeGenerator() output, correction M, independently padded
   with 6 white modules and scaled 10x, CIContext software-rendered (430x430).
5. Same Apple-generated image drawn to the explicit RGBA CGContext.

40 actual VNImageRequestHandler.perform calls in the simulator:
- Revision 1: exact UTF-8 payload recovered for all 5 images in both device modes.
- Revision 2, supported CPU: exact payload recovered for all 5 images, including
  the original 296x296 default-size SpecQR image.
- Revision 2, default devices: first original-size call threw com.apple.Vision
  Code 9 "Could not create inference context"; the 4 later images decoded.
- Revisions 3/4: zero observations for all 5 images, with both default devices
  and supported CPU explicitly selected.20 failed payload matches remain logged.

Thus 19 request cases recovered the exact payload, 20 returned no observations,
and 1 threw a runtime error. Probe process exit 0 means diagnostics completed;
it does NOT mean all 40 decoding attempts passed. Each successful observation
reported QR symbology / confidence 1. Every result/error and selected stage-device
list is preserved in simulator.log and results.json.

For a simulator-specific regression test, revision 2 plus an explicitly
supported CPU device genuinely decodes the original image and preserves the
exact expected payload. This diagnostic does not modify any production/test
file, suppress a failed assertion or prove default revision 4 works. Runtime
library source stayed unchanged. Root owns the test-configuration change.

Artifacts:
- VisionProbe.swift: standalone native probe; no XCTest dependency.
- simulator.log: full native output, including framework errors and JSON events.
- results.json: parsed request/image/environment records and source/binary hashes.
- compile.log: final compile output.
- commands.txt: exact executed compile/run commands.
- run-probe.sh: reproducer requiring the built simulator SpecQR.o/swiftmodule
  and an existing booted simulator. Override SPECQR_PROBE_SIMULATOR for another.

The final compiled probe links the existing coverage-instrumented SpecQR.o,
using -profile-generate solely to resolve that object's profiling runtime.
Only owned .build-xcode-vision-probe scratch was removed after hashes were saved.
No privacy settings, simulator configuration, production or test source changed.
