import Foundation
import SpecQR
import Testing

// Independent public-API Swift Testing validation for Command Line Tools hosts.
// These execute the original fixture corpus; they do not count as an XCTest run.
@Suite("Pinned upstream fixture corpus")
struct CorpusTests {
   @Test("All 1,411 GS1 fixtures preserve canonical results and errors")
   func gs1UpstreamCorpus() throws {
      let url = fixtureURL("gs1-upstream.json")
      let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
      #expect(root["upstreamCommit"] as? String == "15ad15e5c770ea0e39072f8f88b2733018f02ffd")
      let cases = try #require(root["cases"] as? [[String: Any]])
      #expect(cases.count == 1_411)
      for (index, fixture) in cases.enumerated() {
         let actual = try evaluateGS1Fixture(fixture)
         let expected = try #require(fixture["expected"])
         #expect(
            try canonicalGS1JSON(actual) == canonicalGS1JSON(expected),
            "GS1 fixture \(index): \(fixture["op"] ?? "") \(fixture["input"] ?? fixture["elements"] ?? "") \(fixture["options"] ?? "")"
         )
      }
   }

   @Test("All 22 Structured Append fixtures preserve matrices and diagnostics")
   func structuredAppendUpstreamCorpus() throws {
      let url = fixtureURL("structured-append-differential.json")
      let fixtures = try JSONDecoder().decode(FixtureFile.self, from: Data(contentsOf: url))
      #expect(fixtures.upstreamCommit == "15ad15e5c770ea0e39072f8f88b2733018f02ffd")
      #expect(fixtures.cases.count == 22)
      for fixture in fixtures.cases {
         let options = QRStructuredAppendOptions(
            qrOptions: fixture.options.qr, maxSymbols: fixture.options.maxSymbols ?? 16,
            diagnostics: true, splitUnits: fixture.type == "manual" ? .full : .summary)
         let result: QRStructuredAppendResult
         switch fixture.type {
         case "manual":
            result = try SpecQR.generateSegmentsStructuredAppend(
               try #require(fixture.segments).map(\.segment), options: options)
         case "binary": result = try SpecQR.generateStructuredAppend(try #require(fixture.bytes), options: options)
         default: result = try SpecQR.generateStructuredAppend(try #require(fixture.text), options: options)
         }
         let expected = fixture.expected
         #expect(result.total == expected.total, "\(fixture.id)")
         #expect(result.parity == expected.parity, "\(fixture.id)")
         #expect(result.inputLength == expected.inputLength, "\(fixture.id)")
         #expect(result.byteLength == expected.byteLength, "\(fixture.id)")
         #expect(result.diagnostics.version == expected.diagnostics.version, "\(fixture.id)")
         #expect(result.diagnostics.versionSelection == expected.diagnostics.versionSelection, "\(fixture.id)")
         #expect(
            result.diagnostics.versionSelectionReason == expected.diagnostics.versionSelectionReason,
            "\(fixture.id)")
         #expect(result.diagnostics.splitStrategy == expected.diagnostics.splitStrategy, "\(fixture.id)")
         #expect(result.diagnostics.splitUnitCount == expected.diagnostics.splitUnitCount, "\(fixture.id)")
         #expect(result.diagnostics.segmentCount == expected.diagnostics.segmentCount, "\(fixture.id)")
         #expect(result.diagnostics.warnings.map(\.code) == expected.diagnostics.warnings.map(\.code), "\(fixture.id)")
         if let units = expected.diagnostics.splitUnits {
            let actualUnits = try #require(result.diagnostics.splitUnits, "\(fixture.id)")
            try #require(actualUnits.count == units.count, "\(fixture.id)")
            for (actual, expected) in zip(actualUnits, units) {
               #expect(actual.sourceSegmentIndex == expected.sourceSegmentIndex, "\(fixture.id)")
               #expect(actual.mode == expected.mode, "\(fixture.id)")
               #expect(actual.unitStart == expected.unitStart, "\(fixture.id)")
               #expect(actual.unitLength == expected.unitLength, "\(fixture.id)")
               #expect(actual.byteStart == expected.byteStart, "\(fixture.id)")
               #expect(actual.byteLength == expected.byteLength, "\(fixture.id)")
            }
         } else {
            #expect(result.diagnostics.splitUnits == nil, "\(fixture.id)")
         }
         // Require lengths before indexing so a mismatch reports a failure instead of trapping.
         try #require(result.symbols.count == expected.matrices.count, "\(fixture.id)")
         try #require(result.diagnostics.symbols.count == expected.diagnostics.symbols.count, "\(fixture.id)")
         try #require(result.symbols.count == result.diagnostics.symbols.count, "\(fixture.id)")
         for (index, code) in result.symbols.enumerated() {
            #expect(
               code.matrix.map { $0.map { $0 ? "1" : "0" }.joined() } == expected.matrices[index],
               "\(fixture.id) symbol \(index + 1)")
            let actual = result.diagnostics.symbols[index]
            let expected = expected.diagnostics.symbols[index]
            #expect(actual.index == expected.index, "\(fixture.id)")
            #expect(actual.sequenceIndicator == expected.sequenceIndicator, "\(fixture.id)")
            #expect(actual.inputStart == expected.inputStart, "\(fixture.id)")
            #expect(actual.inputLength == expected.inputLength, "\(fixture.id)")
            #expect(actual.byteStart == expected.byteStart, "\(fixture.id)")
            #expect(actual.byteLength == expected.byteLength, "\(fixture.id)")
            #expect(actual.sourceSegmentStart == expected.sourceSegmentStart, "\(fixture.id)")
            #expect(actual.sourceSegmentEnd == expected.sourceSegmentEnd, "\(fixture.id)")
            #expect(actual.splitUnitStart == expected.splitUnitStart, "\(fixture.id)")
            #expect(actual.splitUnitLength == expected.splitUnitLength, "\(fixture.id)")
            #expect(actual.dataBitLength == expected.dataBitLength, "\(fixture.id)")
            #expect(actual.capacityBits == expected.capacityBits, "\(fixture.id)")
            #expect(actual.remainingBits == expected.remainingBits, "\(fixture.id)")
            #expect(actual.maskPattern == expected.maskPattern, "\(fixture.id)")
            #expect(
               code.segments.first == .structuredAppend(index: index + 1, total: result.total, parity: result.parity),
               "\(fixture.id)")
         }
      }
   }
}

private func fixtureURL(_ name: String) -> URL {
   URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("../../../../Tests/SpecQRTests/Fixtures", isDirectory: true)
      .appendingPathComponent(name)
      .standardizedFileURL
}

private func canonicalGS1JSON(_ value: Any) throws -> String {
   let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
   return String(decoding: data, as: UTF8.self)
}

private func evaluateGS1Fixture(_ fixture: [String: Any]) throws -> Any {
   let op = fixture["op"] as! String
   let input = fixture["input"] as? String ?? ""
   let opts = fixture["options"] as? [String: Any] ?? [:]
   let elements = (fixture["elements"] as? [[String: String]] ?? []).map {
      GS1.Element(ai: $0["ai"]!, value: $0["value"]!)
   }
   let primary = (opts["primaryAi"] as? String).flatMap(GS1.PrimaryAI.init(rawValue:))
   let unknown = (opts["unknownQuery"] as? String).flatMap(GS1.UnknownQueryPolicy.init(rawValue:)) ?? .preserve
   let validation = GS1.ValidationOptions(
      context: (opts["context"] as? String).flatMap(GS1.ValidationContext.init(rawValue:)) ?? .elementString,
      allowUnsupportedAI: opts["allowUnsupportedAi"] as? Bool ?? false,
      collectAllErrors: opts["collectAllErrors"] as? Bool ?? true)
   func json<T: Encodable>(_ value: T) throws -> Any {
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
   }
   do {
      switch op {
      case "dictionary": return try json(GS1.getSupportedAIs())
      case "info": return try json(GS1.getAIInfo(input))
      case "checkDigit": return try GS1.calculateCheckDigit(input)
      case "validateCheckDigit": return try GS1.validateCheckDigit(input)
      case "gtinDigit": return try GS1.calculateGTINCheckDigit(input)
      case "gtinAppend": return try GS1.appendGTINCheckDigit(input)
      case "gtinValidate": return try GS1.validateGTINCheckDigit(input)
      case "ssccDigit": return try GS1.calculateSSCCCheckDigit(input)
      case "ssccAppend": return try GS1.appendSSCCCheckDigit(input)
      case "ssccValidate": return try GS1.validateSSCCCheckDigit(input)
      case "human": return try json(GS1.parseHumanReadable(input))
      case "raw": return try json(GS1.parseElementString(input))
      case "create": return try GS1.createElementString(elements)
      case "validateElements": return try json(GS1.validateElements(elements, options: validation))
      case "validateRaw": return try json(GS1.validateElementString(input, options: validation))
      case "linkCreate":
         return try GS1.createDigitalLink(
            elements,
            options: .init(
               baseURL: opts["baseUrl"] as? String ?? "", primaryAI: primary ?? .gtin,
               pathAIs: opts["pathAis"] as? [String]))
      case "linkParse":
         return try json(GS1.parseDigitalLink(input, options: .init(primaryAI: primary, unknownQuery: unknown)))
      case "linkValidate":
         return try json(
            GS1.validateDigitalLink(
               input,
               options: .init(primaryAI: primary, unknownQuery: unknown, normalize: opts["normalize"] as? Bool ?? false)
            ))
      case "linkNormalize":
         return try GS1.normalizeDigitalLink(
            input,
            options: .init(
               primaryAI: primary, unknownQuery: unknown, mode: opts["mode"] as? String ?? "specqr-deterministic"))
      default:
         throw NSError(
            domain: "GS1Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown GS1 fixture operation \(op)"])
      }
   } catch let error as GS1Error { return ["throws": ["code": error.code, "message": error.message]] }
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
