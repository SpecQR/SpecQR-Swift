import Foundation

internal struct BitBuffer {
   private(set) var bytes: [UInt8] = []
   private(set) var count = 0
   mutating func append(_ value: Int, _ width: Int) {
      guard width > 0 else { return }
      for shift in stride(from: width - 1, through: 0, by: -1) {
         if count % 8 == 0 { bytes.append(0) }
         if value >> shift & 1 != 0 { bytes[bytes.count - 1] |= 1 << (7 - count % 8) }
         count += 1
      }
   }
}

internal enum QRValidation {
   static func version(_ version: Int) throws {
      guard (1...40).contains(version) else { throw QRError.invalidVersion("Version must be in 1...40.") }
   }
   static func options(_ options: QROptions) throws {
      try version(options.minVersion)
      try version(options.maxVersion)
      if let fixed = options.version { try version(fixed) }
      guard options.minVersion <= options.maxVersion else {
         throw QRError.invalidVersion("minVersion must not exceed maxVersion.")
      }
      if let mask = options.maskPattern, !(0...7).contains(mask) {
         throw QRError.invalidInput("Mask must be in 0...7.")
      }
      guard options.mode == .auto || options.mode.isData else {
         throw QRError.invalidMode("An input mode must be auto, numeric, alphanumeric, byte, or kanji.")
      }
      if let eci = options.eci { try SegmentEncoder.validate(.eci(eci)) }
      if let indicator = options.fnc1Second { try SegmentEncoder.validate(.fnc1Second(indicator)) }
      if let h = options.structuredAppend {
         try SegmentEncoder.validate(.structuredAppend(index: h.index, total: h.total, parity: h.parity))
      }
      let kinds = [options.gs1, options.eci != nil, options.fnc1Second != nil, options.structuredAppend != nil].filter {
         $0
      }.count
      if kinds > 1 {
         if options.gs1 {
            throw QRError.invalidGS1("GS1 cannot be combined with ECI, FNC1 second position, or Structured Append.")
         }
         throw QRError.invalidMode("ECI, FNC1 second position, and Structured Append cannot be combined.")
      }
   }
   static func controls(_ segments: [QRSegment]) throws {
      var leading: QRMode?
      var eciPresent = false
      for (index, segment) in segments.enumerated() {
         try SegmentEncoder.validate(segment)
         if case .eci = segment {
            eciPresent = true
            continue
         }
         if segment.isControl {
            if index != 0 || leading != nil {
               if segment.mode == .fnc1 {
                  throw QRError.invalidGS1("FNC1 first position must occur once, at the beginning.")
               }
               throw QRError.invalidMode("FNC1 and Structured Append headers must occur once, at the beginning.")
            }
            leading = segment.mode
         }
      }
      if leading != nil && eciPresent {
         if leading == .fnc1 { throw QRError.invalidGS1("FNC1 first position cannot be combined with ECI.") }
         throw QRError.invalidMode("ECI cannot be combined with FNC1 or Structured Append.")
      }
   }
}

internal enum SegmentEncoder {
   static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:".unicodeScalars)
   static let alphaValues: [UInt32: Int] = Dictionary(
      uniqueKeysWithValues: alphabet.enumerated().map { ($0.element.value, $0.offset) })
   static func indicator(_ value: String) throws -> Int {
      let bytes = Array(value.utf8)
      if bytes.count == 2 && bytes.allSatisfy({ (48...57).contains($0) }) {
         return Int(bytes[0] - 48) * 10 + Int(bytes[1] - 48)
      }
      if bytes.count == 1 && ((65...90).contains(bytes[0]) || (97...122).contains(bytes[0])) {
         return Int(bytes[0]) + 100
      }
      throw QRError.invalidMode("FNC1 second position requires two ASCII digits or one Latin letter.")
   }
   static func validate(_ segment: QRSegment) throws {
      switch segment {
      case .numeric(let text):
         guard text.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) else {
            throw QRError.invalidMode("Numeric mode permits only ASCII digits 0-9.")
         }
      case .alphanumeric(let text):
         guard text.unicodeScalars.allSatisfy({ alphaValues[$0.value] != nil }) else {
            throw QRError.invalidMode("Unsupported character in alphanumeric segment.")
         }
      case .kanji(let text):
         guard text.unicodeScalars.allSatisfy({ KanjiMap.value($0) != nil }) else {
            throw QRError.invalidMode("Kanji mode requires characters in the QR Shift_JIS ranges.")
         }
      case .eci(let value):
         guard (0..<1_000_000).contains(value) else {
            throw QRError.invalidECI("ECI assignment must be in 0...999999.")
         }
      case .fnc1Second(let value): _ = try indicator(value)
      case .structuredAppend(let index, let total, _):
         guard (2...16).contains(total), (1...total).contains(index) else {
            throw QRError.invalidMode("Structured Append requires total 2...16 and one-based index 1...total.")
         }
      case .byte, .byteText, .fnc1: break
      }
   }
   static func payloadLength(_ mode: QRMode, count: Int) -> Int {
      switch mode {
      case .numeric: return count / 3 * 10 + [0, 4, 7][count % 3]
      case .alphanumeric: return count / 2 * 11 + count % 2 * 6
      case .kanji: return count * 13
      case .byte: return count * 8
      default: return 0
      }
   }
   static func bitLength(_ segment: QRSegment, version: Int) -> Int {
      switch segment {
      case .eci(let assignment): return assignment < 128 ? 12 : assignment < 16384 ? 20 : 28
      case .fnc1: return 4
      case .fnc1Second: return 12
      case .structuredAppend: return 20
      default:
         let count = segment.mode == .byte ? segment.byteCount : segment.characterCount
         return 4 + QRTables.countBits(segment.mode, version) + payloadLength(segment.mode, count: count)
      }
   }
   static func applyingOptions(_ segments: [QRSegment], options: QROptions) throws -> [QRSegment] {
      var result = segments
      if let assignment = options.eci { result.insert(.eci(assignment), at: 0) }
      if options.gs1 { result.insert(.fnc1, at: 0) }
      if let indicator = options.fnc1Second { result.insert(.fnc1Second(indicator), at: 0) }
      if let h = options.structuredAppend {
         result.insert(.structuredAppend(index: h.index, total: h.total, parity: h.parity), at: 0)
      }
      try QRValidation.controls(result)
      return result
   }
   static func encode(_ segments: [QRSegment], version: Int, level: ErrorCorrectionLevel) throws -> [UInt8] {
      var buffer = BitBuffer()
      for segment in segments {
         try validate(segment)
         switch segment {
         case .eci(let assignment):
            buffer.append(7, 4)
            if assignment < 128 {
               buffer.append(assignment, 8)
            } else if assignment < 16384 {
               buffer.append(2, 2)
               buffer.append(assignment, 14)
            } else {
               buffer.append(6, 3)
               buffer.append(assignment, 21)
            }
         case .fnc1: buffer.append(5, 4)
         case .fnc1Second(let indicator):
            buffer.append(9, 4)
            buffer.append(try self.indicator(indicator), 8)
         case .structuredAppend(let index, let total, let parity):
            buffer.append(3, 4)
            buffer.append(index - 1, 4)
            buffer.append(total - 1, 4)
            buffer.append(Int(parity), 8)
         default:
            let count = segment.mode == .byte ? segment.byteCount : segment.characterCount
            let width = QRTables.countBits(segment.mode, version)
            guard count < 1 << width else {
               throw QRError.dataTooLong(
                  requiredBits: bitLength(segment, version: version),
                  capacityBits: QRTables.dataCodewords(version, level) * 8, version: version)
            }
            let modeBits: Int =
               segment.mode == .numeric ? 1 : segment.mode == .alphanumeric ? 2 : segment.mode == .byte ? 4 : 8
            buffer.append(modeBits, 4)
            buffer.append(count, width)
            switch segment {
            case .numeric(let text):
               let values = Array(text.utf8)
               for offset in stride(from: 0, to: values.count, by: 3) {
                  let length = min(3, values.count - offset)
                  let value = values[offset..<(offset + length)].reduce(0) { $0 * 10 + Int($1 - 48) }
                  buffer.append(value, [0, 4, 7, 10][length])
               }
            case .alphanumeric(let text):
               let values = text.unicodeScalars.map { alphaValues[$0.value]! }
               for offset in stride(from: 0, to: values.count, by: 2) {
                  if offset + 1 < values.count {
                     buffer.append(values[offset] * 45 + values[offset + 1], 11)
                  } else {
                     buffer.append(values[offset], 6)
                  }
               }
            case .kanji(let text): for scalar in text.unicodeScalars { buffer.append(KanjiMap.value(scalar)!, 13) }
            case .byte(let bytes): for byte in bytes { buffer.append(Int(byte), 8) }
            case .byteText(let text): for byte in text.utf8 { buffer.append(Int(byte), 8) }
            default: break
            }
         }
      }
      let capacity = QRTables.dataCodewords(version, level) * 8
      guard buffer.count <= capacity else {
         throw QRError.dataTooLong(requiredBits: buffer.count, capacityBits: capacity, version: version)
      }
      buffer.append(0, min(4, capacity - buffer.count))
      buffer.append(0, (8 - buffer.count % 8) % 8)
      var pad = 0
      while buffer.count < capacity {
         buffer.append(pad % 2 == 0 ? 0xEC : 0x11, 8)
         pad += 1
      }
      return buffer.bytes
   }
   static func diagnostics(_ segment: QRSegment, version: Int) -> QRSegmentDiagnostics {
      var assignment: Int?
      var indicator: String?
      var codeword: Int?
      var header: QRStructuredAppendHeader?
      switch segment {
      case .eci(let value): assignment = value
      case .fnc1Second(let value):
         indicator = value
         codeword = try? self.indicator(value)
      case .structuredAppend(let index, let total, let parity):
         header = .init(index: index, total: total, parity: parity)
      default: break
      }
      return QRSegmentDiagnostics(
         mode: segment.mode, characterCount: segment.characterCount, byteCount: segment.byteCount,
         bitLength: bitLength(segment, version: version), assignmentNumber: assignment, applicationIndicator: indicator,
         applicationIndicatorCodeword: codeword, structuredAppend: header)
   }
}
