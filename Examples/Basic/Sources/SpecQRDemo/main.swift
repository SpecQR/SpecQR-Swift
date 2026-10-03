import Foundation
import SpecQR

let code = try SpecQR.generate("https://example.com", options: .init(errorCorrectionLevel: .Q))
let png = try code.png()
let svg = try code.svg()
print("URL: version \(code.version), mask \(code.maskPattern), PNG \(png.count) bytes, SVG \(svg.utf8.count) bytes")

let binary = try SpecQR.generate(Data([0, 127, 128, 255]))
print("Binary: \(binary.planning.inputBytes) bytes, \(binary.diagnostics.dataBitLength) bits")

let elements = try GS1.parseHumanReadable("(01)09501101530003(10)LOT%123(17)271231")
let raw = try GS1.createElementString(elements)
let gs1 = try SpecQR.generate(raw, options: .init(gs1: true))
let digitalLink = try GS1.createDigitalLink(elements, options: .init(baseURL: "https://example.com"))
print("GS1: \(gs1.planning.mode.rawValue) mode safely preserves literal percent")
print("Digital Link: \(digitalLink)")

let set = try SpecQR.generateStructuredAppend(
   String(repeating: "abc", count: 40), options: .init(qrOptions: .init(version: 1)))
print("Structured Append: \(set.total) symbols, parity \(set.parity)")

let plan = try SpecQR.estimate("HELLO", options: .init(maxVersion: 5))
let scan = try plan.renderDiagnostics(options: .init(printDPI: 300))
print("Planning: \(plan.capacityBits) capacity bits, \(scan.warningDetails.count) warnings")
