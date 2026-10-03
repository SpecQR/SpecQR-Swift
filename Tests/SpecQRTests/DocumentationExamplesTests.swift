import Foundation
import SpecQR
import XCTest

final class DocumentationExamplesTests: XCTestCase {
   func testReadmeGenerationAndPlanning() throws {
      let code = try SpecQR.generate("https://example.com", options: .init(errorCorrectionLevel: .Q))
      XCTAssertFalse(code.matrix.isEmpty)
      XCTAssertTrue(try code.svg().contains("<svg"))
      XCTAssertGreaterThan(try code.png().count, 50)
      let plan = try SpecQR.estimate("HELLO", options: .init(maxVersion: 5))
      XCTAssertTrue(plan.ok)
      XCTAssertEqual(try SpecQR.getCapacity(version: 1, errorCorrectionLevel: .M, mode: .byte).maxBytes, 14)
      let mixed = try SpecQR.generate(segments: [
         .eci(26), .alphanumeric("ORDER "), .numeric("1234567890"), .byte("-こんにちは"),
      ])
      XCTAssertGreaterThan(mixed.size, 0)
   }
   func testReadmeGS1AndStructuredAppend() throws {
      let elements = try GS1.parseHumanReadable("(01)09501101530003(10)LOT123(17)271231")
      let raw = try GS1.createElementString(elements)
      XCTAssertGreaterThan(try SpecQR.generate(raw, options: .init(gs1: true)).size, 0)
      let link = try GS1.createDigitalLink(elements, options: .init(baseURL: "https://example.com"))
      XCTAssertTrue(GS1.validateDigitalLink(link).ok)
      XCTAssertTrue(GS1.validateElements(elements).ok)
      let set = try SpecQR.generateStructuredAppend(
         String(repeating: "abc", count: 40), options: .init(qrOptions: .init(version: 1), maxSymbols: 16))
      XCTAssertGreaterThan(set.total, 1)
      let render = QRRenderOptions(margin: 4, scale: 8, foreground: "#000", background: "#fff", printDPI: 300)
      XCTAssertFalse(
         try set.symbols[0].renderDiagnostics(options: render).warningDetails.contains { $0.severity == .warning })
      XCTAssertTrue(try set.symbols[0].pngDataURL(options: render).hasPrefix("data:image/png;base64,"))
   }
}
