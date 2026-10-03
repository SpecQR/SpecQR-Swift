#if canImport(CoreGraphics) && canImport(Vision)
   import XCTest
   import CoreGraphics
   import Vision
   @testable import SpecQR

   final class ApplePlatformTests: XCTestCase {
      func testCoreGraphicsAndVisionDecode() throws {
         let text = "SpecQR Apple validation 12345"
         let qr = try SpecQR.generate(text)
         let image = try qr.cgImage()
         XCTAssertEqual(image.width, (qr.size + 8) * 8)
         XCTAssertFalse(image.shouldInterpolate)
         let request = VNDetectBarcodesRequest()
         request.symbologies = [.qr]
         #if targetEnvironment(simulator) && os(iOS)
            // iOS 27 simulator revisions 3/4 also miss Apple's own QR control.
            // Revision 2 on CPU exercises real decoding of the unchanged image.
            request.revision = VNDetectBarcodesRequestRevision2
            if #available(iOS 17.0, *) {
               let stages = try request.supportedComputeStageDevices
               XCTAssertFalse(stages.isEmpty)
               for (stage, devices) in stages {
                  let cpu = try XCTUnwrap(
                     devices.first {
                        if case .cpu = $0 { return true }
                        return false
                     })
                  request.setComputeDevice(cpu, for: stage)
               }
            } else {
               request.usesCPUOnly = true
            }
         #endif
         try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
         XCTAssertEqual(request.results?.first?.payloadStringValue, text)
      }
   }
#endif
