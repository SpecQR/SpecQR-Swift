# Independent decoder verification

These are test-only adapters. They do not import the JavaScript SpecQR oracle,
and no third-party decoder or downloaded binary is linked into the Swift product.

## Run

From the package root with Swift, Node 20+, `curl`, Java 17+ (with the compiler
module), and Python 3.10+ with pip available:

```sh
swift build -c release
export SPECQR_CLI="$(swift build -c release --show-bin-path)/specqr-cli"
node Scripts/verify-zxing.mjs
python3 Scripts/verify-zxing-cpp.py
```

The scripts fetch their pinned test dependencies on first use. A network-restricted
CI runner must permit Maven Central and PyPI. Subsequent runs reuse `.build/`.
The C++ harness deliberately requires a published wheel and does not silently
build a native dependency. Its lock file contains hashes for all 30 published
3.1.1 wheels; an unsupported interpreter/platform fails clearly.

### Java suite

- ZXing `core` 3.5.4 from the official Maven Central repository
- SHA-256: `71de5d89341b5fcf5dd89da7f44e84d825d0e084cdf3ec77c9abe26b0f0ceb13`
- [Upstream](https://github.com/zxing/zxing), Apache-2.0
- [Pinned artifact](https://repo.maven.apache.org/maven2/com/google/zxing/core/3.5.4/core-3.5.4.jar)

`DecodeSymbols.java` runs through Java source-file launch, so a separate `javac`
executable or Maven install is unnecessary. Direct matrices go through ZXing's
QR decoder. PNGs from the actual Swift renderer go through Java ImageIO,
ZXing's luminance conversion, binarizer, finder-pattern detection, and QR reader;
`PURE_BARCODE` is deliberately not enabled.

The suite verifies all ECC levels and masks, numeric/alphanumeric/Kanji/UTF-8
payloads, binary byte segments, ECI 3/20/26/170, FNC1 first-position symbology,
all 135 legal Structured Append `(index,total)` combinations, and six sets made
by the high-level Swift API. Those sets cover 48 symbols: numeric, alphanumeric,
Unicode scalar boundaries, all 256 byte values, a 16-symbol set, and manual mixed
modes. Each is reassembled from independently decoded sequence/parity metadata
in simulated out-of-order scan order.

Each successful decode also compares the entire corrected data-codeword stream
against what Swift generated. Controlled corruption flips one module in each of
three distinct Version 1 data codewords, for every ECC/mask combination. The
suite checks both recovered data and ZXing's exact three-error correction count.
An all-white invalid matrix must be rejected.

ZXing Java 3.5.4's FNC1-second branch does not consume the application indicator.
That is a decoder limitation, so this suite does **not** claim to validate
FNC1-second. The C++ suite covers it separately.

### C++ suite

- ZXing-C++ 3.1.1, exact release and wheel SHA-256 hashes in
  `zxing-cpp-requirements.txt`
- [Upstream](https://github.com/zxing-cpp/zxing-cpp), Apache-2.0
- [Release metadata](https://pypi.org/pypi/zxing-cpp/3.1.1/json)

The script installs wheels only into `.build/zxing-cpp` using pip's
`--require-hashes`, `--only-binary=:all:`, and `--no-deps`. It uses Python's native
memoryview, so neither Pillow nor NumPy is required.

It covers all 152 legal FNC1-second indicators (00–99, A–Z, a–z), explicit control
segments and high-level options, alphanumeric/FNC1 escapes, exact binary bytes,
all ECC levels, and all masks. ZXing-C++ returns the application indicator as a
prefix of decoded bytes; assertions explicitly include that prefix. Separate
regressions check high-level literal percent preservation, doubled percent,
actual U+001D separators, and disabled segment optimization. Explicit low-level
FNC1 alphanumeric segments continue to use the standard single-percent separator
and doubled-percent literal convention.

## Outputs and limits

Reports, decoded records, PNG fixtures, dependency jars/wheels, and compiled
helpers stay under ignored `.build/zxing-java` and `.build/zxing-cpp`. Exclude
`.build/` from source deliveries. Reports include the tested Swift executable's
SHA-256, dependency identity, coverage counts, and explicit limitations.

These are real independent decoder tests, but synthetic image/matrix tests are
not a substitute for physical-camera/printing trials or formal ISO/GS1
conformance certification. Arbitrary ECI labels, every possible damage pattern,
and unsupported decoder metadata are not covered.
