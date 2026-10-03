import Foundation

/// A malformed or unsupported GS1 value. Nonthrowing validators expose more detailed issues.
public struct GS1Error: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
   public let message: String
   public var code: String { "INVALID_GS1" }
   public var description: String { message }
   public var errorDescription: String? { message }
   public init(_ message: String) { self.message = message }
}

/// GS1 helpers matching the deliberately bounded AI catalog in SpecQR 3.0.0-rc.2.
/// Values preserve leading zeros. Dates are validated for length and numeric characters,
/// not calendar validity. This namespace is not a complete GS1 specification validator.
public enum GS1 {
   public static let fnc1Separator = "\u{1D}"

   public struct Element: Sendable, Equatable, Hashable, Codable {
      public let ai: String
      public let value: String
      public init(ai: String, value: String) {
         self.ai = ai
         self.value = value
      }
   }

   public enum AILength: Sendable, Equatable, Codable {
      case fixed(exact: Int)
      case variable(min: Int, max: Int)
      private enum Keys: String, CodingKey { case type, exact, min, max }
      public init(from decoder: Decoder) throws {
         let c = try decoder.container(keyedBy: Keys.self)
         switch try c.decode(String.self, forKey: .type) {
         case "fixed": self = .fixed(exact: try c.decode(Int.self, forKey: .exact))
         case "variable":
            self = .variable(min: try c.decode(Int.self, forKey: .min), max: try c.decode(Int.self, forKey: .max))
         default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown GS1 AI length type")
         }
      }
      public func encode(to encoder: Encoder) throws {
         var c = encoder.container(keyedBy: Keys.self)
         switch self {
         case .fixed(let exact):
            try c.encode("fixed", forKey: .type)
            try c.encode(exact, forKey: .exact)
         case .variable(let min, let max):
            try c.encode("variable", forKey: .type)
            try c.encode(min, forKey: .min)
            try c.encode(max, forKey: .max)
         }
      }
      public var isVariable: Bool {
         if case .variable = self { return true }
         return false
      }
      public var maximum: Int {
         switch self {
         case .fixed(let exact): return exact
         case .variable(_, let max): return max
         }
      }
   }

   public enum ValueKind: String, Sendable, Codable { case numeric, text, date, decimal }
   public enum CheckDigitRule: String, Sendable, Codable { case none, gtin, sscc }
   public enum DigitalLinkRole: String, Sendable, Codable {
      case primaryKey = "primary-key", keyQualifier = "key-qualifier", dataAttribute = "data-attribute", notSupported =
         "not-supported"
   }
   public enum SeparatorRequirement: String, Sendable, Codable {
      case none, requiredWhenFollowed = "required-when-followed"
   }

   public struct AIInfo: Sendable, Equatable, Codable {
      public let ai: String
      public let label: String
      public let length: AILength
      public let valueKind: ValueKind
      public let checkDigitRule: CheckDigitRule
      public let digitalLinkRole: DigitalLinkRole
      public let digitalLinkPathForPrimary: [String]?
      public let separator: SeparatorRequirement
   }

   public struct ElementStringParseResult: Sendable, Equatable, Codable {
      public let elements: [Element]
      public let hasSeparators: Bool
      public init(elements: [Element], hasSeparators: Bool) {
         self.elements = elements
         self.hasSeparators = hasSeparators
      }
   }
   public enum ValidationContext: String, Sendable, Codable {
      case elementString = "element-string", digitalLink = "digital-link"
   }
   public struct ValidationOptions: Sendable, Equatable, Codable {
      public var context: ValidationContext
      /// Unsupported AIs are never accepted. Setting this flag returns an invalid-options issue.
      public var allowUnsupportedAI: Bool
      public var collectAllErrors: Bool
      public init(
         context: ValidationContext = .elementString, allowUnsupportedAI: Bool = false, collectAllErrors: Bool = true
      ) {
         self.context = context
         self.allowUnsupportedAI = allowUnsupportedAI
         self.collectAllErrors = collectAllErrors
      }
   }
   /// JSON-compatible expected value carried by a validation issue.
   public enum ExpectedValue: Sendable, Equatable, Codable, ExpressibleByStringLiteral {
      case string(String), boolean(Bool)
      public init(stringLiteral value: String) { self = .string(value) }
      public init(from decoder: Decoder) throws {
         let c = try decoder.singleValueContainer()
         if let v = try? c.decode(Bool.self) { self = .boolean(v) } else { self = .string(try c.decode(String.self)) }
      }
      public func encode(to encoder: Encoder) throws {
         var c = encoder.singleValueContainer()
         switch self {
         case .string(let v): try c.encode(v)
         case .boolean(let v): try c.encode(v)
         }
      }
   }
   public struct ValidationIssue: Sendable, Equatable, Codable {
      public let code: String
      public let message: String
      public var ai: String?
      public var value: String?
      public var key: String?
      /// UTF-16 offset, matching JavaScript string offsets in the upstream API.
      public var offset: Int?
      public var elementIndex: Int?
      public var reason: String?
      public var expected: ExpectedValue?
      public var count: Int?
      init(_ code: String, _ message: String, reason: String? = nil, expected: ExpectedValue? = nil) {
         self.code = code
         self.message = message
         self.reason = reason
         self.expected = expected
      }
   }
   /// On failure, `elements` and `hasSeparators` are nil and `errors` is nonempty.
   public struct ValidationResult: Sendable, Equatable, Encodable {
      public let ok: Bool
      public let elements: [Element]?
      public let hasSeparators: Bool?
      public let errors: [ValidationIssue]
      public let warnings: [ValidationIssue]
      init(elements: [Element], hasSeparators: Bool? = nil) {
         ok = true
         self.elements = elements
         self.hasSeparators = hasSeparators
         errors = []
         warnings = []
      }
      init(errors: [ValidationIssue]) {
         ok = false
         elements = nil
         hasSeparators = nil
         self.errors = errors
         warnings = []
      }
      private enum Keys: String, CodingKey { case ok, elements, hasSeparators, errors, warnings }
      public func encode(to encoder: Encoder) throws {
         var c = encoder.container(keyedBy: Keys.self)
         try c.encode(ok, forKey: .ok)
         try c.encode(warnings, forKey: .warnings)
         if ok {
            try c.encodeIfPresent(elements, forKey: .elements)
            try c.encodeIfPresent(hasSeparators, forKey: .hasSeparators)
         } else {
            try c.encode(errors, forKey: .errors)
         }
      }
   }
   public enum PrimaryAI: String, Sendable, Codable { case sscc = "00", gtin = "01", gln = "414" }
   public enum UnknownQueryPolicy: String, Sendable, Codable { case preserve, reject }
   public struct DigitalLinkOptions: Sendable, Equatable {
      public var baseURL: String
      public var primaryAI: PrimaryAI
      /// Nil uses eligible key qualifiers. An empty list puts every non-primary AI in the query.
      public var pathAIs: [String]?
      public init(baseURL: String, primaryAI: PrimaryAI = .gtin, pathAIs: [String]? = nil) {
         self.baseURL = baseURL
         self.primaryAI = primaryAI
         self.pathAIs = pathAIs
      }
      public init(baseURL: URL, primaryAI: PrimaryAI = .gtin, pathAIs: [String]? = nil) {
         self.init(baseURL: baseURL.absoluteString, primaryAI: primaryAI, pathAIs: pathAIs)
      }
   }
   public struct DigitalLinkParseOptions: Sendable, Equatable {
      public var primaryAI: PrimaryAI?
      public var unknownQuery: UnknownQueryPolicy
      public init(primaryAI: PrimaryAI? = nil, unknownQuery: UnknownQueryPolicy = .preserve) {
         self.primaryAI = primaryAI
         self.unknownQuery = unknownQuery
      }
   }
   public struct DigitalLinkValidationOptions: Sendable, Equatable {
      public var primaryAI: PrimaryAI?
      public var unknownQuery: UnknownQueryPolicy
      /// Kept for parity with upstream's explicit unsupported-option check; use normalizeDigitalLink instead.
      public var normalize: Bool
      public init(primaryAI: PrimaryAI? = nil, unknownQuery: UnknownQueryPolicy = .preserve, normalize: Bool = false) {
         self.primaryAI = primaryAI
         self.unknownQuery = unknownQuery
         self.normalize = normalize
      }
   }
   public struct DigitalLinkNormalizeOptions: Sendable, Equatable {
      public var primaryAI: PrimaryAI?
      public var unknownQuery: UnknownQueryPolicy
      /// Only "specqr-deterministic" is supported; this is not GS1 canonicalization.
      public var mode: String
      public init(
         primaryAI: PrimaryAI? = nil, unknownQuery: UnknownQueryPolicy = .preserve,
         mode: String = "specqr-deterministic"
      ) {
         self.primaryAI = primaryAI
         self.unknownQuery = unknownQuery
         self.mode = mode
      }
   }
   public struct UnknownQuery: Sendable, Equatable, Codable {
      public let key: String
      public let value: String
      public init(key: String, value: String) {
         self.key = key
         self.value = value
      }
   }
   public struct DigitalLinkParseResult: Sendable, Equatable, Codable {
      public let elements: [Element]
      public let primary: Element
      public let pathElements: [Element]
      public let queryElements: [Element]
      /// Preserves input order and repeated non-GS1 query parameters.
      public let unknownQuery: [UnknownQuery]
   }
   public struct DigitalLinkValidationResult: Sendable, Equatable, Encodable {
      public let ok: Bool
      public let result: DigitalLinkParseResult?
      public let errors: [ValidationIssue]
      public let warnings: [ValidationIssue]
      init(result: DigitalLinkParseResult, warnings: [ValidationIssue]) {
         ok = true
         self.result = result
         errors = []
         self.warnings = warnings
      }
      init(error: ValidationIssue) {
         ok = false
         result = nil
         errors = [error]
         warnings = []
      }
      private enum Keys: String, CodingKey { case ok, result, errors, warnings }
      public func encode(to encoder: Encoder) throws {
         var c = encoder.container(keyedBy: Keys.self)
         try c.encode(ok, forKey: .ok)
         try c.encode(warnings, forKey: .warnings)
         if ok { try c.encodeIfPresent(result, forKey: .result) } else { try c.encode(errors, forKey: .errors) }
      }
   }
}
