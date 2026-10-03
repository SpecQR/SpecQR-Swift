import Foundation
import XCTest

@testable import SpecQR

final class GS1Tests: XCTestCase {
   func testPinnedUpstreamDifferentialFixtures() throws {
      let url = try XCTUnwrap(
         Bundle.module.url(forResource: "gs1-upstream", withExtension: "json", subdirectory: "Fixtures"))
      let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
      XCTAssertEqual(root["upstreamCommit"] as? String, "15ad15e5c770ea0e39072f8f88b2733018f02ffd")
      let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
      XCTAssertGreaterThan(cases.count, 1_000)
      for (index, fixture) in cases.enumerated() {
         let actual = try evaluateGS1Fixture(fixture)
         let expected = try XCTUnwrap(fixture["expected"])
         XCTAssertEqual(
            try canonicalGS1JSON(actual), try canonicalGS1JSON(expected),
            "GS1 fixture \(index): \(fixture["op"] ?? "") \(fixture["input"] ?? fixture["elements"] ?? "") \(fixture["options"] ?? "")"
         )
      }
   }

   func testHumanReadableRawRoundTripAndMetadata() throws {
      let elements = try GS1.parseHumanReadable("(01)04912345678904(10)ABC123(17)251231")
      let raw = try GS1.createElementString(elements)
      XCTAssertEqual(raw, "010491234567890410ABC123\u{1D}17251231")
      let result = try GS1.parseElementString(raw)
      XCTAssertEqual(result.elements, elements)
      XCTAssertTrue(result.hasSeparators)
      XCTAssertTrue(GS1.validateElementString(raw).ok)
      XCTAssertTrue(GS1.validateElements(elements, options: .init(context: .digitalLink)).ok)
   }

   func testAllCheckDigitLengthsAndLeadingZeros() throws {
      for count in [7, 11, 12, 13] {
         let body = String(repeating: "0", count: count)
         XCTAssertEqual(try GS1.appendGTINCheckDigit(body), body + "0")
         XCTAssertTrue(try GS1.validateGTINCheckDigit(body + "0"))
         XCTAssertFalse(try GS1.validateGTINCheckDigit(body + "1"))
      }
      XCTAssertEqual(try GS1.appendSSCCCheckDigit("12345678901234567"), "123456789012345675")
      XCTAssertThrowsError(try GS1.calculateCheckDigit("１２３"))
      XCTAssertThrowsError(try GS1.validateCheckDigit("7"))
   }

   func testStructuredValidationCollectsOrStops() {
      let input: [GS1.Element] = [
         .init(ai: "01", value: "123"), .init(ai: "30", value: "12A"), .init(ai: "9999", value: "ABC"),
      ]
      let collected = GS1.validateElements(input)
      XCTAssertEqual(collected.errors.map(\.code), ["GS1_INVALID_LENGTH", "GS1_INVALID_CHARSET", "GS1_UNSUPPORTED_AI"])
      XCTAssertEqual(collected.errors.compactMap(\.elementIndex), [0, 1, 2])
      XCTAssertEqual(collected.errors.compactMap(\.ai), ["01", "30", "9999"])
      XCTAssertEqual(GS1.validateElements(input, options: .init(collectAllErrors: false)).errors.count, 1)
      XCTAssertFalse(GS1.validateElements(input, options: .init(allowUnsupportedAI: true)).ok)
   }

   func testMissingSeparatorHeuristicMatchesUpstream() throws {
      // This conservative heuristic deliberately rejects even a literal batch ending in an
      // apparent fixed element. It does not attempt to validate the apparent suffix's value.
      let result = GS1.validateElementString("10ABC172XXXXX")
      XCTAssertEqual(result.errors.first?.code, "GS1_MISSING_SEPARATOR")
      XCTAssertEqual(result.errors.first?.offset, 2)
      XCTAssertEqual(result.errors.first?.ai, "10")
      XCTAssertEqual(try GS1.parseElementString("10ABC172XXXX").elements, [.init(ai: "10", value: "ABC172XXXX")])
   }

   func testDigitalLinkOrderingEscapesAndRoundTrip() throws {
      let elements: [GS1.Element] = [
         .init(ai: "01", value: "04912345678904"), .init(ai: "21", value: "SER/1"), .init(ai: "10", value: "LOT A"),
         .init(ai: "3102", value: "001234"), .init(ai: "17", value: "251231"),
      ]
      let uri = try GS1.createDigitalLink(elements, options: .init(baseURL: "https://example.com/stem"))
      XCTAssertEqual(uri, "https://example.com/stem/01/04912345678904/21/SER%2F1/10/LOT%20A?17=251231&3102=001234")
      let parsed = try GS1.parseDigitalLink(uri)
      XCTAssertEqual(parsed.pathElements, Array(elements.prefix(3)))
      XCTAssertEqual(parsed.queryElements.map(\.ai), ["17", "3102"])
      XCTAssertEqual(try GS1.createDigitalLink(parsed, options: .init(baseURL: "https://example.com/stem")), uri)
      XCTAssertEqual(try GS1.normalizeDigitalLink(uri), uri)
   }

   func testDigitalLinkNormalizationPreservesRepeatedUnknowns() throws {
      let uri = "https://EXAMPLE.com:443/stem%201/01/04912345678904?b=2&10=LOT%2fA&a=1&b=3"
      let normalized = try GS1.normalizeDigitalLink(uri)
      XCTAssertEqual(normalized, "https://example.com/stem%201/01/04912345678904/10/LOT%2FA?b=2&a=1&b=3")
      XCTAssertEqual(try GS1.normalizeDigitalLink(normalized), normalized)
      let warnings = GS1.validateDigitalLink("http://example.com/01/04912345678904?foo=bar").warnings
      XCTAssertEqual(warnings.map(\.code), ["GS1_DIGITAL_LINK_HTTP", "GS1_DIGITAL_LINK_UNKNOWN_QUERY_PRESERVED"])
      XCTAssertEqual(warnings.last?.count, 1)
   }

   func testTypedOptionsAndFoundationURLOverloads() throws {
      let url = try XCTUnwrap(URL(string: "https://example.com/01/04912345678904"))
      XCTAssertEqual(try GS1.parseDigitalLink(url).primary.ai, "01")
      XCTAssertTrue(GS1.validateDigitalLink(url).ok)
      XCTAssertEqual(try GS1.normalizeDigitalLink(url), url.absoluteString)
      XCTAssertEqual(
         try GS1.createDigitalLink(
            try GS1.parseElementString("0104912345678904"), options: .init(baseURL: URL(string: "https://example.com")!)
         ), url.absoluteString)
      XCTAssertEqual(
         GS1.validateDigitalLink(url, options: .init(normalize: true)).errors.first?.reason, "unsupported-option")
      XCTAssertThrowsError(try GS1.normalizeDigitalLink(url, options: .init(mode: "canonical")))
   }

   func testOverflowingHexadecimalHostsCannotFallBackToDNS() throws {
      let invalidHosts = [
         "0x10000000000000000",
         "0xffffffffffffffffffffffffffffffffffff",
         "foo.0x10000000000000000",
         "foo.0xffffffffffffffffffffffffffffffffffff",
         "0X10000000000000000",
         "0x10000000000000000.",
      ]
      for host in invalidHosts {
         let uri = "https://\(host)/01/09501101530003"
         XCTAssertThrowsError(try GS1.parseDigitalLink(uri), host)
         XCTAssertThrowsError(try GS1.normalizeDigitalLink(uri), host)
         let result = GS1.validateDigitalLink(uri)
         XCTAssertFalse(result.ok, host)
         XCTAssertEqual(result.errors.first?.code, "GS1_DIGITAL_LINK_INVALID_URI", host)
         XCTAssertThrowsError(
            try GS1.createDigitalLink(
               [.init(ai: "01", value: "09501101530003")],
               options: .init(baseURL: "https://\(host)")), host)
      }
      // A nonnumeric DNS suffix, or a non-hexadecimal character, still denotes a domain.
      for host in ["0x10000000000000000.example", "0x10000000000000000z"] {
         XCTAssertTrue(GS1.validateDigitalLink("https://\(host)/01/09501101530003").ok, host)
      }
   }

   func testCatalogHasBoundedSupportAndNoImplicitGLNCheckDigit() throws {
      XCTAssertEqual(GS1.getSupportedAIs().count, 50)
      XCTAssertNil(GS1.getAIInfo("3106"))
      XCTAssertNil(GS1.getAIInfo("90"))
      XCTAssertEqual(GS1.getAIInfo("91")?.length, .variable(min: 1, max: 90))
      XCTAssertEqual(GS1.getAIInfo("414")?.checkDigitRule, GS1.CheckDigitRule.none)
      // No calendar semantics or GLN check-digit checks are silently added to this port.
      XCTAssertTrue(
         GS1.validateElements([.init(ai: "17", value: "999999"), .init(ai: "414", value: "1234567890123")]).ok)
   }
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
