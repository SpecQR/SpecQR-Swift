import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreML
import Darwin
import Foundation
import ImageIO
import SpecQR
import Vision

let payload = "SpecQR Apple validation 12345"

func emit(_ data: [String: Any]) {
   let encoded = try! JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])
   print(String(decoding: encoded, as: UTF8.self))
   fflush(nil)
}

func errorDescription(_ error: Error) -> [String: Any] {
   let ns = error as NSError
   return ["domain": ns.domain, "code": ns.code, "description": ns.localizedDescription,
           "userInfo": String(describing: ns.userInfo)]
}

func normalize(_ image: CGImage) -> CGImage {
   let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
   let context = CGContext(data: nil, width: image.width, height: image.height,
      bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
   context.interpolationQuality = .none
   context.setFillColor(CGColor(gray: 1, alpha: 1))
   context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
   context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
   return context.makeImage()!
}

let specQRDefault = try SpecQR.generate(payload).cgImage()
let specQR = try SpecQR.generate(payload).cgImage(options: .init(margin: 6, scale: 10))
let filter = CIFilter.qrCodeGenerator()
filter.message = Data(payload.utf8)
filter.correctionLevel = "M"
let ciQR = filter.outputImage!
let expanded = ciQR.extent.insetBy(dx: -6, dy: -6)
let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: expanded)
let ciOutput = ciQR.composited(over: white).cropped(to: expanded).transformed(by: CGAffineTransform(scaleX: 10, y: 10))
let ciContext = CIContext(options: [.useSoftwareRenderer: true])
let ciGenerated = ciContext.createCGImage(ciOutput, from: ciOutput.extent)!
let images: [(String, CGImage)] = [
   ("SpecQR-original-default", specQRDefault),
   ("SpecQR-direct", specQR), ("SpecQR-normalized", normalize(specQR)),
   ("Apple-CoreImage-direct", ciGenerated), ("Apple-CoreImage-normalized", normalize(ciGenerated)),
]

emit(["event": "environment", "os": ProcessInfo.processInfo.operatingSystemVersionString,
      "payload": payload, "supportedRevisions": Array(VNDetectBarcodesRequest.supportedRevisions),
      "defaultRevision": VNDetectBarcodesRequest.defaultRevision,
      "currentRevision": VNDetectBarcodesRequest.currentRevision])
for (name, image) in images {
   emit(["event": "image", "name": name, "width": image.width, "height": image.height,
         "bitsPerPixel": image.bitsPerPixel, "alphaInfo": image.alphaInfo.rawValue,
         "bitmapInfo": image.bitmapInfo.rawValue, "colorSpace": String(describing: image.colorSpace)])
   for revision in VNDetectBarcodesRequest.supportedRevisions {
      for mode in ["default", "supported-CPU"] {
         var record: [String: Any] = ["event": "result", "source": name, "revision": revision, "mode": mode]
         let start = Date()
         do {
            let request = VNDetectBarcodesRequest()
            request.revision = revision
            request.symbologies = [.qr]
            let stages = try request.supportedComputeStageDevices
            var devicesRecord: [String: [String]] = [:]
            for (stage, devices) in stages {
               devicesRecord[stage.rawValue] = devices.map { String(describing: $0) }
               if mode == "supported-CPU" {
                  guard let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) else {
                     throw NSError(domain: "VisionProbe", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "No supported CPU at \(stage.rawValue)"])
                  }
                  request.setComputeDevice(cpu, for: stage)
               }
            }
            record["supportedStageDevices"] = devicesRecord
            try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
            let results = request.results
            record["resultsIsNil"] = results == nil
            record["count"] = results?.count ?? -1
            record["payloads"] = results?.map { $0.payloadStringValue ?? "<nil>" } ?? []
            record["exactPayloadMatch"] = results?.contains { $0.payloadStringValue.map { Array($0.utf8) == Array(payload.utf8) } ?? false } ?? false
            record["observations"] = results?.map { ["symbology": $0.symbology.rawValue, "confidence": $0.confidence] } ?? []
         } catch {
            record["error"] = errorDescription(error)
         }
         record["seconds"] = Date().timeIntervalSince(start)
         emit(record)
      }
   }
}
