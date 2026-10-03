import Foundation

extension SpecQR {
   public static func generate(_ text: String, options: QROptions = .init()) throws -> QRCode {
      try build(estimate(text, options: options), options: options)
   }
   public static func generate(_ bytes: [UInt8], options: QROptions = .init()) throws -> QRCode {
      try build(estimate(bytes, options: options), options: options)
   }
   public static func generate(_ data: Data, options: QROptions = .init()) throws -> QRCode {
      try generate(Array(data), options: options)
   }
   public static func generate(segments: [QRSegment], options: QROptions = .init()) throws -> QRCode {
      try build(analyzeSegments(segments, options: options), options: options)
   }
   public static func generateSegments(_ segments: [QRSegment], options: QROptions = .init()) throws -> QRCode {
      try generate(segments: segments, options: options)
   }
   /// Selects versions and correction levels without building parity or a matrix.
   /// Capacity overflow is returned as an unsuccessful plan; invalid input throws.
   public static func estimate(_ text: String, options: QROptions = .init()) throws -> QRPlan {
      try QRValidation.options(options)
      var gs1Validation: QRGS1ValidationDiagnostics?
      if options.gs1 {
         do {
            let parsed = try GS1.parseElementString(text)
            gs1Validation = .init(
               enabled: true, elementCount: parsed.elements.count, ais: parsed.elements.map(\.ai),
               hasSeparators: parsed.hasSeparators)
         } catch { throw QRError.invalidGS1(error.localizedDescription) }
      }
      // High-level GS1 accepts raw element strings. A literal percent must not
      // be reinterpreted as the FNC1 alphanumeric separator or escape sequence.
      // This intentionally corrects the canonical JS auto-mode behavior.
      var encodingMode = options.mode
      if (options.gs1 || options.fnc1Second != nil) && text.contains("%") {
         if encodingMode == .alphanumeric {
            let message = "Raw FNC1 strings containing literal % require byte mode; use mode: .byte or .auto."
            if options.gs1 { throw QRError.invalidGS1(message) }
            throw QRError.invalidMode(message)
         }
         if encodingMode == .auto { encodingMode = .byte }
      }
      let limitVersion = options.version ?? options.maxVersion
      let count = text.unicodeScalars.count
      let minimumCountBits =
         (options.eci == nil ? [QRMode.numeric, .alphanumeric, .byte, .kanji] : [.numeric, .alphanumeric, .byte]).map {
            QRTables.countBits($0, limitVersion)
         }.min()!
      let controlBits = try SegmentEncoder.applyingOptions([], options: options).reduce(0) {
         $0 + SegmentEncoder.bitLength($1, version: limitVersion)
      }
      // Numeric encoding is a safe lower bound for every allowed text mode.
      // Skip optimization of provably impossible oversized inputs, as upstream does.
      let preflightOverflow =
         4 + minimumCountBits + SegmentEncoder.payloadLength(.numeric, count: count) + controlBits
         > QRTables.dataCodewords(limitVersion, options.errorCorrectionLevel) * 8
      var cached: [Int: [QRSegment]] = [:]
      return try plan(options: options, inputBytes: text.utf8.count, gs1Validation: gs1Validation) { version in
         let band = version < 10 ? 0 : version < 27 ? 1 : 2
         if let segments = cached[band] { return segments }
         let base: [QRSegment]
         if encodingMode != .auto || !options.optimizeSegments || preflightOverflow {
            base = try SegmentOptimizer.single(text, requested: encodingMode, allowKanji: options.eci == nil)
         } else {
            base = SegmentOptimizer.optimized(text, version: version, allowKanji: options.eci == nil)
         }
         let segments = try SegmentEncoder.applyingOptions(base, options: options)
         cached[band] = segments
         return segments
      }
   }
   public static func estimate(_ bytes: [UInt8], options: QROptions = .init()) throws -> QRPlan {
      try QRValidation.options(options)
      guard !options.gs1 else {
         throw QRError.invalidGS1("GS1 input must be a raw GS1 element string, not binary input.")
      }
      guard options.mode == .auto || options.mode == .byte else {
         throw QRError.invalidMode("Binary input requires byte or auto mode.")
      }
      let segments = try SegmentEncoder.applyingOptions([.byte(bytes)], options: options)
      return try plan(options: options, inputBytes: bytes.count) { _ in segments }
   }
   public static func estimate(_ data: Data, options: QROptions = .init()) throws -> QRPlan {
      try estimate(Array(data), options: options)
   }
   public static func analyzeSegments(_ segments: [QRSegment], options: QROptions = .init()) throws -> QRPlan {
      try QRValidation.options(options)
      try QRValidation.controls(segments)
      if (options.gs1 || options.fnc1Second != nil)
         && segments.contains(where: {
            if case .alphanumeric(let text) = $0 { return text.contains("%") }
            return false
         })
      {
         let message =
            "FNC1 options with literal % in an alphanumeric segment are ambiguous; use a byte segment or explicit low-level FNC1 control segments with QR escaping."
         if options.gs1 { throw QRError.invalidGS1(message) }
         throw QRError.invalidMode(message)
      }
      let prepared = try SegmentEncoder.applyingOptions(segments, options: options)
      return try plan(options: options, inputBytes: segments.reduce(0) { $0 + $1.byteCount }) { _ in prepared }
   }
   public static func getCapacity(
      version: Int, errorCorrectionLevel: ErrorCorrectionLevel = .M,
      mode: QRMode? = nil, controlBits: Int = 0
   ) throws -> QRCapacity {
      try QRValidation.version(version)
      guard controlBits >= 0 else { throw QRError.invalidInput("controlBits must be nonnegative.") }
      if let mode, !mode.isData {
         throw QRError.invalidMode("Capacity mode must be numeric, alphanumeric, byte, or kanji.")
      }
      let data = QRTables.dataCodewords(version, errorCorrectionLevel)
      let countBits = mode.map { QRTables.countBits($0, version) }
      let payload = countBits.map { max(0, data * 8 - min(controlBits, data * 8) - 4 - $0) }
      var maximum: Int?
      if let mode, let payload {
         switch mode {
         case .numeric: maximum = payload / 10 * 3 + (payload % 10 >= 7 ? 2 : payload % 10 >= 4 ? 1 : 0)
         case .alphanumeric: maximum = payload / 11 * 2 + (payload % 11 >= 6 ? 1 : 0)
         case .byte: maximum = payload / 8
         case .kanji: maximum = payload / 13
         default: break
         }
      }
      return QRCapacity(
         version: version, errorCorrectionLevel: errorCorrectionLevel, dataCodewords: data,
         totalCodewords: QRTables.rawCodewords(version), mode: mode, characterCountBits: countBits,
         controlBits: controlBits, payloadBits: payload,
         maxCharacters: mode == .byte ? nil : maximum, maxBytes: mode == .byte ? maximum : nil)
   }
   private static func plan(
      options: QROptions, inputBytes: Int, gs1Validation: QRGS1ValidationDiagnostics? = nil,
      create: (Int) throws -> [QRSegment]
   ) throws -> QRPlan {
      let lower = options.version ?? options.minVersion
      let upper = options.version ?? options.maxVersion
      for version in lower...upper {
         let segments = try create(version)
         let bits = segments.reduce(0) { $0 + SegmentEncoder.bitLength($1, version: version) }
         let fits = bits <= QRTables.dataCodewords(version, options.errorCorrectionLevel) * 8
         if !fits && version != upper { continue }
         var level = options.errorCorrectionLevel
         if fits && options.boostErrorCorrection {
            for candidate in ErrorCorrectionLevel.allCases where candidate.ordinal > level.ordinal {
               if bits <= QRTables.dataCodewords(version, candidate) * 8 { level = candidate }
            }
         }
         let selection = options.version != nil ? "fixed" : fits ? "auto-minimum" : "auto-range"
         let reason =
            options.version != nil
            ? "Version \(version) was requested explicitly."
            : fits
               ? "Version \(version) is the smallest version in \(lower)..\(upper) that fits the encoded data at error correction \(options.errorCorrectionLevel.rawValue)."
               : "No version in \(lower)..\(upper) fits the encoded data at error correction \(options.errorCorrectionLevel.rawValue); capacity is reported for version \(version)."
         return QRPlan(
            ok: fits, selectedVersion: fits || options.version != nil ? version : nil, evaluatedVersion: version,
            minVersion: options.minVersion, maxVersion: options.maxVersion,
            errorCorrectionLevel: level, requestedErrorCorrectionLevel: options.errorCorrectionLevel,
            versionSelection: selection, versionSelectionReason: reason, segments: segments,
            segmentDiagnostics: segments.map { SegmentEncoder.diagnostics($0, version: version) },
            dataBitLength: bits, capacityBits: QRTables.dataCodewords(version, level) * 8, inputBytes: inputBytes,
            gs1Validation: gs1Validation
               ?? .init(
                  enabled: segments.contains(.fnc1), elementCount: segments.contains(.fnc1) ? nil : 0, ais: [],
                  hasSeparators: false))
      }
      // The validated inclusive version range always executes at least once.
      throw QRError.invalidVersion("Empty version range.")
   }
   private static func build(_ plan: QRPlan, options: QROptions) throws -> QRCode {
      guard plan.ok, let version = plan.selectedVersion else { throw plan.error! }
      let data = try SegmentEncoder.encode(plan.segments, version: version, level: plan.errorCorrectionLevel)
      let codewords = ReedSolomon.interleave(data, version: version, level: plan.errorCorrectionLevel)
      let built = MatrixBuilder.build(
         codewords: codewords, version: version, level: plan.errorCorrectionLevel, mask: options.maskPattern)
      let diagnostics = QRDiagnostics(
         planning: plan, maskPattern: built.maskPattern, maskPenalty: built.penalty,
         maskPenalties: built.penalties, dataCodewords: data.count,
         errorCorrectionCodewords: codewords.count - data.count, totalCodewords: codewords.count)
      return QRCode(
         matrix: built.matrix, version: version, errorCorrectionLevel: plan.errorCorrectionLevel,
         maskPattern: built.maskPattern, segments: plan.segments, dataCodewords: data, codewords: codewords,
         diagnostics: diagnostics)
   }
}
