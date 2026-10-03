import Foundation

/// Manual byte split-unit diagnostics can be compact (the default) or fully expanded.
public enum QRStructuredAppendSplitUnitsDetail: String, Sendable { case summary, full }

/// High-level Structured Append settings. Each set uses one QR version and error correction level.
/// The high-level API owns its headers and rejects ECI, GS1/FNC1, and ECC boosting.
public struct QRStructuredAppendOptions: Equatable, Sendable {
   public let qrOptions: QROptions
   public let maxSymbols: Int
   public let diagnostics: Bool
   public let splitUnits: QRStructuredAppendSplitUnitsDetail
   public init(
      qrOptions: QROptions = .init(), maxSymbols: Int = 16,
      diagnostics: Bool = false, splitUnits: QRStructuredAppendSplitUnitsDetail = .summary
   ) {
      self.qrOptions = qrOptions
      self.maxSymbols = maxSymbols
      self.diagnostics = diagnostics
      self.splitUnits = splitUnits
   }
}

/// Canonical data for reassembling a decoded set. Text is represented by its UTF-8 bytes.
public enum QRStructuredAppendData: Equatable, Sendable {
   case text(String)
   case bytes([UInt8])
   public var canonicalBytes: [UInt8] {
      switch self {
      case .text(let text): return Array(text.utf8)
      case .bytes(let bytes): return bytes
      }
   }
   public var dataType: String {
      switch self {
      case .text: return "string"
      case .bytes: return "binary"
      }
   }
}

/// A decoded Structured Append part; indices are one-based.
public struct QRStructuredAppendPart: Equatable, Sendable {
   public let index: Int
   public let total: Int
   public let parity: UInt8
   public let data: QRStructuredAppendData
   public init(index: Int, total: Int, parity: UInt8, data: QRStructuredAppendData) {
      self.index = index
      self.total = total
      self.parity = parity
      self.data = data
   }
   public init(index: Int, total: Int, parity: UInt8, text: String) {
      self.init(index: index, total: total, parity: parity, data: .text(text))
   }
   public init(index: Int, total: Int, parity: UInt8, bytes: [UInt8]) {
      self.init(index: index, total: total, parity: parity, data: .bytes(bytes))
   }
   public init(index: Int, total: Int, parity: UInt8, bytes: Data) {
      self.init(index: index, total: total, parity: parity, bytes: Array(bytes))
   }
}

public struct QRStructuredAppendPartMetadata: Equatable, Sendable {
   public let index: Int
   public let total: Int
   public let parity: UInt8
   public let dataType: String
   public let byteLength: Int
}

public struct QRStructuredAppendParityCheck: Equatable, Sendable {
   public let expected: UInt8
   public let actual: UInt8
   public var matches: Bool { expected == actual }
}

public struct QRStructuredAppendMergeDiagnostics: Equatable, Sendable {
   public let partCount: Int
   public let total: Int
   public let parity: UInt8
   public let dataType: String
   public let byteLength: Int
   /// Successful merges have no missing or duplicate parts.
   public let missing: [Int]
   public let duplicate: [Int]
   public let parityCheck: QRStructuredAppendParityCheck
}

public struct QRStructuredAppendMergeResult: Equatable, Sendable {
   public let data: QRStructuredAppendData
   public let total: Int
   public let parity: UInt8
   public let parts: [QRStructuredAppendPartMetadata]
   public let diagnostics: QRStructuredAppendMergeDiagnostics
}

public struct QRStructuredAppendSplitUnit: Equatable, Sendable {
   public let sourceSegmentIndex: Int
   public let mode: QRMode
   /// Offset within the source segment, measured in Unicode scalars or binary bytes.
   public let unitStart: Int
   public let unitLength: Int
   public let byteStart: Int
   public let byteLength: Int
}

public struct QRStructuredAppendWarning: Equatable, Sendable {
   public let code: String
   public let severity: String
   public let message: String
   public let total: Int
   public let maxSymbols: Int?
}

/// Each symbol's source range and bit accounting. Ranges are zero-based, half-open.
public struct QRStructuredAppendSymbolDiagnostics: Equatable, Sendable {
   public let index: Int
   public let total: Int
   public let parity: UInt8
   public var sequenceIndex: Int { index - 1 }
   public var sequenceTotal: Int { total - 1 }
   public var sequenceIndicator: Int { (sequenceIndex << 4) | sequenceTotal }
   /// Text/binary input range. Text counts Unicode scalars, not grapheme clusters.
   public let inputStart: Int?
   public let inputLength: Int?
   /// Manual source-segment range, with an exclusive end.
   public let sourceSegmentStart: Int?
   public let sourceSegmentEnd: Int?
   public let splitUnitStart: Int?
   public let splitUnitLength: Int?
   public let byteStart: Int
   public let byteLength: Int
   public let version: Int
   public let errorCorrectionLevel: ErrorCorrectionLevel
   public let dataBitLength: Int
   public let capacityBits: Int
   public let remainingBits: Int
   public let maskPattern: Int
}

public struct QRStructuredAppendDiagnostics: Equatable, Sendable {
   public let version: Int
   public let errorCorrectionLevel: ErrorCorrectionLevel
   public let versionSelection: String
   public let versionSelectionReason: String
   public let total: Int
   public let parity: UInt8
   public let byteLength: Int
   public let inputLength: Int
   public let segmentCount: Int?
   public let maxSymbols: Int
   public let splitStrategy: String
   public let splitUnitCount: Int?
   public let splitUnitsDetail: QRStructuredAppendSplitUnitsDetail?
   /// nil for compact summaries; full detail is materialized only when requested.
   public let splitUnits: [QRStructuredAppendSplitUnit]?
   public let symbols: [QRStructuredAppendSymbolDiagnostics]
   public let warnings: [QRStructuredAppendWarning]
}

/// A complete 2...16-symbol set. Symbols retain the normal immutable QRCode result shape.
public struct QRStructuredAppendResult: Equatable, Sendable {
   public let symbols: [QRCode]
   public let total: Int
   public let parity: UInt8
   /// Number of input Unicode scalars/binary bytes, or number of manual segments.
   public let inputLength: Int
   public let byteLength: Int
   public let diagnostics: QRStructuredAppendDiagnostics
}
