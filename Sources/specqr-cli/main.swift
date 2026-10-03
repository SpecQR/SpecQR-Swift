import Foundation
import SpecQR

struct Options: Decodable {
   var errorCorrectionLevel: ErrorCorrectionLevel?
   var version: Int?
   var minVersion: Int?
   var maxVersion: Int?
   var maskPattern: Int?
   var mode: QRMode?
   var optimizeSegments: Bool?
   var boostErrorCorrection: Bool?
   var eci: Int?
   var gs1: Bool?
   var fnc1Second: String?
   var structuredAppend: Header?
   var qr: QROptions {
      QROptions(
         errorCorrectionLevel: errorCorrectionLevel ?? .M, version: version,
         minVersion: minVersion ?? 1, maxVersion: maxVersion ?? 40, maskPattern: maskPattern,
         mode: mode ?? .auto, optimizeSegments: optimizeSegments ?? true,
         boostErrorCorrection: boostErrorCorrection ?? false, eci: eci, gs1: gs1 ?? false,
         fnc1Second: fnc1Second,
         structuredAppend: structuredAppend.map { .init(index: $0.index, total: $0.total, parity: $0.parity) })
   }
}
struct Header: Decodable {
   let index: Int
   let total: Int
   let parity: UInt8
}
struct Segment: Decodable {
   let mode: String
   var text: String?
   var bytes: [UInt8]?
   var assignmentNumber: Int?
   var applicationIndicator: String?
   var index: Int?
   var total: Int?
   var parity: UInt8?
   func value() throws -> QRSegment {
      switch mode {
      case "numeric":
         guard let text else { throw QRError.invalidInput("numeric.text is required") }
         return .numeric(text)
      case "alphanumeric":
         guard let text else { throw QRError.invalidInput("alphanumeric.text is required") }
         return .alphanumeric(text)
      case "kanji":
         guard let text else { throw QRError.invalidInput("kanji.text is required") }
         return .kanji(text)
      case "byte":
         if let bytes { return .byte(bytes) }
         if let text { return .byteText(text) }
         throw QRError.invalidInput("byte.text or byte.bytes is required")
      case "eci":
         guard let assignmentNumber else { throw QRError.invalidInput("assignmentNumber is required") }
         return .eci(assignmentNumber)
      case "fnc1": return .fnc1
      case "fnc1-second":
         guard let applicationIndicator else { throw QRError.invalidInput("applicationIndicator is required") }
         return .fnc1Second(applicationIndicator)
      case "structured-append":
         guard let index, let total, let parity else { throw QRError.invalidInput("index/total/parity are required") }
         return .structuredAppend(index: index, total: total, parity: parity)
      default: throw QRError.invalidMode("Unknown segment mode")
      }
   }
}
struct RenderOptions: Decodable {
   var margin: Int?
   var scale: Int?
   var foreground: String?
   var background: String?
   var printDPI: Double?
   var qr: QRRenderOptions {
      .init(
         margin: margin ?? 4, scale: scale ?? 8, foreground: foreground ?? "#000000",
         background: background ?? "#ffffff", printDPI: printDPI)
   }
}
struct Request: Decodable {
   var command: String?
   var text: String?
   var bytes: [UInt8]?
   var segments: [Segment]?
   var options: Options?
   var render: RenderOptions?
   var format: String?
}
func planJSON(_ p: QRPlan) -> [String: Any] {
   [
      "ok": p.ok, "selectedVersion": p.selectedVersion as Any? ?? NSNull(),
      "evaluatedVersion": p.evaluatedVersion, "errorCorrectionLevel": p.errorCorrectionLevel.rawValue,
      "mode": p.mode.rawValue, "dataBitLength": p.dataBitLength, "capacityBits": p.capacityBits,
      "remainingBits": p.remainingBits, "inputBytes": p.inputBytes,
      "versionSelection": p.versionSelection,
      "segments": p.segmentDiagnostics.map { d -> [String: Any] in
         var result: [String: Any] = [
            "mode": d.mode.rawValue, "characterCount": d.characterCount, "byteCount": d.byteCount,
            "bitLength": d.bitLength,
         ]
         if let n = d.assignmentNumber { result["assignmentNumber"] = n }
         if let s = d.applicationIndicator { result["applicationIndicator"] = s }
         if let n = d.applicationIndicatorCodeword { result["applicationIndicatorCodeword"] = n }
         if let h = d.structuredAppend {
            result["index"] = h.index
            result["total"] = h.total
            result["parity"] = Int(h.parity)
         }
         return result
      },
   ]
}
func handle(_ r: Request) throws -> [String: Any] {
   let o = r.options?.qr ?? .init()
   let segments = try r.segments?.map { try $0.value() }
   if r.command == "estimate" {
      let p: QRPlan
      if let segments {
         p = try SpecQR.analyzeSegments(segments, options: o)
      } else if let bytes = r.bytes {
         p = try SpecQR.estimate(bytes, options: o)
      } else {
         p = try SpecQR.estimate(r.text ?? "", options: o)
      }
      return planJSON(p)
   }
   let code: QRCode
   if let segments {
      code = try SpecQR.generate(segments: segments, options: o)
   } else if let bytes = r.bytes {
      code = try SpecQR.generate(bytes, options: o)
   } else {
      code = try SpecQR.generate(r.text ?? "", options: o)
   }
   if r.command == "render" {
      let ro = r.render?.qr ?? .init()
      switch r.format ?? "svg" {
      case "svg": return ["output": try code.svg(options: ro)]
      case "svg-data-url": return ["output": try code.svgDataURL(options: ro)]
      case "png", "png-data-url": return ["output": try code.pngDataURL(options: ro)]
      case "rgba":
         let image = try code.rgba(options: ro)
         return ["width": image.width, "height": image.height, "pixels": image.pixels.map(Int.init)]
      default: throw QRError.invalidInput("Unknown output format")
      }
   }
   var result = planJSON(code.planning)
   result["matrix"] = code.matrix.map { $0.map { $0 ? "1" : "0" }.joined() }
   result["version"] = code.version
   result["maskPattern"] = code.maskPattern
   result["maskPenalty"] = code.diagnostics.maskPenalty
   result["maskPenalties"] = code.diagnostics.maskPenalties.map {
      ["maskPattern": $0.maskPattern, "penalty": $0.penalty]
   }
   result["dataCodewords"] = code.dataCodewords.map(Int.init)
   result["codewords"] = code.codewords.map(Int.init)
   return result
}
func printJSON(_ value: [String: Any]) throws {
   let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
   print(String(decoding: data, as: UTF8.self))
}
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--help"] {
   print(
      "Usage: specqr-cli TEXT\n       specqr-cli --png OUTPUT.png TEXT\n       specqr-cli --json-lines < requests.jsonl\nJSON requests: {text,bytes,segments,options,command:generate|estimate|render,format,render}."
   )
} else if arguments == ["--json-lines"] {
   while let line = readLine() {
      do { try printJSON(handle(JSONDecoder().decode(Request.self, from: Data(line.utf8)))) } catch {
         try printJSON(["error": String(describing: error), "code": (error as? QRError)?.code ?? "ERROR"])
      }
   }
} else {
   do {
      if arguments.count == 3 && arguments[0] == "--png" {
         try SpecQR.generate(arguments[2]).png().write(to: URL(fileURLWithPath: arguments[1]), options: .atomic)
      } else if arguments.count == 1 {
         print(try SpecQR.generate(arguments[0]).svg())
      } else {
         throw QRError.invalidInput("Use --help for usage")
      }
   } catch {
      FileHandle.standardError.write(Data(("\(error)\n").utf8))
      exit(1)
   }
}
