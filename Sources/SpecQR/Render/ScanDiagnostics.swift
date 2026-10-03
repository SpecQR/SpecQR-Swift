import Foundation

public enum QRDiagnosticValue: Equatable, Sendable {
   case integer(Int)
   case number(Double)
   case string(String)
   case strings([String])
}
public enum QRWarningSeverity: String, Equatable, Sendable { case info, warning }
public struct QRWarning: Equatable, Sendable {
   public let code: String
   public let severity: QRWarningSeverity
   public let message: String
   public let details: [String: QRDiagnosticValue]
}
extension QRPlan {
   /// Inspects quiet zone, contrast and print geometry without constructing codewords or a matrix.
   /// On capacity overflow, dimensions refer to evaluatedVersion, matching the capacity report.
   /// Raster-size warnings belong to a rendered QRCode and are omitted here.
   public func renderDiagnostics(options: QRRenderOptions = .init()) throws -> QRRenderDiagnostics {
      try ScanDiagnostics.make(plan: self, options: options, includeRasterScale: false)
   }
}
internal enum ScanDiagnostics {
   static func make(plan: QRPlan, options: QRRenderOptions, includeRasterScale: Bool) throws -> QRRenderDiagnostics {
      let dimension = try RenderGeometry.dimension(size: plan.evaluatedVersion * 4 + 17, options: options)
      let foreground = RGBAColor.parse(options.foreground)
      let background = RGBAColor.parse(options.background)
      let ratio: Double? =
         if let foreground, let background {
            (max(foreground.luminance, background.luminance) + 0.05)
               / (min(foreground.luminance, background.luminance) + 0.05)
         } else { nil }
      var warnings: [QRWarning] = []
      func append(
         _ code: String, _ severity: QRWarningSeverity, _ message: String, _ details: [String: QRDiagnosticValue]
      ) {
         warnings.append(.init(code: code, severity: severity, message: message, details: details))
      }
      if options.margin < 4 {
         append(
            "QUIET_ZONE_TOO_SMALL", .warning, "QR Code Model 2 readers expect a quiet zone of at least 4 modules.",
            ["margin": .integer(options.margin), "recommendedModules": .integer(4)])
      }
      if let ratio {
         if ratio < 4.5 {
            append(
               "COLOR_CONTRAST_LOW", .warning, "Foreground and background contrast is low for reliable scanning.",
               ["ratio": .number(ratio), "recommendedMinimumRatio": .number(4.5)])
         } else if ratio < 7 {
            append(
               "COLOR_CONTRAST_MODERATE", .info,
               "Contrast is acceptable, but stronger contrast is recommended for damaged, small, or printed QR codes.",
               ["ratio": .number(ratio), "strongRecommendedRatio": .number(7)])
         }
      } else {
         append(
            "COLOR_CONTRAST_UNKNOWN", .info,
            "Color contrast could not be inspected because one or both colors are not simple hex/named colors.",
            ["foreground": .string(options.foreground), "background": .string(options.background)])
      }
      if let foreground, let background, foreground.a < 255 || background.a < 255 {
         append(
            "COLOR_ALPHA_USED", .warning, "Transparent foreground or background colors can reduce scanner reliability.",
            ["foregroundAlpha": .integer(Int(foreground.a)), "backgroundAlpha": .integer(Int(background.a))])
      }
      if plan.remainingBits >= 0 && Double(plan.remainingBits) / Double(plan.capacityBits) < 0.05 {
         append(
            "CAPACITY_NEAR_LIMIT", .info, "The selected version is close to full capacity.",
            ["remainingBits": .integer(plan.remainingBits), "capacityBits": .integer(plan.capacityBits)])
      }
      let module = options.printDPI.map { Double(options.scale) / $0 * 25.4 }
      if let module, let dpi = options.printDPI, module < 0.25 {
         append(
            "PRINT_MODULE_TOO_SMALL", .warning,
            "The configured scale and DPI produce modules smaller than the print recommendation.",
            ["dpi": .number(dpi), "moduleSizeMm": .number(module), "recommendedMinimumModuleSizeMm": .number(0.25)])
      }
      if includeRasterScale && options.scale < 3 {
         append(
            "RASTER_SCALE_SMALL", .info,
            "Raster output with fewer than 3 pixels per module may scan poorly after resizing.",
            ["scale": .integer(options.scale), "recommendedMinimumScale": .integer(3)])
      }
      let blocking = warnings.filter { $0.severity == .warning }.map(\.code)
      if !blocking.isEmpty {
         append(
            "SCAN_RISK", .warning, "One or more settings may reduce scan reliability.",
            ["blockingWarnings": .strings(blocking)])
      }
      return QRRenderDiagnostics(
         dimension: dimension, quietZoneModules: options.margin, contrastRatio: ratio,
         foregroundAlpha: ratio == nil ? nil : foreground.map { Double($0.a) },
         backgroundAlpha: ratio == nil ? nil : background.map { Double($0.a) },
         moduleSizeMM: module, symbolSizeMM: options.printDPI.map { Double(dimension) / $0 * 25.4 },
         warnings: warnings.map(\.code), warningDetails: warnings)
   }
}
