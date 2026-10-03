import Foundation

extension SpecQR {
   /// XOR parity of the original UTF-8 bytes, before QR mode encoding.
   public static func calculateStructuredAppendParity(_ text: String) -> UInt8 {
      text.utf8.reduce(0, ^)
   }
   public static func calculateStructuredAppendParity(_ bytes: [UInt8]) -> UInt8 { bytes.reduce(0, ^) }
   public static func calculateStructuredAppendParity(_ bytes: Data) -> UInt8 { bytes.reduce(0, ^) }

   /// XOR parity of manual canonical payload bytes. Kanji contributes UTF-8, not Shift-JIS.
   /// Empty data and control segments are rejected by the high-level manual API.
   public static func calculateStructuredAppendSegmentsParity(_ segments: [QRSegment]) throws -> UInt8 {
      try StructuredAppendEncoder.validateSegments(segments)
      return segments.reduce(UInt8(0)) { $0 ^ StructuredAppendEncoder.canonicalBytes($1).reduce(0, ^) }
   }

   /// Validates a complete decoded set and merges in sequence order. This does not decode images.
   /// All parts must agree on total, parity, and text/binary kind. Missing/duplicate indices,
   /// incompatible metadata, and mismatching canonical byte parity throw INVALID_INPUT.
   public static func mergeStructuredAppendParts(_ parts: [QRStructuredAppendPart]) throws
      -> QRStructuredAppendMergeResult
   {
      guard let first = parts.first else { throw QRError.invalidInput("Structured Append parts must not be empty") }
      var seen = Set<Int>()
      for (sourceIndex, part) in parts.enumerated() {
         guard (1...16).contains(part.index) else {
            throw QRError.invalidInput(
               "Structured Append parts[\(sourceIndex)].index must be an integer from 1 to 16; got \(part.index)")
         }
         guard (2...16).contains(part.total) else {
            throw QRError.invalidInput(
               "Structured Append parts[\(sourceIndex)].total must be an integer from 2 to 16; got \(part.total)")
         }
         guard part.total == first.total else {
            throw QRError.invalidInput(
               "Structured Append total mismatch: expected \(first.total), got \(part.total) at parts[\(sourceIndex)]")
         }
         guard part.parity == first.parity else {
            throw QRError.invalidInput(
               "Structured Append parity mismatch: expected \(first.parity), got \(part.parity) at parts[\(sourceIndex)]"
            )
         }
         guard part.index <= part.total else {
            throw QRError.invalidInput(
               "Structured Append parts[\(sourceIndex)].index must be between 1 and total \(part.total); got \(part.index)"
            )
         }
         guard part.data.dataType == first.data.dataType else {
            throw QRError.invalidInput("Structured Append parts must not mix string and binary data")
         }
         guard seen.insert(part.index).inserted else {
            throw QRError.invalidInput("Structured Append duplicate index \(part.index)")
         }
      }
      let missing = (1...first.total).filter { !seen.contains($0) }
      guard missing.isEmpty else {
         throw QRError.invalidInput(
            "Structured Append parts are missing index(es): \(missing.map(String.init).joined(separator: ", "))")
      }
      guard parts.count == first.total else {
         throw QRError.invalidInput("Structured Append part count \(parts.count) does not match total \(first.total)")
      }
      let sorted = parts.sorted { $0.index < $1.index }
      let bytes = sorted.flatMap { $0.data.canonicalBytes }
      let actual = calculateStructuredAppendParity(bytes)
      guard actual == first.parity else {
         throw QRError.invalidInput("Structured Append parity check failed: expected \(first.parity), got \(actual)")
      }
      let data: QRStructuredAppendData
      switch first.data {
      case .bytes: data = .bytes(bytes)
      case .text:
         data = .text(
            sorted.map {
               if case .text(let text) = $0.data { return text }
               return ""
            }.joined())
      }
      return QRStructuredAppendMergeResult(
         data: data, total: first.total, parity: first.parity,
         parts: sorted.map {
            .init(
               index: $0.index, total: $0.total, parity: $0.parity,
               dataType: $0.data.dataType, byteLength: $0.data.canonicalBytes.count)
         },
         diagnostics: .init(
            partCount: sorted.count, total: first.total, parity: first.parity,
            dataType: first.data.dataType, byteLength: bytes.count,
            missing: [], duplicate: [], parityCheck: .init(expected: first.parity, actual: actual)))
   }
}
