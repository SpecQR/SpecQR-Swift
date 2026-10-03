import Foundation
import XCTest

@testable import SpecQR

final class StructuredAppendTests: XCTestCase {
   func testCanonicalJSDifferentialFixtures() throws {
      let url = try XCTUnwrap(
         Bundle.module.url(
            forResource: "structured-append-differential", withExtension: "json", subdirectory: "Fixtures"))
      let fixtures = try JSONDecoder().decode(FixtureFile.self, from: Data(contentsOf: url))
      XCTAssertEqual(fixtures.upstreamCommit, "15ad15e5c770ea0e39072f8f88b2733018f02ffd")
      XCTAssertEqual(fixtures.cases.count, 22)
      for fixture in fixtures.cases {
         let options = QRStructuredAppendOptions(
            qrOptions: fixture.options.qr, maxSymbols: fixture.options.maxSymbols ?? 16,
            diagnostics: true, splitUnits: fixture.type == "manual" ? .full : .summary)
         let result: QRStructuredAppendResult
         switch fixture.type {
         case "manual":
            result = try SpecQR.generateSegmentsStructuredAppend(
               try XCTUnwrap(fixture.segments).map(\.segment), options: options)
         case "binary": result = try SpecQR.generateStructuredAppend(try XCTUnwrap(fixture.bytes), options: options)
         default: result = try SpecQR.generateStructuredAppend(try XCTUnwrap(fixture.text), options: options)
         }
         let expected = fixture.expected
         XCTAssertEqual(result.total, expected.total, fixture.id)
         XCTAssertEqual(result.parity, expected.parity, fixture.id)
         XCTAssertEqual(result.inputLength, expected.inputLength, fixture.id)
         XCTAssertEqual(result.byteLength, expected.byteLength, fixture.id)
         XCTAssertEqual(result.diagnostics.version, expected.diagnostics.version, fixture.id)
         XCTAssertEqual(result.diagnostics.versionSelection, expected.diagnostics.versionSelection, fixture.id)
         XCTAssertEqual(
            result.diagnostics.versionSelectionReason, expected.diagnostics.versionSelectionReason, fixture.id)
         XCTAssertEqual(result.diagnostics.splitStrategy, expected.diagnostics.splitStrategy, fixture.id)
         XCTAssertEqual(result.diagnostics.splitUnitCount, expected.diagnostics.splitUnitCount, fixture.id)
         XCTAssertEqual(result.diagnostics.segmentCount, expected.diagnostics.segmentCount, fixture.id)
         XCTAssertEqual(result.diagnostics.warnings.map(\.code), expected.diagnostics.warnings.map(\.code), fixture.id)
         if let units = expected.diagnostics.splitUnits {
            XCTAssertEqual(result.diagnostics.splitUnits, units.map(\.unit), fixture.id)
         } else {
            XCTAssertNil(result.diagnostics.splitUnits, fixture.id)
         }
         for (index, code) in result.symbols.enumerated() {
            XCTAssertEqual(
               code.matrix.map { $0.map { $0 ? "1" : "0" }.joined() }, expected.matrices[index],
               "\(fixture.id) symbol \(index + 1)")
            let actual = result.diagnostics.symbols[index]
            let expected = expected.diagnostics.symbols[index]
            XCTAssertEqual(actual.index, expected.index, fixture.id)
            XCTAssertEqual(actual.sequenceIndicator, expected.sequenceIndicator, fixture.id)
            XCTAssertEqual(actual.inputStart, expected.inputStart, fixture.id)
            XCTAssertEqual(actual.inputLength, expected.inputLength, fixture.id)
            XCTAssertEqual(actual.byteStart, expected.byteStart, fixture.id)
            XCTAssertEqual(actual.byteLength, expected.byteLength, fixture.id)
            XCTAssertEqual(actual.sourceSegmentStart, expected.sourceSegmentStart, fixture.id)
            XCTAssertEqual(actual.sourceSegmentEnd, expected.sourceSegmentEnd, fixture.id)
            XCTAssertEqual(actual.splitUnitStart, expected.splitUnitStart, fixture.id)
            XCTAssertEqual(actual.splitUnitLength, expected.splitUnitLength, fixture.id)
            XCTAssertEqual(actual.dataBitLength, expected.dataBitLength, fixture.id)
            XCTAssertEqual(actual.capacityBits, expected.capacityBits, fixture.id)
            XCTAssertEqual(actual.remainingBits, expected.remainingBits, fixture.id)
            XCTAssertEqual(actual.maskPattern, expected.maskPattern, fixture.id)
            XCTAssertEqual(
               code.segments.first, .structuredAppend(index: index + 1, total: result.total, parity: result.parity),
               fixture.id)
         }
      }
   }

   func testCanonicalParity() throws {
      XCTAssertEqual(SpecQR.calculateStructuredAppendParity(""), 0)
      XCTAssertEqual(SpecQR.calculateStructuredAppendParity([UInt8]()), 0)
      XCTAssertEqual(SpecQR.calculateStructuredAppendParity("ABC"), 0x40)
      XCTAssertEqual(SpecQR.calculateStructuredAppendParity([0, 255, 65, 126]), 192)
      let storage = Data([170, 16, 32, 187])
      XCTAssertEqual(SpecQR.calculateStructuredAppendParity(storage[1..<3]), 48)
      let segments: [QRSegment] = [
         .numeric("12345"), .alphanumeric("HELLO-QR"), .byteText("é"), .byte([0, 255, 65]), .kanji("漢字"),
      ]
      let expected = Array("12345HELLO-QRé".utf8) + [0, 255, 65] + Array("漢字".utf8)
      XCTAssertEqual(try SpecQR.calculateStructuredAppendSegmentsParity(segments), expected.reduce(0, ^))
      for segments: [QRSegment] in [
         [], [.byte([])], [.byteText("")], [.numeric("")], [.kanji("")], [.alphanumeric("")],
      ] {
         assertError("INVALID_INPUT") { _ = try SpecQR.calculateStructuredAppendSegmentsParity(segments) }
      }
      for segment: QRSegment in [.eci(26), .fnc1Second("37"), .structuredAppend(index: 1, total: 2, parity: 0)] {
         assertError("INVALID_MODE") {
            _ = try SpecQR.calculateStructuredAppendSegmentsParity([segment, .byteText("ABC")])
         }
      }
      assertError("INVALID_GS1") { _ = try SpecQR.calculateStructuredAppendSegmentsParity([.fnc1, .numeric("123")]) }
      assertError("INVALID_MODE") { _ = try SpecQR.calculateStructuredAppendSegmentsParity([.numeric("12a")]) }
   }

   func testManualSummaryAndFullDiagnosticsHaveIdenticalOutput() throws {
      let segments: [QRSegment] = [.numeric("1234567890"), .byteText(String(repeating: "🙂é", count: 12)), .kanji("漢字")]
      let options = QROptions(errorCorrectionLevel: .L, version: 2, maskPattern: 1)
      let summary = try SpecQR.generateSegmentsStructuredAppend(segments, options: .init(qrOptions: options))
      let full = try SpecQR.generateSegmentsStructuredAppend(
         segments, options: .init(qrOptions: options, diagnostics: true, splitUnits: .full))
      XCTAssertEqual(summary.symbols, full.symbols)
      XCTAssertNil(summary.diagnostics.splitUnits)
      XCTAssertEqual(summary.diagnostics.splitUnitsDetail, .summary)
      XCTAssertEqual(full.diagnostics.splitUnitsDetail, .full)
      XCTAssertEqual(full.diagnostics.splitUnits?.count, full.diagnostics.splitUnitCount)
      XCTAssertEqual(full.diagnostics.splitUnits?.last?.byteLength, 6)
      XCTAssertEqual(full.diagnostics.splitUnits?.last?.unitLength, 2)
      XCTAssertTrue(summary.diagnostics.warnings.isEmpty)
      XCTAssertEqual(full.diagnostics.warnings.map(\.code), ["STRUCTURED_APPEND_DECODER_SUPPORT_VARIES"])
   }

   func testGenerationRejectsUnsupportedOptionsAndSingleSymbol() throws {
      let text = String(repeating: "a", count: 31)
      assertError("INVALID_INPUT") { _ = try SpecQR.generateStructuredAppend("") }
      assertError("INVALID_INPUT") { _ = try SpecQR.generateStructuredAppend([UInt8]()) }
      assertError("INVALID_INPUT") { _ = try SpecQR.generateStructuredAppend("short") }
      assertError("INVALID_INPUT") { _ = try SpecQR.generateSegmentsStructuredAppend([.byteText("short")]) }
      assertError("INVALID_INPUT") { _ = try SpecQR.generateSegmentsStructuredAppend([]) }
      for limit in [-1, 0, 1, 17, Int.max] {
         assertError("INVALID_MODE") {
            _ = try SpecQR.generateStructuredAppend(text, options: .init(maxSymbols: limit))
         }
      }
      var invalid: [(QROptions, String)] = []
      var eci = QROptions()
      eci.eci = 26
      invalid.append((eci, "INVALID_MODE"))
      var gs1 = QROptions()
      gs1.gs1 = true
      invalid.append((gs1, "INVALID_GS1"))
      var fnc = QROptions()
      fnc.fnc1Second = "37"
      invalid.append((fnc, "INVALID_MODE"))
      var header = QROptions()
      header.structuredAppend = .init(index: 1, total: 2, parity: 0)
      invalid.append((header, "INVALID_MODE"))
      var boost = QROptions()
      boost.boostErrorCorrection = true
      invalid.append((boost, "INVALID_MODE"))
      var version = QROptions()
      version.version = 41
      invalid.append((version, "INVALID_VERSION"))
      var range = QROptions()
      range.minVersion = 5
      range.maxVersion = 3
      invalid.append((range, "INVALID_VERSION"))
      var mask = QROptions()
      mask.maskPattern = 8
      invalid.append((mask, "INVALID_INPUT"))
      for (options, error) in invalid {
         assertError(error) { _ = try SpecQR.generateStructuredAppend(text, options: .init(qrOptions: options)) }
         assertError(error) {
            _ = try SpecQR.generateSegmentsStructuredAppend([.byteText(text)], options: .init(qrOptions: options))
         }
      }
      assertError("INVALID_MODE") {
         _ = try SpecQR.generateStructuredAppend([0, 1], options: .init(qrOptions: .init(mode: .numeric)))
      }
      assertError("INVALID_MODE") {
         _ = try SpecQR.generateStructuredAppend("123A", options: .init(qrOptions: .init(mode: .numeric)))
      }
      assertError("INVALID_MODE") {
         _ = try SpecQR.generateSegmentsStructuredAppend(
            [.byteText(text)], options: .init(qrOptions: .init(mode: .byte)))
      }
      assertError("INVALID_MODE") {
         _ = try SpecQR.generateSegmentsStructuredAppend(
            [.byteText(text)], options: .init(qrOptions: .init(optimizeSegments: false)))
      }
      assertError("INVALID_INPUT") { _ = try SpecQR.generateStructuredAppend(text, options: .init(splitUnits: .full)) }
      assertError("DATA_TOO_LONG") {
         _ = try SpecQR.generateStructuredAppend(
            Array(repeating: UInt8(0), count: 31),
            options: .init(qrOptions: .init(errorCorrectionLevel: .L, version: 1), maxSymbols: 2))
      }
      assertError("DATA_TOO_LONG") {
         _ = try SpecQR.generateSegmentsStructuredAppend(
            [.numeric(String(repeating: "1", count: 70)), .byteText("abc")],
            options: .init(qrOptions: .init(version: 1)))
      }
   }

   func testIncrementalTrackerMatchesCoreOptimizerAcrossPrefixes() throws {
      let alphabet = Array("0123456789ABCXYZabc $%*+-./:é漢字🙂e\u{0301}".unicodeScalars)
      var seed: UInt64 = 0x51A77E
      for version in [1, 10, 27, 40] {
         for _ in 0..<40 {
            var scalars: [Unicode.Scalar] = []
            var tracker = StructuredAppendEncoder.TextBitLengthTracker(version: version)
            for index in 0..<48 {
               seed = seed &* 6_364_136_223_846_793_005 &+ 1
               let scalar = alphabet[Int((seed >> 32) % UInt64(alphabet.count))]
               scalars.append(scalar)
               let bits = tracker.append(scalar)
               if index % 3 == 0 || index == 47 {
                  let text = String(String.UnicodeScalarView(scalars))
                  let segments = SegmentOptimizer.optimized(text, version: version, allowKanji: true)
                  XCTAssertEqual(bits, segments.reduce(0) { $0 + SegmentEncoder.bitLength($1, version: version) })
               }
            }
         }
      }
   }

   func testTooLongErrorExplainsTheSplitConstraint() {
      do {
         _ = try SpecQR.generateStructuredAppend(
            Array(repeating: UInt8(0), count: 31),
            options: .init(qrOptions: .init(errorCorrectionLevel: .L, version: 1), maxSymbols: 2))
         XCTFail("Expected a split capacity failure")
      } catch let error as QRError {
         XCTAssertEqual(error.code, "DATA_TOO_LONG")
         XCTAssertEqual(
            error.errorDescription, "Input cannot be split into 2 or fewer version 1-L Structured Append symbols")
      } catch { XCTFail("Unexpected error: \(error)") }
   }

   func testLargeInputsFailCapacityPreflight() {
      let options = QRStructuredAppendOptions(qrOptions: .init(errorCorrectionLevel: .H, version: 1), maxSymbols: 2)
      assertError("DATA_TOO_LONG") {
         _ = try SpecQR.generateStructuredAppend(String(repeating: "A", count: 100_000), options: options)
      }
      assertError("DATA_TOO_LONG") {
         _ = try SpecQR.generateStructuredAppend(Array(repeating: UInt8(0), count: 100_000), options: options)
      }
      assertError("DATA_TOO_LONG") {
         _ = try SpecQR.generateSegmentsStructuredAppend(
            [.byteText(String(repeating: "🙂", count: 100_000))], options: options)
      }
   }

   func testDataSliceGenerationAndValueIsolation() throws {
      let bytes = (0..<31).map(UInt8.init)
      let backing = Data([0xff] + bytes + [0xff])
      let options = QRStructuredAppendOptions(qrOptions: .init(errorCorrectionLevel: .L, version: 1, maskPattern: 2))
      let sliced = try SpecQR.generateStructuredAppend(backing[1..<32], options: options)
      let plain = try SpecQR.generateStructuredAppend(bytes, options: options)
      XCTAssertEqual(sliced, plain)
      var callerOptions = QROptions(errorCorrectionLevel: .L, version: 1, maskPattern: 2)
      let snapshot = QRStructuredAppendOptions(qrOptions: callerOptions)
      callerOptions.version = 2
      XCTAssertEqual(snapshot.qrOptions.version, 1)
      func requireSendable<T: Sendable>(_ value: T) {}
      requireSendable(sliced)
      requireSendable(snapshot)
   }

   func testMixedSingleAndTooLongVersionsRemainTooLong() {
      // An indivisible segment overflows version 1, then the entire input fits version 2.
      // No usable multi-symbol split exists: upstream prefers DATA_TOO_LONG over single input.
      assertError("DATA_TOO_LONG") {
         _ = try SpecQR.generateSegmentsStructuredAppend(
            [.numeric(String(repeating: "1", count: 40))],
            options: .init(qrOptions: .init(errorCorrectionLevel: .M, minVersion: 1, maxVersion: 2)))
      }
   }

   func testUnicodeAndBinaryRoundTripThroughMerge() throws {
      let text = String(repeating: "e\u{0301}🙂漢", count: 8)
      let generated = try SpecQR.generateStructuredAppend(
         text, options: .init(qrOptions: .init(errorCorrectionLevel: .L, version: 2, mode: .byte)))
      let scalars = Array(text.unicodeScalars)
      let parts = generated.diagnostics.symbols.reversed().map { symbol in
         QRStructuredAppendPart(
            index: symbol.index, total: symbol.total, parity: symbol.parity,
            text: String(
               String.UnicodeScalarView(scalars[symbol.inputStart!..<(symbol.inputStart! + symbol.inputLength!)])))
      }
      let merged = try SpecQR.mergeStructuredAppendParts(parts)
      XCTAssertEqual(merged.data, .text(text))
      XCTAssertEqual(merged.diagnostics.byteLength, text.utf8.count)
      XCTAssertTrue(merged.diagnostics.parityCheck.matches)
      XCTAssertTrue(merged.diagnostics.missing.isEmpty)
      XCTAssertEqual(merged.parts.map(\.index), Array(1...generated.total))
      let bytes = (0..<61).map(UInt8.init)
      let binary = try SpecQR.generateStructuredAppend(
         Data(bytes), options: .init(qrOptions: .init(errorCorrectionLevel: .L, version: 1)))
      let binaryParts = binary.diagnostics.symbols.reversed().map { symbol in
         QRStructuredAppendPart(
            index: symbol.index, total: symbol.total, parity: symbol.parity,
            bytes: Array(bytes[symbol.byteStart..<(symbol.byteStart + symbol.byteLength)]))
      }
      XCTAssertEqual(try SpecQR.mergeStructuredAppendParts(binaryParts).data, .bytes(bytes))
   }

   func testMergeRejectsCorruptionAndInvalidMetadata() throws {
      let p = SpecQR.calculateStructuredAppendParity("AB")
      let first = QRStructuredAppendPart(index: 1, total: 2, parity: p, text: "A")
      let second = QRStructuredAppendPart(index: 2, total: 2, parity: p, text: "B")
      XCTAssertEqual(try SpecQR.mergeStructuredAppendParts([second, first]).data, .text("AB"))
      let invalid: [[QRStructuredAppendPart]] = [
         [], [first], [first, first],
         [.init(index: 0, total: 2, parity: p, text: "A"), second],
         [.init(index: 17, total: 2, parity: p, text: "A"), second],
         [.init(index: 3, total: 2, parity: p, text: "A"), second],
         [.init(index: 1, total: 1, parity: p, text: "A"), second],
         [.init(index: 1, total: 17, parity: p, text: "A"), second],
         [first, .init(index: 2, total: 3, parity: p, text: "B")],
         [first, .init(index: 2, total: 2, parity: p ^ 1, text: "B")],
         [first, .init(index: 2, total: 2, parity: p, text: "C")],
         [first, .init(index: 2, total: 2, parity: p, bytes: [66])],
      ]
      for parts in invalid { assertError("INVALID_INPUT") { _ = try SpecQR.mergeStructuredAppendParts(parts) } }
      // The merge utility follows upstream in allowing empty decoded chunks if complete parity is valid.
      let empty = try SpecQR.mergeStructuredAppendParts([
         .init(index: 1, total: 2, parity: 65, text: ""), .init(index: 2, total: 2, parity: 65, text: "A"),
      ])
      XCTAssertEqual(empty.data, .text("A"))
   }

   private func assertError(
      _ code: String, file: StaticString = #filePath, line: UInt = #line, _ operation: () throws -> Void
   ) {
      XCTAssertThrowsError(try operation(), file: file, line: line) { error in
         XCTAssertEqual((error as? QRError)?.code, code, "\(error)", file: file, line: line)
      }
   }
}

private struct FixtureFile: Decodable {
   let upstreamCommit: String
   let cases: [Fixture]
}
private struct Fixture: Decodable {
   let id: String
   let type: String
   let text: String?
   let bytes: [UInt8]?
   let segments: [FixtureSegment]?
   let options: FixtureOptions
   let expected: FixtureExpected
}
private struct FixtureOptions: Decodable {
   let version: Int?
   let minVersion: Int?
   let maxVersion: Int?
   let maskPattern: Int?
   let errorCorrectionLevel: ErrorCorrectionLevel?
   let mode: QRMode?
   let optimizeSegments: Bool?
   let maxSymbols: Int?
   var qr: QROptions {
      .init(
         errorCorrectionLevel: errorCorrectionLevel ?? .M, version: version, minVersion: minVersion ?? 1,
         maxVersion: maxVersion ?? 40, maskPattern: maskPattern, mode: mode ?? .auto,
         optimizeSegments: optimizeSegments ?? true)
   }
}
private struct FixtureSegment: Decodable {
   let segment: QRSegment
   enum CodingKeys: String, CodingKey { case mode, data }
   init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      let mode = try c.decode(QRMode.self, forKey: .mode)
      if let bytes = try? c.decode([UInt8].self, forKey: .data) {
         segment = .byte(bytes)
         return
      }
      let text = try c.decode(String.self, forKey: .data)
      switch mode {
      case .numeric: segment = .numeric(text)
      case .alphanumeric: segment = .alphanumeric(text)
      case .kanji: segment = .kanji(text)
      default: segment = .byteText(text)
      }
   }
}
private struct FixtureExpected: Decodable {
   let total: Int
   let parity: UInt8
   let inputLength: Int
   let byteLength: Int
   let diagnostics: FixtureDiagnostics
   let matrices: [[String]]
}
private struct FixtureDiagnostics: Decodable {
   let version: Int
   let versionSelection: String
   let versionSelectionReason: String
   let splitStrategy: String
   let splitUnitCount: Int?
   let segmentCount: Int?
   let splitUnits: [FixtureUnit]?
   let symbols: [FixtureSymbol]
   let warnings: [FixtureWarning]
}
private struct FixtureWarning: Decodable { let code: String }
private struct FixtureUnit: Decodable {
   let sourceSegmentIndex: Int
   let mode: QRMode
   let unitStart: Int
   let unitLength: Int
   let byteStart: Int
   let byteLength: Int
   var unit: QRStructuredAppendSplitUnit {
      .init(
         sourceSegmentIndex: sourceSegmentIndex, mode: mode, unitStart: unitStart, unitLength: unitLength,
         byteStart: byteStart, byteLength: byteLength)
   }
}
private struct FixtureSymbol: Decodable {
   let index: Int
   let sequenceIndicator: Int
   let inputStart: Int?
   let inputLength: Int?
   let byteStart: Int
   let byteLength: Int
   let sourceSegmentStart: Int?
   let sourceSegmentEnd: Int?
   let splitUnitStart: Int?
   let splitUnitLength: Int?
   let dataBitLength: Int
   let capacityBits: Int
   let remainingBits: Int
   let maskPattern: Int
}
