import CoreGraphics
import Foundation
import ImageIO
import SpecQR
import Testing
import Vision

/// Independent public-API consumer checks. Framework imports are unconditional:
/// an unavailable Apple framework is a build failure, never a silently skipped pass.
@Suite(.serialized)
struct AppleValidationTests {
   @Test
   func coreGraphicsPreservesStraightRGBAAndOwnsStorage() throws {
      let options = QRRenderOptions(margin: 3, scale: 2, foreground: "#12345678", background: "#aBcDeF09")
      let expected = try SpecQR.generate("storage lifetime 123").rgba(options: options)
      let retained: CGImage = try autoreleasepool {
         let transient = try SpecQR.generate("storage lifetime 123")
         return try transient.cgImage(options: options)
      }
      #expect(retained.width == expected.width)
      #expect(retained.height == expected.height)
      #expect(retained.bitsPerComponent == 8)
      #expect(retained.bitsPerPixel == 32)
      #expect(retained.bytesPerRow == expected.width * 4)
      #expect(retained.alphaInfo == .last)
      #expect(retained.colorSpace?.model == .rgb)
      #expect(!retained.shouldInterpolate)
      let stored = try #require(retained.dataProvider?.data)
      #expect(Array(stored as Data) == expected.pixels)
      #expect(Array((stored as Data).prefix(4)) == [171, 205, 239, 9])
      #expect(expected.pixels.contains(120))
      // The QRCode, pixel array, temporary Data and autorelease pool have gone
      // out of scope. Drawing also proves the provider's backing storage lives.
      let raster = try renderedRGBA(retained)
      #expect(raster.count == expected.width * expected.height * 4)
      #expect(raster[3] == 9)
   }

   @Test
   func imageIODecodesActualPNGToEveryOriginalPixel() throws {
      let code = try SpecQR.generate("PNG reader: 0123456789 / RGB")
      for margin in [0, 4] {
         for scale in [1, 3] {
            let options = QRRenderOptions(margin: margin, scale: scale, foreground: "#123456", background: "#abcdef")
            let expected = try code.rgba(options: options)
            let source = try #require(CGImageSourceCreateWithData(try code.png(options: options) as CFData, nil))
            #expect(CGImageSourceGetCount(source) == 1)
            #expect((CGImageSourceGetType(source) as String?) == "public.png")
            let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(decoded.width == expected.width)
            #expect(decoded.height == expected.height)
            #expect(try renderedRGBA(decoded) == expected.pixels)
         }
      }
   }

   @Test
   func visionDecodesDirectCGImageAndPNGIncludingUTF8() throws {
      let inputs = [
         "SpecQR Apple validation 12345",
         "https://example.com/path?x=1&text=percent%25",
         "日本語 漢字 かな カナ",
         "UTF-8: café 🙂 e\u{0301}",
         String(repeating: "0123456789", count: 30),
      ]
      for text in inputs {
         let code = try SpecQR.generate(text, options: .init(errorCorrectionLevel: .Q, eci: 26))
         let direct = try decodedText(image: code.cgImage())
         let png = try decodedText(png: code.png())
         // UTF-8 bytes expose normalization changes that String equality hides.
         #expect(Array(direct.utf8) == Array(text.utf8))
         #expect(Array(png.utf8) == Array(text.utf8))
      }
   }

   @Test
   func visionPreservesGS1LiteralPercentAndSeparators() throws {
      let inputs = [
         "10ABC%DEF",
         "10ABC%%DEF",
         "010950110153000310LOT%123\u{1D}17271231",
      ]
      for text in inputs {
         let code = try SpecQR.generate(text, options: .init(gs1: true))
         #expect(code.segments.filter { !$0.isControl } == [.byteText(text)])
         #expect(Array(try decodedText(image: code.cgImage()).utf8) == Array(text.utf8))
         #expect(Array(try decodedText(png: code.png()).utf8) == Array(text.utf8))
      }
      let lowLevel = try SpecQR.generate(segments: [.fnc1, .alphanumeric("10ABC%%DEF")])
      #expect(try decodedText(image: lowLevel.cgImage()) == "10ABC%DEF")
   }

   @Test
   func coreGraphicsRejectsInvalidOptionsBeforeAllocation() throws {
      let code = try SpecQR.generate("negative rendering")
      let invalid: [QRRenderOptions] = [
         .init(margin: -1), .init(scale: 0), .init(scale: -1),
         .init(margin: Int.max), .init(scale: Int.max), .init(scale: 100),
         .init(foreground: "not-a-color"), .init(background: "#gggggg"),
         .init(printDPI: .infinity), .init(printDPI: .nan), .init(printDPI: 0),
         .init(foreground: String(repeating: "a", count: 65_537)),
      ]
      for options in invalid {
         #expect(throws: QRRenderError.self) { _ = try code.cgImage(options: options) }
         #expect(throws: QRRenderError.self) { _ = try code.png(options: options) }
      }
      let v40 = try SpecQR.generate("version forty", options: .init(version: 40))
      #expect(try v40.cgImage().width == (177 + 8) * 8)
   }

   @Test
   func bothFNC1FormsPreservePercentSafetyAcrossPlanningAndGeneration() throws {
      for secondPosition in [false, true] {
         for optimize in [false, true] {
            for text in ["10ABC%DEF", "10ABC%%DEF", "10ABC%DEF\u{1D}17271231"] {
               let options = QROptions(
                  errorCorrectionLevel: .Q, version: 4, maskPattern: 3,
                  optimizeSegments: optimize, gs1: !secondPosition, fnc1Second: secondPosition ? "A" : nil)
               let code = try SpecQR.generate(text, options: options)
               let plan = try SpecQR.estimate(text, options: options)
               let control: QRSegment = secondPosition ? .fnc1Second("A") : .fnc1
               let reference = try SpecQR.generate(
                  segments: [control, .byteText(text)],
                  options: .init(errorCorrectionLevel: .Q, version: 4, maskPattern: 3))
               #expect(plan.ok)
               #expect(plan.segments == code.segments)
               #expect(code.segments == [control, .byteText(text)])
               #expect(code.matrix == reference.matrix)
               var explicitByte = options
               explicitByte.mode = .byte
               #expect(try SpecQR.generate(text, options: explicitByte).matrix == code.matrix)
               var unsafeAlpha = options
               unsafeAlpha.mode = .alphanumeric
               #expect(throws: QRError.self) { _ = try SpecQR.generate(text, options: unsafeAlpha) }
               #expect(throws: QRError.self) { _ = try SpecQR.estimate(text, options: unsafeAlpha) }
               #expect(throws: QRError.self) {
                  _ = try SpecQR.generate(segments: [.alphanumeric("10ABC%DEF")], options: options)
               }
            }
         }
      }
   }

   @Test
   func structuredAppendHeadersShuffledMergeAndCorruption() throws {
      let bytes = Array(UInt8(0)...UInt8(120)) + [255, 128, 0]
      let set = try SpecQR.generateStructuredAppend(
         bytes,
         options: .init(qrOptions: .init(errorCorrectionLevel: .L, version: 2, maskPattern: 5), diagnostics: true))
      #expect((2...16).contains(set.total))
      #expect(set.symbols.count == set.total)
      #expect(set.parity == bytes.reduce(0, ^))
      var parts: [QRStructuredAppendPart] = []
      for (offset, symbol) in set.symbols.enumerated() {
         let diagnostic = set.diagnostics.symbols[offset]
         #expect(symbol.segments.first == .structuredAppend(index: offset + 1, total: set.total, parity: set.parity))
         #expect(diagnostic.sequenceIndicator == (offset << 4) | (set.total - 1))
         #expect(
            symbol.segments.dropFirst().flatMap { $0.bytes ?? [] }
               == Array(bytes[diagnostic.byteStart..<diagnostic.byteStart + diagnostic.byteLength]))
         parts.append(
            .init(
               index: offset + 1, total: set.total, parity: set.parity,
               bytes: Array(bytes[diagnostic.byteStart..<diagnostic.byteStart + diagnostic.byteLength])))
         #expect(try symbol.cgImage().width == (symbol.size + 8) * 8)
      }
      let merged = try SpecQR.mergeStructuredAppendParts(Array(parts.reversed()))
      #expect(merged.data == .bytes(bytes))
      #expect(merged.diagnostics.parityCheck.matches)
      #expect(merged.parts.map(\.index) == Array(1...set.total))
      #expect(throws: QRError.self) { _ = try SpecQR.mergeStructuredAppendParts(Array(parts.dropLast())) }
      #expect(throws: QRError.self) { _ = try SpecQR.mergeStructuredAppendParts(parts + [parts[0]]) }
      var corrupt = parts
      var changed = parts[0].data.canonicalBytes
      changed[0] ^= 1
      corrupt[0] = .init(index: 1, total: set.total, parity: set.parity, bytes: changed)
      #expect(throws: QRError.self) { _ = try SpecQR.mergeStructuredAppendParts(corrupt) }
      corrupt[0] = .init(index: 1, total: set.total, parity: set.parity ^ 1, bytes: parts[0].data.canonicalBytes)
      #expect(throws: QRError.self) { _ = try SpecQR.mergeStructuredAppendParts(corrupt) }
   }

   @Test
   func concurrentCoreGraphicsRenderingMaintainsValueIsolation() async throws {
      let inputs = ["HELLO", "漢字123", "https://example.com", "🙂 e\u{0301}"]
      let expected = try inputs.map { try SpecQR.generate($0) }
      let options = QRRenderOptions(scale: 2, foreground: "#12345678", background: "#abcdef90")
      let expectedPixels = try expected.map { try $0.rgba(options: options).pixels }
      let outcomes = try await withThrowingTaskGroup(of: Bool.self, returning: [Bool].self) { group in
         for task in 0..<32 {
            group.addTask {
               let index = task % inputs.count
               let code = try SpecQR.generate(inputs[index])
               var independent = code.matrix
               independent[0][0].toggle()
               let image = try code.cgImage(options: options)
               guard let data = image.dataProvider?.data else { return false }
               return code == expected[index] && independent != code.matrix
                  && Array(data as Data) == expectedPixels[index]
            }
         }
         var results: [Bool] = []
         for try await result in group { results.append(result) }
         return results
      }
      #expect(outcomes.count == 32)
      #expect(outcomes.allSatisfy { $0 })
   }
}

private func decodedText(image: CGImage) throws -> String {
   let request = VNDetectBarcodesRequest()
   request.symbologies = [.qr]
   try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
   let results = try #require(request.results)
   #expect(results.count == 1)
   let barcode = try #require(results.first)
   #expect(barcode.symbology == .qr)
   return try #require(barcode.payloadStringValue)
}

private func decodedText(png: Data) throws -> String {
   let request = VNDetectBarcodesRequest()
   request.symbologies = [.qr]
   try VNImageRequestHandler(data: png, options: [:]).perform([request])
   let results = try #require(request.results)
   #expect(results.count == 1)
   let barcode = try #require(results.first)
   #expect(barcode.symbology == .qr)
   return try #require(barcode.payloadStringValue)
}

private func renderedRGBA(_ image: CGImage) throws -> [UInt8] {
   let space = try #require(image.colorSpace)
   let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
   let context = try #require(
      CGContext(
         data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
         bytesPerRow: image.width * 4, space: space, bitmapInfo: info))
   context.interpolationQuality = .none
   context.setBlendMode(.copy)
   context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
   let data = try #require(context.data)
   return Array(
      UnsafeBufferPointer(
         start: data.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
}
