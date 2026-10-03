#if canImport(CoreGraphics)
   import Foundation
   import CoreGraphics

   extension QRCode {
      /// Produces an un-interpolated Core Graphics image. Requires verification on an Apple SDK; Linux does not compile this branch.
      public func cgImage(options: QRRenderOptions = .init()) throws -> CGImage {
         let bitmap = try rgba(options: options)
         let data = Data(bitmap.pixels) as CFData
         guard let provider = CGDataProvider(data: data),
            let image = CGImage(
               width: bitmap.width, height: bitmap.height, bitsPerComponent: 8,
               bitsPerPixel: 32, bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
               decode: nil, shouldInterpolate: false, intent: .defaultIntent)
         else {
            throw QRRenderError.invalidOptions("Core Graphics could not construct the image")
         }
         return image
      }
   }
#endif
