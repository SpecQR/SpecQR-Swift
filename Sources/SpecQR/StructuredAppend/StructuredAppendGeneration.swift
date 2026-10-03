import Foundation

extension SpecQR {
   /// Greedily splits text on Unicode scalar boundaries into 2...16 symbols.
   /// Automatic selection chooses the smallest usable version, not the fewest symbols.
   /// Input fitting one header-bearing symbol is rejected; use generate for that input.
   public static func generateStructuredAppend(_ text: String, options: QRStructuredAppendOptions = .init()) throws
      -> QRStructuredAppendResult
   {
      try StructuredAppendEncoder.generate(text: text, options: options)
   }
   public static func generateStructuredAppend(_ bytes: [UInt8], options: QRStructuredAppendOptions = .init()) throws
      -> QRStructuredAppendResult
   {
      try StructuredAppendEncoder.generate(bytes: bytes, options: options)
   }
   public static func generateStructuredAppend(_ bytes: Data, options: QRStructuredAppendOptions = .init()) throws
      -> QRStructuredAppendResult
   {
      try StructuredAppendEncoder.generate(bytes: Array(bytes), options: options)
   }
   /// Preserves numeric, alphanumeric and Kanji segment boundaries. Binary byte segments
   /// split per byte; text byte segments split per Unicode scalar. Control segments are rejected.
   public static func generateSegmentsStructuredAppend(
      _ segments: [QRSegment], options: QRStructuredAppendOptions = .init()
   ) throws -> QRStructuredAppendResult {
      try StructuredAppendEncoder.generate(segments: segments, options: options)
   }
}

internal enum StructuredAppendEncoder {
   /// Minimum costs for numeric remainders 0/1/2, alphanumeric 0/1, Kanji, and byte.
   /// Only bit lengths matter for splitting; final segment tie-breaking stays in the core.
   struct TextBitLengthTracker {
      static let infinity = Int.max / 4
      let version: Int
      var costs = [Int](repeating: infinity, count: 7)
      var best = 0
      mutating func append(_ scalar: Unicode.Scalar) -> Int {
         var next = [Int](repeating: Self.infinity, count: 7)
         if (48...57).contains(scalar.value) {
            next[0] = costs[2] + 3
            next[1] = min(costs[0] + 4, best + 4 + QRTables.countBits(.numeric, version) + 4)
            next[2] = costs[1] + 3
         }
         if SegmentEncoder.alphaValues[scalar.value] != nil {
            next[3] = costs[4] + 5
            next[4] = min(costs[3] + 6, best + 4 + QRTables.countBits(.alphanumeric, version) + 6)
         }
         if KanjiMap.value(scalar) != nil {
            next[5] = min(costs[5], best + 4 + QRTables.countBits(.kanji, version)) + 13
         }
         next[6] = min(costs[6], best + 4 + QRTables.countBits(.byte, version)) + String(scalar).utf8.count * 8
         costs = next
         best = next.min()!
         return best
      }
   }
   struct TextIndex {
      let scalars: [Unicode.Scalar]
      let byteOffsets: [Int]
      /// A provably optimal single mode for the entire input, when one exists.
      let uniformMode: QRMode?
      init(_ text: String) {
         scalars = Array(text.unicodeScalars)
         var offsets = [0]
         offsets.reserveCapacity(scalars.count + 1)
         for scalar in scalars { offsets.append(offsets.last! + String(scalar).utf8.count) }
         byteOffsets = offsets
         if scalars.allSatisfy({ (48...57).contains($0.value) }) {
            uniformMode = .numeric
         } else if scalars.allSatisfy({ SegmentEncoder.alphaValues[$0.value] != nil && !(48...57).contains($0.value) })
         {
            uniformMode = .alphanumeric
         } else if scalars.allSatisfy({ KanjiMap.value($0) != nil }) {
            uniformMode = .kanji
         } else if scalars.allSatisfy({ SegmentEncoder.alphaValues[$0.value] == nil && KanjiMap.value($0) == nil }) {
            uniformMode = .byte
         } else {
            uniformMode = nil
         }
      }
      func text(_ range: Range<Int>) -> String { String(String.UnicodeScalarView(scalars[range])) }
      func byteCount(_ range: Range<Int>) -> Int { byteOffsets[range.upperBound] - byteOffsets[range.lowerBound] }
   }
   struct Descriptor {
      let segment: QRSegment
      let sourceIndex: Int
      let byteStart: Int
      let byteLength: Int
      let unitStart: Int
      let unitCount: Int
      let textIndex: TextIndex?
      init(segment: QRSegment, index: Int, byteStart: Int, unitStart: Int) {
         self.segment = segment
         self.sourceIndex = index
         self.byteStart = byteStart
         self.unitStart = unitStart
         byteLength = canonicalBytes(segment).count
         switch segment {
         case .byte(let bytes):
            unitCount = bytes.count
            textIndex = nil
         case .byteText(let text):
            let textIndex = TextIndex(text)
            self.textIndex = textIndex
            unitCount = textIndex.scalars.count
         default:
            unitCount = 1
            textIndex = nil
         }
      }
      func overlap(_ range: Range<Int>) -> Range<Int>? {
         let start = max(range.lowerBound, unitStart)
         let end = min(range.upperBound, unitStart + unitCount)
         return start < end ? (start - unitStart)..<(end - unitStart) : nil
      }
      func byteOffset(_ unit: Int) -> Int {
         if let textIndex { return byteStart + textIndex.byteOffsets[unit] }
         return byteStart + (segment.mode == .byte ? unit : 0)
      }
      func byteCount(_ range: Range<Int>) -> Int {
         if let textIndex { return textIndex.byteCount(range) }
         return segment.mode == .byte ? range.count : byteLength
      }
      func materialize(_ range: Range<Int>) -> QRSegment {
         if let textIndex { return .byteText(textIndex.text(range)) }
         if case .byte(let bytes) = segment { return .byte(Array(bytes[range])) }
         return segment
      }
      func bitLength(_ range: Range<Int>, version: Int) -> Int {
         if segment.mode == .byte { return singleBits(.byte, count: byteCount(range), version: version) }
         return SegmentEncoder.bitLength(segment, version: version)
      }
   }
   enum Source {
      case text(TextIndex), binary([UInt8]), manual([Descriptor])
      var unitCount: Int {
         switch self {
         case .text(let index): return index.scalars.count
         case .binary(let bytes): return bytes.count
         case .manual(let descriptors): return descriptors.reduce(0) { $0 + $1.unitCount }
         }
      }
      var byteLength: Int {
         switch self {
         case .text(let index): return index.byteOffsets.last!
         case .binary(let bytes): return bytes.count
         case .manual(let descriptors): return descriptors.reduce(0) { $0 + $1.byteLength }
         }
      }
      var inputLength: Int {
         if case .manual(let descriptors) = self { return descriptors.count }
         return unitCount
      }
      var isManual: Bool {
         if case .manual = self { return true }
         return false
      }
      func dataBits(_ range: Range<Int>, options: QROptions, version: Int) throws -> Int {
         switch self {
         case .binary: return singleBits(.byte, count: range.count, version: version)
         case .text(let index):
            if options.mode != .auto {
               return singleBits(
                  options.mode, count: options.mode == .byte ? index.byteCount(range) : range.count, version: version)
            }
            if let mode = index.uniformMode {
               return singleBits(mode, count: mode == .byte ? index.byteCount(range) : range.count, version: version)
            }
            if options.optimizeSegments {
               var tracker = TextBitLengthTracker(version: version)
               for scalar in index.scalars[range] { _ = tracker.append(scalar) }
               return tracker.best
            }
            let segments = try SegmentOptimizer.single(index.text(range), requested: .auto, allowKanji: true)
            return segments.reduce(0) { $0 + SegmentEncoder.bitLength($1, version: version) }
         case .manual(let descriptors):
            return descriptors.reduce(0) { sum, descriptor in
               guard let overlap = descriptor.overlap(range) else { return sum }
               return sum + descriptor.bitLength(overlap, version: version)
            }
         }
      }
      func autoTextPrefix(start: Int, maxLength: Int, options: QROptions, version: Int, capacity: Int) -> Int? {
         guard case .text(let index) = self, options.mode == .auto, index.uniformMode == nil else { return nil }
         var tracker = TextBitLengthTracker(version: version)
         var best = 0
         var numeric = true
         var alpha = true
         var kanji = true
         var bytes = 0
         for offset in 0..<maxLength {
            let scalar = index.scalars[start + offset]
            let bits: Int
            if options.optimizeSegments {
               bits = tracker.append(scalar)
            } else {
               numeric = numeric && (48...57).contains(scalar.value)
               alpha = alpha && SegmentEncoder.alphaValues[scalar.value] != nil
               kanji = kanji && KanjiMap.value(scalar) != nil
               bytes += String(scalar).utf8.count
               let mode: QRMode = numeric ? .numeric : alpha ? .alphanumeric : kanji ? .kanji : .byte
               bits = singleBits(mode, count: mode == .byte ? bytes : offset + 1, version: version)
            }
            if bits > capacity { break }
            best = offset + 1
         }
         return best
      }
      func chunk(_ range: Range<Int>) -> Chunk {
         switch self {
         case .text(let index):
            return Chunk(
               payload: .text(index.text(range)), range: range, byteStart: index.byteOffsets[range.lowerBound],
               byteLength: index.byteCount(range), segmentStart: nil, segmentEnd: nil)
         case .binary(let bytes):
            return Chunk(
               payload: .binary(Array(bytes[range])), range: range, byteStart: range.lowerBound,
               byteLength: range.count, segmentStart: nil, segmentEnd: nil)
         case .manual(let descriptors):
            var segments: [QRSegment] = []
            var first: Int?
            var last: Int?
            var byteStart: Int?
            var byteLength = 0
            for descriptor in descriptors {
               guard let overlap = descriptor.overlap(range) else { continue }
               segments.append(descriptor.materialize(overlap))
               first = first ?? descriptor.sourceIndex
               last = descriptor.sourceIndex + 1
               byteStart = byteStart ?? descriptor.byteOffset(overlap.lowerBound)
               byteLength += descriptor.byteCount(overlap)
            }
            return Chunk(
               payload: .manual(segments), range: range, byteStart: byteStart ?? 0,
               byteLength: byteLength, segmentStart: first, segmentEnd: last)
         }
      }
      func splitUnits() -> [QRStructuredAppendSplitUnit]? {
         guard case .manual(let descriptors) = self else { return nil }
         var units: [QRStructuredAppendSplitUnit] = []
         units.reserveCapacity(unitCount)
         for descriptor in descriptors {
            for unit in 0..<descriptor.unitCount {
               units.append(
                  .init(
                     sourceSegmentIndex: descriptor.sourceIndex, mode: descriptor.segment.mode,
                     unitStart: unit,
                     unitLength: descriptor.segment.mode == .byte ? 1 : descriptor.segment.characterCount,
                     byteStart: descriptor.byteOffset(unit), byteLength: descriptor.byteCount(unit..<(unit + 1))))
            }
         }
         return units
      }
   }
   enum Payload { case text(String), binary([UInt8]), manual([QRSegment]) }
   struct Chunk {
      let payload: Payload
      let range: Range<Int>
      let byteStart: Int
      let byteLength: Int
      let segmentStart: Int?
      let segmentEnd: Int?
   }

   static func canonicalBytes(_ segment: QRSegment) -> [UInt8] {
      if case .byte(let bytes) = segment { return bytes }
      return Array((segment.text ?? "").utf8)
   }
   static func validateSegments(_ segments: [QRSegment]) throws {
      guard !segments.isEmpty else { throw QRError.invalidInput("Structured Append requires non-empty data segments") }
      for (index, segment) in segments.enumerated() {
         if case .fnc1 = segment {
            throw QRError.invalidGS1("Structured Append cannot be combined with manual FNC1 first position segments")
         }
         guard !segment.isControl else {
            throw QRError.invalidMode(
               "Structured Append does not support manual \(segment.mode.rawValue) control segments")
         }
         try SegmentEncoder.validate(segment)
         guard !canonicalBytes(segment).isEmpty else {
            throw QRError.invalidInput("segments[\(index)] must include non-empty data for Structured Append")
         }
      }
   }
   static func validateOptions(_ options: QRStructuredAppendOptions, manual: Bool) throws {
      let qr = options.qrOptions
      guard (2...16).contains(options.maxSymbols) else {
         throw QRError.invalidMode("maxSymbols must be an integer from 2 to 16; got \(options.maxSymbols)")
      }
      if manual && qr.mode != .auto {
         throw QRError.invalidMode(
            "generateSegmentsStructuredAppend uses caller-provided segment modes; mode is not supported")
      }
      if manual && !qr.optimizeSegments {
         throw QRError.invalidMode(
            "generateSegmentsStructuredAppend preserves manual segments; optimizeSegments is not supported")
      }
      if !manual && options.splitUnits != .summary {
         throw QRError.invalidInput("Full split-unit diagnostics apply only to manual segments")
      }
      if qr.structuredAppend != nil {
         throw QRError.invalidMode(
            "High-level Structured Append owns the header; structuredAppend option is not supported")
      }
      if qr.eci != nil { throw QRError.invalidMode("High-level Structured Append cannot be combined with ECI") }
      if qr.gs1 { throw QRError.invalidGS1("High-level Structured Append cannot be combined with GS1") }
      if qr.fnc1Second != nil {
         throw QRError.invalidMode("High-level Structured Append cannot be combined with FNC1 second position")
      }
      if qr.boostErrorCorrection {
         throw QRError.invalidMode("High-level Structured Append does not support boostErrorCorrection")
      }
      try QRValidation.options(qr)
   }
   static func singleBits(_ mode: QRMode, count: Int, version: Int) -> Int {
      4 + QRTables.countBits(mode, version) + SegmentEncoder.payloadLength(mode, count: count)
   }
   static func tooLong(_ options: QRStructuredAppendOptions, manual: Bool = false) -> QRError {
      let qr = options.qrOptions
      let input = manual ? "Input segments" : "Input"
      if let version = qr.version {
         return .structuredAppendTooLong(
            "\(input) cannot be split into \(options.maxSymbols) or fewer version \(version)-\(qr.errorCorrectionLevel.rawValue) Structured Append symbols"
         )
      }
      return .structuredAppendTooLong(
         "\(input) cannot be split into \(options.maxSymbols) or fewer Structured Append symbols for versions \(qr.minVersion)..\(qr.maxVersion) at error correction \(qr.errorCorrectionLevel.rawValue)"
      )
   }
   static func preflight(count: Int, byteCount: Int, mode: QRMode, options: QRStructuredAppendOptions) throws {
      let version = options.qrOptions.version ?? options.qrOptions.maxVersion
      let capacity = QRTables.dataCodewords(version, options.qrOptions.errorCorrectionLevel) * 8
      let payload: Int
      let countBits: Int
      if mode == .auto {
         payload = SegmentEncoder.payloadLength(.numeric, count: count)
         countBits = [QRMode.numeric, .alphanumeric, .byte, .kanji].map { QRTables.countBits($0, version) }.min()!
      } else {
         payload = SegmentEncoder.payloadLength(mode, count: mode == .byte ? byteCount : count)
         countBits = QRTables.countBits(mode, version)
      }
      if payload > max(0, capacity - 24 - countBits) * options.maxSymbols { throw tooLong(options) }
   }
   static func generate(text: String, options: QRStructuredAppendOptions) throws -> QRStructuredAppendResult {
      try validateOptions(options, manual: false)
      guard !text.isEmpty else {
         throw QRError.invalidInput(
            "generateStructuredAppend requires input that can be split into at least two non-empty symbols")
      }
      if options.qrOptions.mode != .auto {
         try SegmentEncoder.validate(SegmentOptimizer.segment(text, mode: options.qrOptions.mode))
      }
      try preflight(
         count: text.unicodeScalars.count, byteCount: text.utf8.count, mode: options.qrOptions.mode, options: options)
      return try build(
         source: .text(TextIndex(text)), parity: SpecQR.calculateStructuredAppendParity(text), options: options)
   }
   static func generate(bytes: [UInt8], options: QRStructuredAppendOptions) throws -> QRStructuredAppendResult {
      try validateOptions(options, manual: false)
      guard options.qrOptions.mode == .auto || options.qrOptions.mode == .byte else {
         throw QRError.invalidMode("Binary input can only be encoded in byte mode")
      }
      guard !bytes.isEmpty else {
         throw QRError.invalidInput(
            "generateStructuredAppend requires input that can be split into at least two non-empty symbols")
      }
      try preflight(count: bytes.count, byteCount: bytes.count, mode: .byte, options: options)
      return try build(source: .binary(bytes), parity: SpecQR.calculateStructuredAppendParity(bytes), options: options)
   }
   static func generate(segments: [QRSegment], options: QRStructuredAppendOptions) throws -> QRStructuredAppendResult {
      try validateOptions(options, manual: true)
      try validateSegments(segments)
      let version = options.qrOptions.version ?? options.qrOptions.maxVersion
      let required = segments.reduce(0) { $0 + SegmentEncoder.bitLength($1, version: version) }
      let available =
         options.maxSymbols * max(0, QRTables.dataCodewords(version, options.qrOptions.errorCorrectionLevel) * 8 - 20)
      if required > available { throw tooLong(options, manual: true) }
      var descriptors: [Descriptor] = []
      var byteStart = 0
      var unitStart = 0
      for (index, segment) in segments.enumerated() {
         let descriptor = Descriptor(segment: segment, index: index, byteStart: byteStart, unitStart: unitStart)
         descriptors.append(descriptor)
         byteStart += descriptor.byteLength
         unitStart += descriptor.unitCount
      }
      return try build(
         source: .manual(descriptors), parity: segments.reduce(UInt8(0)) { $0 ^ canonicalBytes($1).reduce(0, ^) },
         options: options)
   }
   enum Attempt { case single, tooLong, split([Range<Int>]) }
   static func attempt(source: Source, options: QRStructuredAppendOptions, version: Int) throws -> Attempt {
      let capacity = QRTables.dataCodewords(version, options.qrOptions.errorCorrectionLevel) * 8 - 20
      func fits(_ range: Range<Int>) throws -> Bool {
         // Numeric is the cheapest possible payload. Reject obviously oversized text
         // prefixes before allocating optimizer state, including large full-input probes.
         if case .text = source {
            let minimumHeader =
               4 + [QRMode.numeric, .alphanumeric, .byte, .kanji]
               .map { QRTables.countBits($0, version) }.min()!
            if SegmentEncoder.payloadLength(.numeric, count: range.count) + minimumHeader > capacity { return false }
         }
         return try source.dataBits(range, options: options.qrOptions, version: version) <= capacity
      }
      if try fits(0..<source.unitCount) { return .single }
      guard source.unitCount >= 2 else { return .tooLong }
      var ranges: [Range<Int>] = []
      var position = 0
      while position < source.unitCount {
         if ranges.count >= options.maxSymbols { return .tooLong }
         let maxLength = source.unitCount - position - (ranges.isEmpty ? 1 : 0)
         var best: Int
         if let prefix = source.autoTextPrefix(
            start: position, maxLength: maxLength, options: options.qrOptions, version: version, capacity: capacity)
         {
            best = prefix
         } else {
            var low = 1
            var high = maxLength
            best = 0
            while low <= high {
               let middle = low + (high - low) / 2
               if try fits(position..<(position + middle)) {
                  best = middle
                  low = middle + 1
               } else {
                  high = middle - 1
               }
            }
         }
         if best == 0 { return .tooLong }
         ranges.append(position..<(position + best))
         position += best
      }
      return ranges.count >= 2 ? .split(ranges) : .single
   }
   static func build(source: Source, parity: UInt8, options: QRStructuredAppendOptions) throws
      -> QRStructuredAppendResult
   {
      let qr = options.qrOptions
      let versions = qr.version.map { $0...$0 } ?? qr.minVersion...qr.maxVersion
      var selected: (version: Int, ranges: [Range<Int>])?
      var sawTooLong = false
      for version in versions {
         switch try attempt(source: source, options: options, version: version) {
         case .split(let ranges): selected = (version, ranges)
         case .tooLong: sawTooLong = true
         case .single: break
         }
         if selected != nil { break }
      }
      guard let selected else {
         if sawTooLong { throw tooLong(options, manual: source.isManual) }
         let input = source.isManual ? "Input segments" : "Input"
         let method = source.isManual ? "generateSegments()" : "generate()"
         let location =
            qr.version.map { "version \($0)-\(qr.errorCorrectionLevel.rawValue) symbol" }
            ?? "symbol in the selected version range"
         throw QRError.invalidInput(
            "\(input) fits in one \(location); use \(method) or the low-level structuredAppend option instead")
      }
      var symbols: [QRCode] = []
      var diagnostics: [QRStructuredAppendSymbolDiagnostics] = []
      for (index, range) in selected.ranges.enumerated() {
         let chunk = source.chunk(range)
         var symbolOptions = qr
         symbolOptions.version = selected.version
         symbolOptions.minVersion = selected.version
         symbolOptions.maxVersion = selected.version
         symbolOptions.structuredAppend = .init(index: index + 1, total: selected.ranges.count, parity: parity)
         let code: QRCode
         switch chunk.payload {
         case .text(let text): code = try SpecQR.generate(text, options: symbolOptions)
         case .binary(let bytes): code = try SpecQR.generate(bytes, options: symbolOptions)
         case .manual(let segments): code = try SpecQR.generate(segments: segments, options: symbolOptions)
         }
         symbols.append(code)
         diagnostics.append(
            .init(
               index: index + 1, total: selected.ranges.count, parity: parity,
               inputStart: source.isManual ? nil : range.lowerBound, inputLength: source.isManual ? nil : range.count,
               sourceSegmentStart: chunk.segmentStart, sourceSegmentEnd: chunk.segmentEnd,
               splitUnitStart: source.isManual ? range.lowerBound : nil,
               splitUnitLength: source.isManual ? range.count : nil,
               byteStart: chunk.byteStart, byteLength: chunk.byteLength, version: code.version,
               errorCorrectionLevel: code.errorCorrectionLevel, dataBitLength: code.diagnostics.dataBitLength,
               capacityBits: code.diagnostics.capacityBits, remainingBits: code.diagnostics.remainingBits,
               maskPattern: code.maskPattern))
      }
      var warnings: [QRStructuredAppendWarning] = []
      if symbols.count == options.maxSymbols {
         warnings.append(
            .init(
               code: "STRUCTURED_APPEND_MAX_SYMBOLS_NEAR_LIMIT", severity: "info",
               message: "The generated Structured Append set uses the configured maximum number of symbols.",
               total: symbols.count, maxSymbols: options.maxSymbols))
      }
      if options.diagnostics {
         warnings.append(
            .init(
               code: "STRUCTURED_APPEND_DECODER_SUPPORT_VARIES", severity: "info",
               message: "Decoder APIs vary in how they expose Structured Append set metadata.", total: symbols.count,
               maxSymbols: nil))
      }
      let reason =
         qr.version != nil
         ? "Version \(selected.version) was requested explicitly."
         : "Version \(selected.version) is the smallest version in \(qr.minVersion)..\(qr.maxVersion) that can split the \(source.isManual ? "manual segments" : "payload") into \(symbols.count) Structured Append symbols at error correction \(qr.errorCorrectionLevel.rawValue)."
      return .init(
         symbols: symbols, total: symbols.count, parity: parity, inputLength: source.inputLength,
         byteLength: source.byteLength,
         diagnostics: .init(
            version: selected.version, errorCorrectionLevel: qr.errorCorrectionLevel,
            versionSelection: qr.version != nil ? "fixed" : "auto-minimum", versionSelectionReason: reason,
            total: symbols.count, parity: parity, byteLength: source.byteLength, inputLength: source.inputLength,
            segmentCount: source.isManual ? source.inputLength : nil, maxSymbols: options.maxSymbols,
            splitStrategy: source.isManual ? "segment-boundary-byte-chunk" : "greedy-largest-fitting",
            splitUnitCount: source.isManual ? source.unitCount : nil,
            splitUnitsDetail: source.isManual ? options.splitUnits : nil,
            splitUnits: options.splitUnits == .full ? source.splitUnits() : nil, symbols: diagnostics,
            warnings: warnings))
   }
}
