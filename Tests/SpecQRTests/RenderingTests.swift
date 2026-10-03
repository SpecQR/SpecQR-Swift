import Foundation
import XCTest

@testable import SpecQR

final class RenderingTests: XCTestCase {
   func testSVGAndURLs() throws {
      let code = try SpecQR.generate("HELLO")
      let svg = try code.svg()
      XCTAssertTrue(svg.hasPrefix("<svg xmlns=\"http://www.w3.org/2000/svg\""))
      XCTAssertTrue(svg.contains("width=\"232\""))
      let url = try code.svgDataURL()
      XCTAssertEqual(String(url.dropFirst("data:image/svg+xml;charset=utf-8,".count)).removingPercentEncoding, svg)
      let png = try code.png()
      let dataURL = try code.pngDataURL()
      XCTAssertEqual(Data(base64Encoded: String(dataURL.dropFirst("data:image/png;base64,".count))), png)
      let escaped = try code.svg(options: .init(foreground: "\"<&>"))
      XCTAssertTrue(escaped.contains("&quot;&lt;&amp;&gt;"))
   }
   func testRasterMatchesEveryModule() throws {
      let code = try SpecQR.generate("0123456789")
      for margin in [0, 4, 8] {
         for scale in [1, 3, 8] {
            let image = try code.rgba(
               options: .init(margin: margin, scale: scale, foreground: "#1234", background: "#abCDef01"))
            XCTAssertEqual(image.width, (code.size + margin * 2) * scale)
            for y in 0..<image.height {
               for x in 0..<image.width {
                  let mx = x / scale - margin
                  let my = y / scale - margin
                  let dark = mx >= 0 && my >= 0 && mx < code.size && my < code.size && code.matrix[my][mx]
                  let offset = (y * image.width + x) * 4
                  let expected: [UInt8] = dark ? [17, 34, 51, 68] : [171, 205, 239, 1]
                  XCTAssertEqual(Array(image.pixels[offset..<offset + 4]), expected)
               }
            }
         }
      }
   }
   func testPNGStructureCRCAndStoredDeflate() throws {
      let code = try SpecQR.generate("PNG regression")
      let image = try code.rgba(options: .init(scale: 2))
      let png = Array(try code.png(options: .init(scale: 2)))
      XCTAssertEqual(Array(png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
      func u32(_ bytes: [UInt8]) -> UInt32 { bytes.reduce(0) { ($0 << 8) | UInt32($1) } }
      var offset = 8
      var types: [String] = []
      var stream: [UInt8] = []
      while offset < png.count {
         let length = Int(u32(Array(png[offset..<offset + 4])))
         let type = String(decoding: png[offset + 4..<offset + 8], as: UTF8.self)
         let payload = Array(png[offset + 8..<offset + 8 + length])
         XCTAssertEqual(Array(png[offset..<offset + length + 12]), PNGCodec.chunk(type, payload))
         if type == "IHDR" {
            XCTAssertEqual(Int(u32(Array(payload[0..<4]))), image.width)
            XCTAssertEqual(Array(payload[8...]), [8, 6, 0, 0, 0])
         }
         if type == "IDAT" { stream += payload }
         types.append(type)
         offset += length + 12
      }
      XCTAssertEqual(types, ["IHDR", "IDAT", "IEND"])
      XCTAssertEqual(Array(stream.prefix(2)), [0x78, 1])
      var cursor = 2
      var raw: [UInt8] = []
      while true {
         let final = stream[cursor] == 1
         let length = Int(stream[cursor + 1]) | Int(stream[cursor + 2]) << 8
         let inverse = Int(stream[cursor + 3]) | Int(stream[cursor + 4]) << 8
         XCTAssertEqual(length ^ inverse, 65535)
         raw += stream[cursor + 5..<cursor + 5 + length]
         cursor += length + 5
         if final { break }
      }
      XCTAssertEqual(cursor + 4, stream.count)
      var a: UInt32 = 1
      var b: UInt32 = 0
      for byte in raw {
         a = (a + UInt32(byte)) % 65521
         b = (b + a) % 65521
      }
      XCTAssertEqual(u32(Array(stream[cursor...])), b << 16 | a)
      for row in 0..<image.height {
         XCTAssertEqual(raw[row * (image.width * 4 + 1)], 0)
         XCTAssertEqual(
            Array(raw[(row * (image.width * 4 + 1) + 1)..<((row + 1) * (image.width * 4 + 1))]),
            Array(image.pixels[row * image.width * 4..<(row + 1) * image.width * 4]))
      }
   }
   func testResourceAndColorValidation() throws {
      let code = try SpecQR.generate("Limits")
      for options in [
         QRRenderOptions(margin: -1), .init(scale: 0), .init(margin: Int.max), .init(scale: Int.max),
         .init(printDPI: .infinity), .init(printDPI: 0),
      ] {
         XCTAssertThrowsError(try code.svg(options: options))
         XCTAssertThrowsError(try code.rgba(options: options))
      }
      XCTAssertThrowsError(try code.png(options: .init(scale: 100)))
      XCTAssertThrowsError(try code.png(options: .init(foreground: "red")))
      XCTAssertThrowsError(try code.svg(options: .init(foreground: String(repeating: "a", count: 65537))))
      for value in ["#00", "#ggg", "rgb(0,0,0)", "", "#fffff"] { XCTAssertNil(RGBAColor.parse(value)) }
      for value in ["black", " WHITE ", "transparent", "#123", "#1234", "#112233", "#11223344"] {
         XCTAssertNotNil(RGBAColor.parse(value))
      }
   }
   func testPlanningWarningsWithoutMatrixAndOverflow() throws {
      let plan = try SpecQR.estimate(String(repeating: "A", count: 200), options: .init(version: 1))
      XCTAssertFalse(plan.ok)
      let diagnostics = try plan.renderDiagnostics(
         options: .init(margin: 1, scale: 1, foreground: "#0008", printDPI: 300))
      XCTAssertFalse(diagnostics.warnings.contains("CAPACITY_NEAR_LIMIT"))
      XCTAssertFalse(diagnostics.warnings.contains("RASTER_SCALE_SMALL"))
      XCTAssertTrue(diagnostics.warnings.contains("SCAN_RISK"))
      XCTAssertEqual(diagnostics.foregroundAlpha, 136)
      XCTAssertEqual(diagnostics.warningDetails.first?.severity, .warning)
      XCTAssertEqual(diagnostics.warningDetails.first?.details["margin"], .integer(1))
      XCTAssertEqual(diagnostics.dimension, 23)
   }
   func testScanWarningsAndCanvas() throws {
      let code = try SpecQR.generate("Warnings")
      let warnings = try code.renderDiagnostics(
         options: .init(margin: 1, scale: 1, foreground: "#7777", background: "#999", printDPI: 300))
      for warning in [
         "QUIET_ZONE_TOO_SMALL", "COLOR_CONTRAST_LOW", "COLOR_ALPHA_USED", "PRINT_MODULE_TOO_SMALL",
         "RASTER_SCALE_SMALL", "SCAN_RISK",
      ] { XCTAssertTrue(warnings.warnings.contains(warning)) }
      XCTAssertEqual(try code.renderDiagnostics().contrastRatio!, 21, accuracy: 0.001)
      var canvas = RecordingCanvas()
      try code.draw(to: &canvas, options: .init(scale: 2))
      XCTAssertEqual(canvas.width, (code.size + 8) * 2)
      XCTAssertEqual(canvas.rectangles, code.matrix.flatMap { $0 }.filter { $0 }.count + 1)
   }
}
private struct RecordingCanvas: QRCanvas {
   var width = 0, height = 0, rectangles = 0
   mutating func resize(width: Int, height: Int) {
      self.width = width
      self.height = height
   }
   mutating func fillRectangle(x: Int, y: Int, width: Int, height: Int, color: String) { rectangles += 1 }
}
