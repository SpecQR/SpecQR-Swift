import Foundation

/// Portable rendering settings. A four-module quiet zone is recommended for scanning.
public struct QRRenderOptions: Sendable, Equatable {
   public var margin: Int
   public var scale: Int
   public var foreground: String
   public var background: String
   public var printDPI: Double?
   public init(
      margin: Int = 4, scale: Int = 8, foreground: String = "#000000", background: String = "#ffffff",
      printDPI: Double? = nil
   ) {
      self.margin = margin
      self.scale = scale
      self.foreground = foreground
      self.background = background
      self.printDPI = printDPI
   }
}

public enum QRRenderError: Error, Sendable, Equatable, CustomStringConvertible {
   case invalidOptions(String)
   case invalidColor(String)
   case resourceLimit(String)
   public var description: String {
      switch self {
      case .invalidOptions(let s), .invalidColor(let s), .resourceLimit(let s): return s
      }
   }
}

public struct QRRGBAImage: Sendable, Equatable {
   public let width: Int
   public let height: Int
   /// Row-major, straight (unpremultiplied) RGBA8 pixels.
   public let pixels: [UInt8]
}

public struct QRRenderDiagnostics: Sendable, Equatable {
   public let dimension: Int
   public let quietZoneModules: Int
   public let contrastRatio: Double?
   public let foregroundAlpha: Double?
   public let backgroundAlpha: Double?
   public let moduleSizeMM: Double?
   public let symbolSizeMM: Double?
   public let warnings: [String]
   public let warningDetails: [QRWarning]
   public var isQuietZoneSufficient: Bool { quietZoneModules >= 4 }
   public var isColorInspectable: Bool { contrastRatio != nil }
   public var isColorStrong: Bool { (contrastRatio ?? 0) >= 7 }
   public var isColorSufficient: Bool {
      (contrastRatio ?? 0) >= 4.5 && foregroundAlpha == 255 && backgroundAlpha == 255
   }
   public var recommendedMinimumModuleSizeMM: Double { 0.25 }
   public var isModuleSizeSufficient: Bool? { moduleSizeMM.map { $0 >= 0.25 } }
}

/// A minimal canvas adapter for host UI frameworks. All rectangles use integer pixels.
public protocol QRCanvas {
   mutating func resize(width: Int, height: Int) throws
   mutating func fillRectangle(x: Int, y: Int, width: Int, height: Int, color: String) throws
}

extension QRCode {
   public func svg(options: QRRenderOptions = .init()) throws -> String {
      let dimension = try RenderGeometry.dimension(size: size, options: options)
      let darkCount = matrix.reduce(0) { $0 + $1.filter { $0 }.count }
      let bound =
         512 + options.foreground.utf8.count * 6 + options.background.utf8.count * 6
         + darkCount * (7 + String(dimension).count * 2 + String(options.scale).count * 3)
      guard bound <= 8 * 1024 * 1024 else { throw QRRenderError.resourceLimit("SVG exceeds 8 MiB character budget") }
      func escape(_ value: String) -> String {
         value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
      }
      var path = ""
      path.reserveCapacity(bound)
      for y in 0..<size {
         for x in 0..<size where matrix[y][x] {
            path +=
               "M\((x + options.margin) * options.scale),\((y + options.margin) * options.scale)h\(options.scale)v\(options.scale)h-\(options.scale)z"
         }
      }
      return
         "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(dimension)\" height=\"\(dimension)\" viewBox=\"0 0 \(dimension) \(dimension)\" role=\"img\"><rect width=\"100%\" height=\"100%\" fill=\"\(escape(options.background))\"/><path fill=\"\(escape(options.foreground))\" d=\"\(path)\"/></svg>"
   }

   public func svgDataURL(options: QRRenderOptions = .init()) throws -> String {
      let text = try svg(options: options)
      let allowed = CharacterSet(
         charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
      guard let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) else {
         throw QRRenderError.invalidOptions("SVG could not be percent-encoded")
      }
      guard encoded.utf8.count + 38 <= 32 * 1024 * 1024 else {
         throw QRRenderError.resourceLimit("Data URL exceeds 32 MiB budget")
      }
      return "data:image/svg+xml;charset=utf-8," + encoded
   }

   public func rgba(options: QRRenderOptions = .init()) throws -> QRRGBAImage {
      let dimension = try RenderGeometry.rasterDimension(size: size, options: options)
      let foreground = try RGBAColor.parseRequired(options.foreground)
      let background = try RGBAColor.parseRequired(options.background)
      var pixels = [UInt8](repeating: 0, count: dimension * dimension * 4)
      for y in 0..<dimension {
         let my = y / options.scale - options.margin
         for x in 0..<dimension {
            let mx = x / options.scale - options.margin
            let dark = mx >= 0 && my >= 0 && mx < size && my < size && matrix[my][mx]
            let color = dark ? foreground : background
            let offset = (y * dimension + x) * 4
            pixels[offset] = color.r
            pixels[offset + 1] = color.g
            pixels[offset + 2] = color.b
            pixels[offset + 3] = color.a
         }
      }
      return QRRGBAImage(width: dimension, height: dimension, pixels: pixels)
   }

   /// Dependency-free PNG encoder: RGBA8, filter 0, zlib stored blocks.
   public func png(options: QRRenderOptions = .init()) throws -> Data {
      let image = try rgba(options: options)
      var scanlines = [UInt8]()
      scanlines.reserveCapacity(image.height * (image.width * 4 + 1))
      for row in 0..<image.height {
         scanlines.append(0)
         scanlines.append(contentsOf: image.pixels[(row * image.width * 4)..<((row + 1) * image.width * 4)])
      }
      var zlib: [UInt8] = [0x78, 0x01]
      var offset = 0
      while offset < scanlines.count {
         let length = min(65535, scanlines.count - offset)
         let inverse = UInt16(length) ^ 0xffff
         zlib.append(offset + length == scanlines.count ? 1 : 0)
         zlib.append(UInt8(length & 255))
         zlib.append(UInt8(length >> 8))
         zlib.append(UInt8(inverse & 255))
         zlib.append(UInt8(inverse >> 8))
         zlib.append(contentsOf: scanlines[offset..<(offset + length)])
         offset += length
      }
      var a: UInt32 = 1
      var b: UInt32 = 0
      for byte in scanlines {
         a = (a + UInt32(byte)) % 65521
         b = (b + a) % 65521
      }
      zlib.append(contentsOf: PNGCodec.bigEndian((b << 16) | a))
      var header = PNGCodec.bigEndian(UInt32(image.width)) + PNGCodec.bigEndian(UInt32(image.height))
      header += [8, 6, 0, 0, 0]
      var output: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
      output += PNGCodec.chunk("IHDR", header)
      output += PNGCodec.chunk("IDAT", zlib)
      output += PNGCodec.chunk("IEND", [])
      return Data(output)
   }

   public func pngDataURL(options: QRRenderOptions = .init()) throws -> String {
      "data:image/png;base64," + (try png(options: options)).base64EncodedString()
   }

   public func draw<C: QRCanvas>(to canvas: inout C, options: QRRenderOptions = .init()) throws {
      let dimension = try RenderGeometry.rasterDimension(size: size, options: options)
      try canvas.resize(width: dimension, height: dimension)
      try canvas.fillRectangle(x: 0, y: 0, width: dimension, height: dimension, color: options.background)
      for y in 0..<size {
         for x in 0..<size where matrix[y][x] {
            try canvas.fillRectangle(
               x: (x + options.margin) * options.scale, y: (y + options.margin) * options.scale,
               width: options.scale, height: options.scale, color: options.foreground)
         }
      }
   }

   public func renderDiagnostics(options: QRRenderOptions = .init(), raster: Bool = true) throws -> QRRenderDiagnostics
   {
      try ScanDiagnostics.make(plan: planning, options: options, includeRasterScale: raster)
   }

}

internal enum RenderGeometry {
   static func dimension(size: Int, options: QRRenderOptions) throws -> Int {
      guard options.margin >= 0, options.scale > 0 else {
         throw QRRenderError.invalidOptions("margin must be nonnegative and scale positive")
      }
      guard options.foreground.utf8.count <= 65536, options.background.utf8.count <= 65536 else {
         throw QRRenderError.resourceLimit("Color string exceeds 64 KiB budget")
      }
      if let dpi = options.printDPI, !dpi.isFinite || dpi <= 0 {
         throw QRRenderError.invalidOptions("printDPI must be finite and positive")
      }
      let (margin, overflow1) = options.margin.multipliedReportingOverflow(by: 2)
      let (span, overflow2) = margin.addingReportingOverflow(size)
      let (dimension, overflow3) = span.multipliedReportingOverflow(by: options.scale)
      guard !overflow1, !overflow2, !overflow3, dimension > 0, Int64(dimension) <= 9_007_199_254_740_991 else {
         throw QRRenderError.resourceLimit("Render geometry exceeds safe integer range")
      }
      return dimension
   }
   static func rasterDimension(size: Int, options: QRRenderOptions) throws -> Int {
      let dimension = try dimension(size: size, options: options)
      guard dimension <= 2048 else { throw QRRenderError.resourceLimit("Raster exceeds 4,194,304-pixel budget") }
      return dimension
   }
}

internal struct RGBAColor {
   let r: UInt8, g: UInt8, b: UInt8, a: UInt8
   static func parseRequired(_ value: String) throws -> RGBAColor {
      guard let parsed = parse(value) else {
         throw QRRenderError.invalidColor("Use #RGB, #RGBA, #RRGGBB, #RRGGBBAA, black, white or transparent")
      }
      return parsed
   }
   static func parse(_ value: String) -> RGBAColor? {
      let s = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if s == "black" { return .init(r: 0, g: 0, b: 0, a: 255) }
      if s == "white" { return .init(r: 255, g: 255, b: 255, a: 255) }
      if s == "transparent" { return .init(r: 0, g: 0, b: 0, a: 0) }
      guard s.first == "#" else { return nil }
      let digits = Array(s.dropFirst().utf8)
      guard [3, 4, 6, 8].contains(digits.count),
         digits.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
      else { return nil }
      func nibble(_ d: UInt8) -> UInt8 { d <= 57 ? d - 48 : d - 87 }
      if digits.count <= 4 {
         return .init(
            r: nibble(digits[0]) * 17, g: nibble(digits[1]) * 17, b: nibble(digits[2]) * 17,
            a: digits.count == 4 ? nibble(digits[3]) * 17 : 255)
      }
      func channel(_ index: Int) -> UInt8 { nibble(digits[index]) * 16 + nibble(digits[index + 1]) }
      return .init(r: channel(0), g: channel(2), b: channel(4), a: digits.count == 8 ? channel(6) : 255)
   }
   var luminance: Double {
      func linear(_ channel: UInt8) -> Double {
         let n = Double(channel) / 255
         return n <= 0.03928 ? n / 12.92 : pow((n + 0.055) / 1.055, 2.4)
      }
      return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
   }
}

internal enum PNGCodec {
   static func bigEndian(_ n: UInt32) -> [UInt8] {
      [UInt8(n >> 24), UInt8((n >> 16) & 255), UInt8((n >> 8) & 255), UInt8(n & 255)]
   }
   static func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
      let payload = Array(type.utf8) + data
      var crc: UInt32 = 0xffff_ffff
      for byte in payload {
         crc ^= UInt32(byte)
         for _ in 0..<8 { crc = (crc & 1) == 0 ? crc >> 1 : (crc >> 1) ^ 0xedb8_8320 }
      }
      return bigEndian(UInt32(data.count)) + payload + bigEndian(crc ^ 0xffff_ffff)
   }
}
