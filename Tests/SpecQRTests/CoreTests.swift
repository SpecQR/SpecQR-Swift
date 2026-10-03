import XCTest

@testable import SpecQR

final class CoreTests: XCTestCase {
   func testHighLevelFNC1SecondAndManualOptionsPercentSafety() throws {
      for text in ["ABC%DEF", "ABC%%DEF", "%\u{1D}%"] {
         for optimize in [true, false] {
            let auto = try SpecQR.generate(text, options: .init(optimizeSegments: optimize, fnc1Second: "A"))
            let byte = try SpecQR.generate(text, options: .init(mode: .byte, fnc1Second: "A"))
            XCTAssertEqual(auto.matrix, byte.matrix)
            XCTAssertThrowsError(try SpecQR.generate(text, options: .init(mode: .alphanumeric, fnc1Second: "A")))
         }
      }
      XCTAssertThrowsError(try SpecQR.analyzeSegments([.alphanumeric("10ABC%DEF")], options: .init(gs1: true)))
      XCTAssertThrowsError(try SpecQR.analyzeSegments([.alphanumeric("ABC%DEF")], options: .init(fnc1Second: "A")))
      XCTAssertNoThrow(try SpecQR.generate(segments: [.fnc1Second("A"), .alphanumeric("ABC%%DEF")]))
      let long = "10" + String(repeating: "%", count: 20)
      let overflow = try SpecQR.estimate(long, options: .init(version: 1, gs1: true))
      XCTAssertFalse(overflow.ok)
      XCTAssertEqual(overflow.mode, .byte)
   }

   func testHighLevelGS1PreservesLiteralPercent() throws {
      for text in ["10ABC%DEF", "10ABC%%DEF", "10%", "10%%%", "10LOT%\u{1D}21SER%IAL"] {
         let auto = try SpecQR.generate(text, options: .init(gs1: true))
         let byte = try SpecQR.generate(text, options: .init(mode: .byte, gs1: true))
         XCTAssertEqual(auto.matrix, byte.matrix)
         XCTAssertEqual(auto.segments, [.fnc1, .byteText(text)])
         XCTAssertEqual(auto.planning.inputBytes, text.utf8.count)
         XCTAssertEqual(try SpecQR.estimate(text, options: .init(gs1: true)).mode, .byte)
         XCTAssertThrowsError(try SpecQR.generate(text, options: .init(mode: .alphanumeric, gs1: true)))
      }
      let manual = try SpecQR.generate(segments: [.fnc1, .alphanumeric("10ABC%%DEF")])
      XCTAssertEqual(manual.segments, [.fnc1, .alphanumeric("10ABC%%DEF")])
   }

   func testMalformedHeaderDiagnosticsDoNotTrap() {
      for value in [Int.min, -1, 0, 17, Int.max] {
         let header = QRStructuredAppendHeader(index: value, total: value, parity: 0)
         XCTAssertFalse(header.isValid)
         XCTAssertNil(header.sequenceIndex)
         XCTAssertNil(header.sequenceTotal)
         XCTAssertNil(header.sequenceIndicator)
      }
      let valid = QRStructuredAppendHeader(index: 1, total: 2, parity: 0)
      XCTAssertEqual(valid.sequenceIndex, 0)
      XCTAssertEqual(valid.sequenceTotal, 1)
      XCTAssertEqual(valid.sequenceIndicator, 1)
   }

   func testAlphanumericGoldenCodewords() throws {
      let qr = try SpecQR.generate("HELLO WORLD")
      XCTAssertEqual(qr.version, 1)
      XCTAssertEqual(qr.maskPattern, 0)
      XCTAssertEqual(qr.planning.dataBitLength, 74)
      XCTAssertEqual(qr.segments, [.alphanumeric("HELLO WORLD")])
      XCTAssertEqual(qr.dataCodewords, [32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17])
      XCTAssertEqual(
         qr.codewords,
         [
            32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17, 236, 17, 196, 35, 39, 119, 235, 215, 231, 226,
            93, 23,
         ])
   }
   func testNumericGoldenCodewords() throws {
      let qr = try SpecQR.generate("01234567")
      XCTAssertEqual(qr.planning.dataBitLength, 41)
      XCTAssertEqual(qr.dataCodewords, [16, 32, 12, 86, 97, 128, 236, 17, 236, 17, 236, 17, 236, 17, 236, 17])
      XCTAssertEqual(qr.codewords.suffix(10), [165, 36, 212, 193, 237, 54, 199, 135, 44, 85])
   }
   func testKanjiGoldenAndMapping() throws {
      let qr = try SpecQR.generate("漢字")
      XCTAssertEqual(qr.planning.dataBitLength, 38)
      XCTAssertEqual(qr.segments, [.kanji("漢字")])
      XCTAssertEqual(qr.dataCodewords, [128, 35, 159, 168, 104, 0, 236, 17, 236, 17, 236, 17, 236, 17, 236, 17])
      XCTAssertEqual(KanjiMap.codes.count, 6953)
      XCTAssertEqual(try SpecQR.estimate("漢字", options: .init(eci: 26)).mode, .byte)
      XCTAssertThrowsError(try SpecQR.generate("😀", options: .init(mode: .kanji)))
   }
   func testOptimizedMixedGolden() throws {
      let qr = try SpecQR.generate("Hello🙂12345678901234567890")
      XCTAssertEqual(qr.version, 2)
      XCTAssertEqual(qr.maskPattern, 2)
      XCTAssertEqual(qr.planning.dataBitLength, 165)
      XCTAssertEqual(qr.segments, [.byteText("Hello🙂"), .numeric("12345678901234567890")])
      XCTAssertEqual(
         qr.dataCodewords,
         [
            64, 148, 134, 86, 198, 198, 255, 9, 249, 152, 33, 5, 7, 183, 35, 21, 3, 21, 154, 154, 208, 0, 236, 17, 236,
            17, 236, 17,
         ])
   }
   func testEmptyAndBinaryInput() throws {
      XCTAssertEqual(try SpecQR.generate("").segments, [.byteText("")])
      let bytes: [UInt8] = [0, 128, 255, 1]
      let code = try SpecQR.generate(bytes)
      XCTAssertEqual(code.planning.dataBitLength, 44)
      XCTAssertEqual(code.segments, [.byte(bytes)])
      XCTAssertEqual(code.diagnostics.segments[0].characterCount, 0)
      XCTAssertEqual(code.diagnostics.segments[0].byteCount, 4)
      XCTAssertEqual(try SpecQR.generate(Data(bytes)).matrix, code.matrix)
      XCTAssertThrowsError(try SpecQR.generate(bytes, options: .init(mode: .numeric)))
      XCTAssertThrowsError(try SpecQR.generate(bytes, options: .init(gs1: true)))
   }
   func testAllVersionCapacitiesAndBlockLengths() throws {
      for version in 1...40 {
         for level in ErrorCorrectionLevel.allCases {
            let capacity = try SpecQR.getCapacity(version: version, errorCorrectionLevel: level)
            XCTAssertGreaterThan(capacity.dataCodewords, 0)
            XCTAssertLessThan(capacity.dataCodewords, capacity.totalCodewords)
            let data = [UInt8](repeating: 0, count: capacity.dataCodewords)
            XCTAssertEqual(ReedSolomon.interleave(data, version: version, level: level).count, capacity.totalCodewords)
         }
      }
      XCTAssertEqual(try SpecQR.getCapacity(version: 1, errorCorrectionLevel: .L, mode: .numeric).maxCharacters, 41)
      XCTAssertEqual(
         try SpecQR.getCapacity(version: 1, errorCorrectionLevel: .L, mode: .alphanumeric).maxCharacters, 25)
      XCTAssertEqual(try SpecQR.getCapacity(version: 1, errorCorrectionLevel: .L, mode: .byte).maxBytes, 17)
      XCTAssertEqual(try SpecQR.getCapacity(version: 1, errorCorrectionLevel: .L, mode: .kanji).maxCharacters, 10)
      XCTAssertEqual(try SpecQR.getCapacity(version: 40, errorCorrectionLevel: .L, mode: .byte).maxBytes, 2953)
      XCTAssertEqual(try SpecQR.getCapacity(version: 40, errorCorrectionLevel: .L, mode: .numeric).maxCharacters, 7089)
      XCTAssertEqual(try SpecQR.getCapacity(version: 1, mode: .byte, controlBits: Int.max).maxBytes, 0)
   }
   func testExactCapacityAndOverflow() throws {
      let options = QROptions(errorCorrectionLevel: .L, version: 1, mode: .byte)
      XCTAssertTrue(try SpecQR.estimate(String(repeating: "x", count: 17), options: options).ok)
      let overflow = try SpecQR.estimate(String(repeating: "x", count: 18), options: options)
      XCTAssertFalse(overflow.ok)
      XCTAssertEqual(overflow.selectedVersion, 1)
      XCTAssertEqual(overflow.overflowBits, 4)
      XCTAssertThrowsError(try SpecQR.generate(String(repeating: "x", count: 18), options: options)) { error in
         XCTAssertEqual((error as? QRError)?.code, "DATA_TOO_LONG")
      }
      XCTAssertTrue(
         try SpecQR.estimate(String(repeating: "1", count: 7089), options: .init(errorCorrectionLevel: .L)).ok)
      XCTAssertFalse(
         try SpecQR.estimate(String(repeating: "1", count: 7090), options: .init(errorCorrectionLevel: .L)).ok)
      XCTAssertFalse(try SpecQR.estimate(String(repeating: "x", count: 100_000)).ok)
   }
   func testFixedVersionRangeAndBoost() throws {
      let qr = try SpecQR.generate(
         "1", options: .init(errorCorrectionLevel: .L, minVersion: 5, maxVersion: 6, boostErrorCorrection: true))
      XCTAssertEqual(qr.version, 5)
      XCTAssertEqual(qr.errorCorrectionLevel, .H)
      XCTAssertTrue(qr.planning.boostedErrorCorrection)
      XCTAssertEqual(qr.planning.requestedErrorCorrectionLevel, .L)
      XCTAssertEqual(try SpecQR.generate("A", options: .init(version: 2, minVersion: 5)).version, 2)
      let fixed = try SpecQR.generate("A", options: .init(version: 7, maskPattern: 7))
      XCTAssertEqual(fixed.maskPattern, 7)
      XCTAssertEqual(fixed.diagnostics.maskPenalties.count, 1)
   }
   func testECIDesignatorBoundaries() throws {
      let cases = [(0, 12), (127, 12), (128, 20), (16383, 20), (16384, 28), (999999, 28)]
      for (assignment, bits) in cases {
         let qr = try SpecQR.generate(segments: [.eci(assignment), .byte([0])])
         XCTAssertEqual(qr.planning.segmentDiagnostics[0].bitLength, bits)
         XCTAssertEqual(qr.planning.segmentDiagnostics[0].assignmentNumber, assignment)
      }
      XCTAssertEqual(try SpecQR.generate(segments: [.eci(128)]).dataCodewords.prefix(3), [0x78, 0x08, 0x00])
      XCTAssertEqual(try SpecQR.generate(segments: [.eci(16384)]).dataCodewords.prefix(4), [0x7C, 0x04, 0x00, 0x00])
      XCTAssertThrowsError(try SpecQR.generate(segments: [.eci(-1)]))
      XCTAssertThrowsError(try SpecQR.generate(segments: [.eci(1_000_000)]))
      XCTAssertNoThrow(try SpecQR.generate(segments: [.eci(3), .byte([1]), .eci(26), .byte([2])]))
   }
   func testFNC1AndStructuredAppendHeaderBits() throws {
      XCTAssertEqual(try SpecQR.generate(segments: [.fnc1]).dataCodewords[0], 0x50)
      XCTAssertEqual(try SpecQR.generate(segments: [.fnc1Second("12")]).dataCodewords.prefix(2), [0x90, 0xC0])
      XCTAssertEqual(try SpecQR.generate(segments: [.fnc1Second("A")]).dataCodewords.prefix(2), [0x9A, 0x50])
      let sa = try SpecQR.generate(segments: [.structuredAppend(index: 2, total: 3, parity: 0xAB)])
      XCTAssertEqual(sa.dataCodewords.prefix(3), [0x31, 0x2A, 0xB0])
      XCTAssertEqual(sa.planning.controlSegments[0].structuredAppend, .init(index: 2, total: 3, parity: 0xAB))
      XCTAssertThrowsError(try SpecQR.generate(segments: [.structuredAppend(index: 0, total: 3, parity: 0)]))
      XCTAssertThrowsError(try SpecQR.generate(segments: [.structuredAppend(index: 1, total: 1, parity: 0)]))
      XCTAssertThrowsError(try SpecQR.generate(segments: [.fnc1Second("AA")]))
   }
   func testControlConflictsAndOrdering() throws {
      for segments: [QRSegment] in [
         [.byte([1]), .fnc1], [.fnc1, .fnc1], [.fnc1, .eci(26)], [.fnc1Second("A"), .eci(1)],
         [.structuredAppend(index: 1, total: 2, parity: 0), .eci(2)],
      ] {
         XCTAssertThrowsError(try SpecQR.generate(segments: segments))
      }
      XCTAssertThrowsError(try SpecQR.generate("A", options: .init(eci: 26, gs1: true)))
      XCTAssertThrowsError(
         try SpecQR.generate(
            "A", options: .init(fnc1Second: "A", structuredAppend: .init(index: 1, total: 2, parity: 0))))
      XCTAssertThrowsError(try SpecQR.generate(segments: [.fnc1], options: .init(gs1: true)))
   }
   func testInvalidModesAndBounds() throws {
      for version in [-1, 0, 41, Int.max] { XCTAssertThrowsError(try SpecQR.getCapacity(version: version)) }
      XCTAssertThrowsError(try SpecQR.generate("A", options: .init(minVersion: 4, maxVersion: 3)))
      XCTAssertThrowsError(try SpecQR.generate("A", options: .init(maskPattern: 8)))
      XCTAssertThrowsError(try SpecQR.generate("A", options: .init(mode: .mixed)))
      XCTAssertThrowsError(try SpecQR.generate("１２", options: .init(mode: .numeric)))
      XCTAssertThrowsError(try SpecQR.generate("hello", options: .init(mode: .alphanumeric)))
      XCTAssertThrowsError(try SpecQR.getCapacity(version: 1, mode: .auto))
      XCTAssertThrowsError(try SpecQR.getCapacity(version: 1, controlBits: -1))
   }
   func testUnicodeCountsAndCanonicalEncoding() throws {
      let decomposed = "e\u{301}"
      let qr = try SpecQR.generate(decomposed, options: .init(mode: .byte))
      XCTAssertEqual(qr.diagnostics.segments[0].characterCount, 2)
      XCTAssertEqual(qr.diagnostics.segments[0].byteCount, 3)
      XCTAssertEqual(qr.diagnostics.inputBytes, 3)
      XCTAssertEqual(qr.dataCodewords.prefix(5), [0x40, 0x36, 0x5C, 0xC8, 0x10])
   }
   func testReedSolomonFieldAndSyndromes() {
      XCTAssertEqual(ReedSolomon.multiply(0x80, 2), 0x1D)
      XCTAssertEqual(ReedSolomon.multiply(0, 0xAB), 0)
      for byte in UInt8.min...UInt8.max { XCTAssertEqual(ReedSolomon.multiply(byte, 1), byte) }
      let polynomial = ReedSolomon.generator(degree: 18)
      let data: [UInt8] = [0, 1, 42, 255, 100, 10, 18]
      let encoded = data + ReedSolomon.remainder(data: data, generator: polynomial)
      var root: UInt8 = 1
      for _ in 0..<18 {
         let syndrome = encoded.reduce(UInt8(0)) { ReedSolomon.multiply($0, root) ^ $1 }
         XCTAssertEqual(syndrome, 0)
         root = ReedSolomon.multiply(root, 2)
      }
   }
   func testOptimizerNeverWorseThanSingleMode() throws {
      for text in [
         "123ABC456", "abc12345678901234567890xyz", "漢字12345678901234567890漢字", "😀1234567890", "123A456B789",
         "a漢字ABC12345678901234567890",
      ] {
         for version in [1, 9, 10, 26, 27, 40] {
            let optimized = try SpecQR.estimate(text, options: .init(version: version))
            let single = try SpecQR.estimate(text, options: .init(version: version, optimizeSegments: false))
            XCTAssertLessThanOrEqual(optimized.dataBitLength, single.dataBitLength)
         }
      }
   }
   func testGeneratedObjectsAreValueTypes() throws {
      let original = try SpecQR.generate("VALUE")
      var matrix = original.matrix
      matrix[0][0].toggle()
      XCTAssertNotEqual(matrix[0][0], original.matrix[0][0])
      let _: any Sendable = original
      let _: any Sendable = original.planning
   }
}
