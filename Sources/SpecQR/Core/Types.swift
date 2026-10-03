import Foundation

/// QR Model 2 error correction levels, ordered from least to most redundancy.
public enum ErrorCorrectionLevel: String, CaseIterable, Codable, Sendable {
   case L, M, Q, H
   var ordinal: Int { Self.allCases.firstIndex(of: self)! }
   var formatBits: Int { [1, 0, 3, 2][ordinal] }
}

public enum QRMode: String, Codable, Sendable {
   case auto, numeric, alphanumeric, byte, kanji
   case eci, fnc1
   case fnc1Second = "fnc1-second"
   case structuredAppend = "structured-append"
   case mixed
   var isData: Bool { [.numeric, .alphanumeric, .byte, .kanji].contains(self) }
}

/// Structured Append uses one-based indices, matching the JavaScript API.
public struct QRStructuredAppendHeader: Equatable, Sendable {
   public var index: Int
   public var total: Int
   public var parity: UInt8
   public init(index: Int, total: Int, parity: UInt8) {
      self.index = index
      self.total = total
      self.parity = parity
   }
   public var isValid: Bool { (2...16).contains(total) && (1...total).contains(index) }
   /// Encoded fields are nil for a malformed caller-created header; generation throws.
   public var sequenceIndex: Int? { isValid ? index - 1 : nil }
   public var sequenceTotal: Int? { isValid ? total - 1 : nil }
   public var sequenceIndicator: Int? {
      guard let index = sequenceIndex, let total = sequenceTotal else { return nil }
      return index << 4 | total
   }
}

/// Immutable segment payload. Text byte segments retain text character diagnostics.
public enum QRSegment: Equatable, Sendable {
   case numeric(String)
   case alphanumeric(String)
   case byte([UInt8])
   case byteText(String)
   case kanji(String)
   case eci(Int)
   case fnc1
   case fnc1Second(String)
   case structuredAppend(index: Int, total: Int, parity: UInt8)
   public static func byte(_ text: String) -> QRSegment { .byteText(text) }
   public var mode: QRMode {
      switch self {
      case .numeric: return .numeric
      case .alphanumeric: return .alphanumeric
      case .byte, .byteText: return .byte
      case .kanji: return .kanji
      case .eci: return .eci
      case .fnc1: return .fnc1
      case .fnc1Second: return .fnc1Second
      case .structuredAppend: return .structuredAppend
      }
   }
   public var text: String? {
      switch self {
      case .numeric(let t), .alphanumeric(let t), .byteText(let t), .kanji(let t): return t
      default: return nil
      }
   }
   public var bytes: [UInt8]? {
      switch self {
      case .byte(let bytes): return bytes
      case .byteText(let text): return Array(text.utf8)
      default: return nil
      }
   }
   public var isControl: Bool { !mode.isData }
   public var characterCount: Int { text?.unicodeScalars.count ?? 0 }
   public var byteCount: Int {
      if case .kanji = self { return characterCount * 2 }
      return bytes?.count ?? text?.utf8.count ?? 0
   }
   public func bitLength(version: Int) throws -> Int {
      try QRValidation.version(version)
      try SegmentEncoder.validate(self)
      return SegmentEncoder.bitLength(self, version: version)
   }
}

public struct QROptions: Equatable, Sendable {
   public var errorCorrectionLevel: ErrorCorrectionLevel
   /// nil selects the smallest fitting version within minVersion...maxVersion.
   public var version: Int?
   public var minVersion: Int
   public var maxVersion: Int
   public var maskPattern: Int?
   public var mode: QRMode
   public var optimizeSegments: Bool
   public var boostErrorCorrection: Bool
   /// nil disables ECI; 26 explicitly labels UTF-8.
   public var eci: Int?
   public var gs1: Bool
   public var fnc1Second: String?
   public var structuredAppend: QRStructuredAppendHeader?
   public init(
      errorCorrectionLevel: ErrorCorrectionLevel = .M, version: Int? = nil,
      minVersion: Int = 1, maxVersion: Int = 40, maskPattern: Int? = nil,
      mode: QRMode = .auto, optimizeSegments: Bool = true,
      boostErrorCorrection: Bool = false, eci: Int? = nil, gs1: Bool = false,
      fnc1Second: String? = nil, structuredAppend: QRStructuredAppendHeader? = nil
   ) {
      self.errorCorrectionLevel = errorCorrectionLevel
      self.version = version
      self.minVersion = minVersion
      self.maxVersion = maxVersion
      self.maskPattern = maskPattern
      self.mode = mode
      self.optimizeSegments = optimizeSegments
      self.boostErrorCorrection = boostErrorCorrection
      self.eci = eci
      self.gs1 = gs1
      self.fnc1Second = fnc1Second
      self.structuredAppend = structuredAppend
   }
}

public enum QRError: Error, Equatable, Sendable, LocalizedError {
   case invalidInput(String)
   case invalidVersion(String)
   case invalidMode(String)
   case invalidECI(String)
   case invalidGS1(String)
   case dataTooLong(requiredBits: Int, capacityBits: Int, version: Int)
   case structuredAppendTooLong(String)
   public var code: String {
      switch self {
      case .invalidInput: return "INVALID_INPUT"
      case .invalidVersion: return "INVALID_VERSION"
      case .invalidMode: return "INVALID_MODE"
      case .invalidECI: return "INVALID_ECI"
      case .invalidGS1: return "INVALID_GS1"
      case .dataTooLong, .structuredAppendTooLong: return "DATA_TOO_LONG"
      }
   }
   public var errorDescription: String? {
      switch self {
      case .invalidInput(let s), .invalidVersion(let s), .invalidMode(let s), .invalidECI(let s), .invalidGS1(let s),
         .structuredAppendTooLong(let s):
         return s
      case .dataTooLong(let required, let capacity, let version):
         return "Input requires \(required) bits, but version \(version) has \(capacity) data bits."
      }
   }
}

public struct QRSegmentDiagnostics: Equatable, Sendable {
   public let mode: QRMode
   public let characterCount: Int
   public let byteCount: Int
   public let bitLength: Int
   public let assignmentNumber: Int?
   public let applicationIndicator: String?
   public let applicationIndicatorCodeword: Int?
   public let structuredAppend: QRStructuredAppendHeader?
   public var index: Int? { structuredAppend?.index }
   public var total: Int? { structuredAppend?.total }
   public var parity: UInt8? { structuredAppend?.parity }
   public var sequenceIndex: Int? { structuredAppend?.sequenceIndex }
   public var sequenceTotal: Int? { structuredAppend?.sequenceTotal }
   public var sequenceIndicator: Int? {
      guard let i = sequenceIndex, let t = sequenceTotal else { return nil }
      return i << 4 | t
   }
}

public struct QRGS1ValidationDiagnostics: Equatable, Sendable {
   public let enabled: Bool
   public let elementCount: Int?
   public let ais: [String]
   public let hasSeparators: Bool
}

public struct QRFNC1SecondDiagnostics: Equatable, Sendable {
   public let enabled: Bool
   public let applicationIndicator: String?
   public let applicationIndicatorCodeword: Int?
}

public struct QRPlan: Equatable, Sendable {
   public let ok: Bool
   public let selectedVersion: Int?
   /// On overflow this is the upper version used for the capacity calculation.
   public let evaluatedVersion: Int
   public let minVersion: Int
   public let maxVersion: Int
   public let errorCorrectionLevel: ErrorCorrectionLevel
   public let requestedErrorCorrectionLevel: ErrorCorrectionLevel
   public let versionSelection: String
   public let versionSelectionReason: String
   public let segments: [QRSegment]
   public let segmentDiagnostics: [QRSegmentDiagnostics]
   public let dataBitLength: Int
   public let capacityBits: Int
   public let inputBytes: Int
   public let gs1Validation: QRGS1ValidationDiagnostics
   public var phase: String { "planning" }
   public var renderPlanned: Bool { false }
   public var maskEvaluated: Bool { false }
   public var codewordsBuilt: Bool { false }
   public var version: Int? { selectedVersion }
   public var size: Int? { selectedVersion.map { $0 * 4 + 17 } }
   public var mode: QRMode {
      let modes = Set(segments.filter { !$0.isControl }.map(\.mode))
      return modes.count > 1 ? .mixed : modes.first ?? .byte
   }
   public var controlSegments: [QRSegmentDiagnostics] { segmentDiagnostics.filter { !$0.mode.isData } }
   public var boostedErrorCorrection: Bool { errorCorrectionLevel != requestedErrorCorrectionLevel }
   public var eciAssignmentNumber: Int? { controlSegments.compactMap(\.assignmentNumber).first }
   public var fnc1: String? {
      segments.contains(.fnc1)
         ? "first-position" : segments.contains(where: { $0.mode == .fnc1Second }) ? "second-position" : nil
   }
   public var gs1: Bool { segments.contains(.fnc1) }
   public var fnc1SecondApplicationIndicator: String? { controlSegments.compactMap(\.applicationIndicator).first }
   public var fnc1Second: QRFNC1SecondDiagnostics {
      .init(
         enabled: fnc1 == "second-position", applicationIndicator: fnc1SecondApplicationIndicator,
         applicationIndicatorCodeword: controlSegments.compactMap(\.applicationIndicatorCodeword).first)
   }
   public var structuredAppend: QRStructuredAppendHeader? { controlSegments.compactMap(\.structuredAppend).first }
   public var remainingBits: Int { capacityBits - dataBitLength }
   public var overflowBits: Int { max(0, -remainingBits) }
   public var capacityUtilization: Double { Double(dataBitLength) / Double(capacityBits) }
   public var usageRatio: Double { capacityUtilization }
   public var error: QRError? {
      ok ? nil : .dataTooLong(requiredBits: dataBitLength, capacityBits: capacityBits, version: evaluatedVersion)
   }
}

public struct QRMaskPenalty: Equatable, Sendable {
   public let maskPattern: Int
   public let penalty: Int
   public init(maskPattern: Int, penalty: Int) {
      self.maskPattern = maskPattern
      self.penalty = penalty
   }
}

public struct QRDiagnostics: Equatable, Sendable {
   public let planning: QRPlan
   public let maskPattern: Int
   public let maskPenalty: Int
   public let maskPenalties: [QRMaskPenalty]
   public let dataCodewords: Int
   public let errorCorrectionCodewords: Int
   public let totalCodewords: Int
   public var version: Int { planning.evaluatedVersion }
   public var size: Int { version * 4 + 17 }
   public var errorCorrectionLevel: ErrorCorrectionLevel { planning.errorCorrectionLevel }
   public var requestedErrorCorrectionLevel: ErrorCorrectionLevel { planning.requestedErrorCorrectionLevel }
   public var boostedErrorCorrection: Bool { planning.boostedErrorCorrection }
   public var dataBitLength: Int { planning.dataBitLength }
   public var capacityBits: Int { planning.capacityBits }
   public var remainingBits: Int { planning.remainingBits }
   public var capacityUtilization: Double { planning.capacityUtilization }
   public var inputBytes: Int { planning.inputBytes }
   public var mode: QRMode { planning.mode }
   public var segments: [QRSegmentDiagnostics] { planning.segmentDiagnostics }
   public var controlSegments: [QRSegmentDiagnostics] { planning.controlSegments }
   public var versionSelection: String { planning.versionSelection }
   public var versionSelectionReason: String { planning.versionSelectionReason }
   public var maskSelectionReason: String {
      maskPenalties.count == 1
         ? "Mask pattern \(maskPattern) was requested explicitly."
         : "Mask pattern \(maskPattern) had the lowest penalty score (\(maskPenalty)) among the evaluated masks."
   }
   public var eciAssignmentNumber: Int? { planning.eciAssignmentNumber }
   public var fnc1: String? { planning.fnc1 }
   public var gs1: Bool { planning.gs1 }
   public var gs1Validation: QRGS1ValidationDiagnostics { planning.gs1Validation }
   public var fnc1Second: QRFNC1SecondDiagnostics { planning.fnc1Second }
   public var structuredAppend: QRStructuredAppendHeader? { planning.structuredAppend }
}

public struct QRCode: Equatable, Sendable {
   public let matrix: [[Bool]]
   public let version: Int
   public let errorCorrectionLevel: ErrorCorrectionLevel
   public let maskPattern: Int
   public let segments: [QRSegment]
   public let dataCodewords: [UInt8]
   public let codewords: [UInt8]
   public let diagnostics: QRDiagnostics
   public var size: Int { matrix.count }
   public var planning: QRPlan { diagnostics.planning }
}

public struct QRCapacity: Equatable, Sendable {
   public let version: Int
   public let errorCorrectionLevel: ErrorCorrectionLevel
   public let dataCodewords: Int
   public let totalCodewords: Int
   public let mode: QRMode?
   public let characterCountBits: Int?
   public let controlBits: Int
   public let payloadBits: Int?
   public let maxCharacters: Int?
   public let maxBytes: Int?
   public var size: Int { version * 4 + 17 }
   public var capacityBits: Int { dataCodewords * 8 }
   public var modeIndicatorBits: Int? { mode == nil ? nil : 4 }
   public var errorCorrectionCodewords: Int { totalCodewords - dataCodewords }
}

/// A dependency-free QR Model 2 encoder and planning facade.
public enum SpecQR {}
