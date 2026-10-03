import Foundation

extension GS1 {
   /// Calculates the GS1 modulo-10 digit, applying alternating weights 3 and 1 from the right.
   public static func calculateCheckDigit(_ digits: String) throws -> String {
      try requireDigits(digits, label: "GS1 check digit input")
      var sum = 0
      for (index, digit) in digits.utf8.reversed().enumerated() {
         sum = (sum + Int(digit - 48) * (index % 2 == 0 ? 3 : 1)) % 10
      }
      return String((10 - sum) % 10)
   }
   /// Throws for malformed input; returns false for a correctly shaped but incorrect check digit.
   public static func validateCheckDigit(_ digits: String) throws -> Bool {
      try requireDigits(digits, label: "GS1 check digit value")
      guard digits.utf8.count >= 2 else {
         throw GS1Error("GS1 check digit value must include body digits and one check digit")
      }
      return try calculateCheckDigit(String(digits.dropLast())) == String(digits.suffix(1))
   }
   public static func calculateGTINCheckDigit(_ body: String) throws -> String {
      try requireDigits(body, label: "GTIN body")
      guard [7, 11, 12, 13].contains(body.utf8.count) else {
         throw GS1Error("GTIN body must be 7, 11, 12, or 13 digits")
      }
      return try calculateCheckDigit(body)
   }
   public static func appendGTINCheckDigit(_ body: String) throws -> String { try body + calculateGTINCheckDigit(body) }
   public static func validateGTINCheckDigit(_ gtin: String) throws -> Bool {
      try requireDigits(gtin, label: "GTIN")
      guard [8, 12, 13, 14].contains(gtin.utf8.count) else { throw GS1Error("GTIN must be 8, 12, 13, or 14 digits") }
      return try validateCheckDigit(gtin)
   }
   public static func calculateSSCCCheckDigit(_ body: String) throws -> String {
      try requireDigits(body, label: "SSCC body")
      guard body.utf8.count == 17 else { throw GS1Error("SSCC body must be exactly 17 digits") }
      return try calculateCheckDigit(body)
   }
   public static func appendSSCCCheckDigit(_ body: String) throws -> String { try body + calculateSSCCCheckDigit(body) }
   public static func validateSSCCCheckDigit(_ sscc: String) throws -> Bool {
      try requireDigits(sscc, label: "SSCC")
      guard sscc.utf8.count == 18 else { throw GS1Error("SSCC must be exactly 18 digits") }
      return try validateCheckDigit(sscc)
   }

   /// Converts validated human-readable `(AI)value` pairs into elements.
   public static func parseHumanReadable(_ input: String) throws -> [Element] {
      let text = Array(input.utf16)
      guard !text.isEmpty else { throw GS1Error("GS1 human-readable input must not be empty") }
      var result: [Element] = []
      var position = 0
      while position < text.count {
         guard text[position] == 40 else {
            throw GS1Error("GS1 human-readable input must contain an AI in parentheses at offset \(position)")
         }
         guard let close = text[(position + 1)...].firstIndex(of: 41) else {
            throw GS1Error("GS1 AI starting at offset \(position) is missing a closing parenthesis")
         }
         let end = text[(close + 1)...].firstIndex(of: 40) ?? text.count
         let element = Element(ai: utf16(text, position + 1, close), value: utf16(text, close + 1, end))
         _ = try normalize(element, index: result.count)
         result.append(element)
         position = end
      }
      return result
   }

   /// Produces raw GS1 data with ASCII GS separators after each non-final variable-length element.
   public static func createElementString(_ elements: [Element]) throws -> String {
      guard !elements.isEmpty else { throw GS1Error("GS1 elements must not be empty") }
      var result = ""
      for (index, element) in elements.enumerated() {
         let info = try normalize(element, index: index)
         result += element.ai + element.value
         if info.length.isVariable && index < elements.count - 1 { result += fnc1Separator }
      }
      return result
   }

   /// Parses raw GS1 data. Matches upstream's conservative missing-separator heuristic:
   /// a final variable value ending in a complete fixed-length element is rejected as ambiguous.
   public static func parseElementString(_ input: String) throws -> ElementStringParseResult {
      guard !input.isEmpty else { throw GS1Error("GS1 element string input must not be empty") }
      guard !input.contains("(") && !input.contains(")") else {
         throw GS1Error(
            "GS1 element string input must be raw data without human-readable parentheses; use parseGs1HumanReadable() and createGs1ElementString() before generate(..., { gs1: true })"
         )
      }
      let text = Array(input.utf16)
      var elements: [Element] = []
      var position = 0
      while position < text.count {
         guard text[position] != 29 else {
            throw GS1Error("GS1 element string has an unexpected FNC1 separator at offset \(position)")
         }
         guard let info = readAI(text, position) else { throw GS1Error("Unsupported GS1 AI at offset \(position)") }
         let start = position + info.ai.utf8.count
         let end: Int
         switch info.length {
         case .fixed(let exact): end = min(text.count, start + exact)
         case .variable: end = text[start...].firstIndex(of: 29) ?? text.count
         }
         if info.length.isVariable && end == text.count && end - start > 1 {
            for candidate in (start + 1)..<end {
               if let next = readAI(text, candidate), case .fixed(let exact) = next.length,
                  candidate + next.ai.utf8.count + exact == end
               {
                  throw GS1Error(
                     "GS1 variable-length element at offset \(start) is missing an FNC1 separator before offset \(candidate)"
                  )
               }
            }
         }
         let element = Element(ai: info.ai, value: utf16(text, start, end))
         _ = try normalize(element, index: elements.count)
         elements.append(element)
         position = end
         if position < text.count && text[position] == 29 && info.length.isVariable {
            position += 1
            guard position < text.count else {
               throw GS1Error("GS1 element string must not end with an FNC1 separator")
            }
         }
      }
      return ElementStringParseResult(elements: elements, hasSeparators: input.contains(fnc1Separator))
   }

   /// Validates individual elements, optionally requiring at least one Digital Link primary key.
   /// Like upstream, Digital Link context here does not check duplicate AIs or path placement.
   public static func validateElements(_ elements: [Element], options: ValidationOptions = .init()) -> ValidationResult
   {
      if let issue = validationOptionsIssue(options) { return ValidationResult(errors: [issue]) }
      guard !elements.isEmpty else {
         return ValidationResult(errors: [
            .init("GS1_INVALID_INPUT", "GS1 elements must not be empty", reason: "invalid-input")
         ])
      }
      var errors: [ValidationIssue] = []
      for (index, element) in elements.enumerated() {
         do { _ = try normalize(element, index: index) } catch {
            errors.append(validationIssue(error, element: element, elementIndex: index))
            if !options.collectAllErrors { break }
         }
      }
      if !errors.isEmpty { return ValidationResult(errors: errors) }
      if options.context == .digitalLink
         && !elements.contains(where: { getAIInfo($0.ai)?.digitalLinkRole == .primaryKey })
      {
         return ValidationResult(errors: [
            .init(
               "GS1_INVALID_DIGITAL_LINK_PLACEMENT",
               "GS1 Digital Link elements must include a primary AI 00, 01, or 414",
               reason: "invalid-digital-link-placement", expected: "primary AI 00, 01, or 414")
         ])
      }
      return ValidationResult(elements: elements)
   }

   /// Nonthrowing raw parser. Upstream validates options but does not apply Digital Link context
   /// or error collection to raw strings, because parsing must stop at the first malformed field.
   public static func validateElementString(_ input: String, options: ValidationOptions = .init()) -> ValidationResult {
      if let issue = validationOptionsIssue(options) { return ValidationResult(errors: [issue]) }
      do {
         let result = try parseElementString(input)
         return ValidationResult(elements: result.elements, hasSeparators: result.hasSeparators)
      } catch { return ValidationResult(errors: [validationIssue(error, input: input)]) }
   }

   static func normalize(_ element: Element, index: Int) throws -> AIInfo {
      let ai = element.ai
      let value = element.value
      guard isAI(ai) else {
         throw GS1Error("GS1 element \(index) has invalid AI \(jsonQuote(ai)); expected 2 to 4 digits")
      }
      guard let info = getAIInfo(ai) else {
         throw GS1Error("Unsupported GS1 AI \(ai). Add explicit support before using it.")
      }
      guard !value.isEmpty else { throw GS1Error("GS1 AI \(ai) value must not be empty") }
      guard !value.contains(fnc1Separator) else {
         throw GS1Error("GS1 AI \(ai) value must not contain the FNC1 separator")
      }
      guard !value.contains("(") && !value.contains(")") else {
         throw GS1Error("GS1 AI \(ai) value must be raw data without human-readable parentheses")
      }
      guard value.utf8.allSatisfy({ 32...126 ~= $0 }) else {
         throw GS1Error("GS1 AI \(ai) value must use printable ASCII characters")
      }
      if info.valueKind == .numeric && !isDigits(value) {
         throw GS1Error("GS1 AI \(ai) value must contain digits only")
      }
      switch info.length {
      case .fixed(let exact):
         guard value.utf8.count == exact else {
            throw GS1Error("GS1 AI \(ai) value must be exactly \(exact) characters")
         }
      case .variable(_, let max):
         guard value.utf8.count <= max else { throw GS1Error("GS1 AI \(ai) value must be at most \(max) characters") }
      }
      if try info.checkDigitRule == .gtin && !validateGTINCheckDigit(value) {
         throw GS1Error("GS1 AI \(ai) value has an invalid GTIN check digit")
      }
      if try info.checkDigitRule == .sscc && !validateSSCCCheckDigit(value) {
         throw GS1Error("GS1 AI \(ai) value has an invalid SSCC check digit")
      }
      return info
   }
   static func isAI(_ ai: String) -> Bool { (2...4).contains(ai.utf8.count) && isDigits(ai) }
   static func isDigits(_ text: String) -> Bool { !text.isEmpty && text.utf8.allSatisfy { 48...57 ~= $0 } }
   private static func requireDigits(_ text: String, label: String) throws {
      guard isDigits(text) else { throw GS1Error("\(label) must contain digits only") }
   }
   private static func readAI(_ text: [UInt16], _ offset: Int) -> AIInfo? {
      for length in [4, 3, 2] where offset + length <= text.count {
         if let info = getAIInfo(utf16(text, offset, offset + length)) { return info }
      }
      return nil
   }
   static func utf16(_ text: [UInt16], _ start: Int, _ end: Int) -> String {
      String(decoding: text[start..<end], as: UTF16.self)
   }
   static func jsonQuote(_ string: String) -> String {
      guard let data = try? JSONEncoder().encode(string), let result = String(data: data, encoding: .utf8) else {
         return "\"\""
      }
      return result.replacingOccurrences(of: "\\/", with: "/")
   }
   static func capture(_ pattern: String, in text: String, group: Int = 1) -> String? {
      guard let regex = try? NSRegularExpression(pattern: pattern),
         let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
         group < match.numberOfRanges, let range = Range(match.range(at: group), in: text)
      else { return nil }
      return String(text[range])
   }
   private static func validationOptionsIssue(_ options: ValidationOptions) -> ValidationIssue? {
      options.allowUnsupportedAI
         ? .init(
            "GS1_INVALID_INPUT", "GS1 validation options.allowUnsupportedAi must be false", reason: "invalid-options",
            expected: .boolean(false)) : nil
   }

   static func validationIssue(_ error: Error, element: Element? = nil, elementIndex: Int? = nil, input: String? = nil)
      -> ValidationIssue
   {
      let message = (error as? GS1Error)?.message ?? String(describing: error)
      var issue = ValidationIssue("GS1_INVALID_INPUT", message, reason: "invalid-input")
      if message.contains("Unsupported GS1 AI") {
         issue = .init("GS1_UNSUPPORTED_AI", message, reason: "unsupported-ai", expected: "supported GS1 AI")
      } else if let expectation = capture("(exactly [0-9]+ characters|at most [0-9]+ characters)", in: message) {
         issue = .init("GS1_INVALID_LENGTH", message, reason: "invalid-length", expected: .string(expectation))
      } else if message.contains("digits only") || message.contains("printable ASCII") {
         issue = .init(
            "GS1_INVALID_CHARSET", message, reason: "invalid-charset",
            expected: .string(message.contains("digits only") ? "digits only" : "printable ASCII"))
      } else if message.contains("missing an FNC1 separator") {
         issue = .init(
            "GS1_MISSING_SEPARATOR", message, reason: "missing-separator",
            expected: "FNC1 separator before the next GS1 element")
      } else if message.contains("unexpected FNC1 separator") || message.contains("must not end with an FNC1 separator")
         || message.contains("must not contain the FNC1 separator")
      {
         issue = .init(
            "GS1_UNEXPECTED_SEPARATOR", message, reason: "unexpected-separator",
            expected: "separator only after a non-final variable-length GS1 element")
      } else if message.contains("invalid GTIN check digit") || message.contains("invalid SSCC check digit") {
         issue = .init(
            "GS1_INVALID_CHECK_DIGIT", message, reason: "invalid-check-digit",
            expected: .string(message.contains("SSCC") ? "valid SSCC check digit" : "valid GTIN check digit"))
      } else if message.contains("cannot be placed in the Digital Link path") {
         issue = .init("GS1_INVALID_DIGITAL_LINK_PLACEMENT", message, reason: "invalid-digital-link-placement")
      } else if capture("duplicate AI ([0-9]{2,4})", in: message) != nil {
         issue = .init(
            "GS1_DUPLICATE_AI", message, reason: "duplicate-ai", expected: "unique GS1 AI within the Digital Link URI")
      }
      issue.ai = capture("GS1 AI ([0-9]{2,4})", in: message) ?? capture("duplicate AI ([0-9]{2,4})", in: message)
      issue.offset = capture("offset ([0-9]+)", in: message).flatMap(Int.init)
      issue.elementIndex = capture("GS1 element ([0-9]+)", in: message).flatMap(Int.init) ?? elementIndex
      issue.value = element?.value
      if issue.ai == nil, let input, let offset = issue.offset {
         let bytes = Array(input.utf16)
         if offset <= bytes.count { issue.ai = capture("^([0-9]{2,4})", in: utf16(bytes, offset, bytes.count)) }
         if issue.ai == nil {
            for length in [2, 3, 4] where offset >= length && offset <= bytes.count {
               let candidate = utf16(bytes, offset - length, offset)
               if getAIInfo(candidate) != nil {
                  issue.ai = candidate
                  break
               }
            }
         }
      }
      return issue
   }
}
