import Foundation

extension GS1 {
   /// Creates a deterministic Digital Link. Eligible path qualifiers retain input order;
   /// query AIs are sorted lexicographically. A base URL must be supplied explicitly.
   public static func createDigitalLink(_ elements: [Element], options: DigitalLinkOptions) throws -> String {
      guard !options.baseURL.isEmpty else { throw GS1Error("GS1 Digital Link options.baseUrl is required") }
      var url: GS1URL
      do { url = try GS1URL(options.baseURL) } catch {
         throw GS1Error("GS1 Digital Link options.baseUrl must be a valid http or https URL")
      }
      guard url.scheme == "https" || url.scheme == "http" else {
         throw GS1Error("GS1 Digital Link options.baseUrl must use http or https")
      }
      guard (url.query ?? "").isEmpty && (url.fragment ?? "").isEmpty else {
         throw GS1Error("GS1 Digital Link options.baseUrl must not include query or fragment components")
      }
      let primaryAI = options.primaryAI.rawValue
      if let pathAIs = options.pathAIs {
         for ai in pathAIs {
            guard isAI(ai) else { throw GS1Error("GS1 Digital Link pathAis entries must be 2 to 4 digit AI strings") }
            if ai != primaryAI { try assertPathPlacement(ai, primary: primaryAI) }
         }
      }
      guard !elements.isEmpty else { throw GS1Error("GS1 Digital Link input elements must not be empty") }
      var seen = Set<String>()
      for (index, element) in elements.enumerated() {
         _ = try normalize(element, index: index)
         try rejectDuplicate(seen, element.ai)
         seen.insert(element.ai)
      }
      guard let primary = elements.first(where: { $0.ai == primaryAI }) else {
         throw GS1Error("GS1 Digital Link input must include primary AI \(primaryAI)")
      }
      func inPath(_ ai: String) -> Bool {
         options.pathAIs.map { $0.contains(ai) } ?? canPlaceInPath(ai, primary: primaryAI)
      }
      let pathElements = [primary] + elements.filter { $0.ai != primaryAI && inPath($0.ai) }
      let queryElements = elements.filter { $0.ai != primaryAI && !inPath($0.ai) }.sorted {
         $0.ai == $1.ai ? $0.value < $1.value : $0.ai < $1.ai
      }
      let prefix = String(url.path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression))
      let suffix = pathElements.flatMap { [percentEncode($0.ai, form: false), percentEncode($0.value, form: false)] }
         .joined(separator: "/")
      url.path = GS1URL.normalizePath(prefix + "/" + suffix)
      url.query =
         queryElements.isEmpty
         ? nil
         : queryElements.map { percentEncode($0.ai, form: true) + "=" + percentEncode($0.value, form: true) }.joined(
            separator: "&")
      return url.string
   }
   public static func createDigitalLink(_ parsed: ElementStringParseResult, options: DigitalLinkOptions) throws
      -> String
   {
      try createDigitalLink(parsed.elements, options: options)
   }
   public static func createDigitalLink(_ parsed: DigitalLinkParseResult, options: DigitalLinkOptions) throws -> String
   {
      try createDigitalLink(parsed.elements, options: options)
   }
   /// Parses path qualifiers, GS1 query attributes, and ordered unknown query parameters.
   public static func parseDigitalLink(_ uri: String, options: DigitalLinkParseOptions = .init()) throws
      -> DigitalLinkParseResult
   {
      try parseDigitalLinkURL(normalizedDigitalLinkURL(uri), options: options)
   }
   public static func parseDigitalLink(_ uri: URL, options: DigitalLinkParseOptions = .init()) throws
      -> DigitalLinkParseResult
   {
      try parseDigitalLink(uri.absoluteString, options: options)
   }
   /// Nonthrowing validation, including percent-escape syntax and HTTP/unknown-query warnings.
   public static func validateDigitalLink(_ uri: String, options: DigitalLinkValidationOptions = .init())
      -> DigitalLinkValidationResult
   {
      if options.normalize {
         return DigitalLinkValidationResult(
            error: .init(
               "GS1_INVALID_INPUT", "GS1 Digital Link validation options.normalize is not implemented yet",
               reason: "unsupported-option", expected: .boolean(false)))
      }
      do {
         let url = try GS1URL(uri)
         guard !invalidPercentEncoding(url.path) && !invalidPercentEncoding(url.query ?? "") else {
            throw GS1Error("GS1 Digital Link URI must use valid percent-encoding")
         }
         try checkDigitalLinkURL(url)
         let parsed = try parseDigitalLinkURL(
            url, options: .init(primaryAI: options.primaryAI, unknownQuery: options.unknownQuery))
         var warnings: [ValidationIssue] = []
         if url.scheme == "http" {
            warnings.append(
               .init(
                  "GS1_DIGITAL_LINK_HTTP",
                  "GS1 Digital Link URI uses http. Use https when transport security is required.", reason: "http-uri"))
         }
         if !parsed.unknownQuery.isEmpty {
            var warning = ValidationIssue(
               "GS1_DIGITAL_LINK_UNKNOWN_QUERY_PRESERVED",
               "GS1 Digital Link URI contains non-GS1 query parameters preserved in unknownQuery.",
               reason: "unknown-query-preserved")
            warning.count = parsed.unknownQuery.count
            warnings.append(warning)
         }
         return DigitalLinkValidationResult(result: parsed, warnings: warnings)
      } catch { return DigitalLinkValidationResult(error: digitalLinkIssue(error)) }
   }
   public static func validateDigitalLink(_ uri: URL, options: DigitalLinkValidationOptions = .init())
      -> DigitalLinkValidationResult
   {
      validateDigitalLink(uri.absoluteString, options: options)
   }
   /// Deterministic SpecQR normalization: move eligible query qualifiers into the path, sort
   /// GS1 query attributes, preserve unknown parameters in their original relative order.
   public static func normalizeDigitalLink(_ uri: String, options: DigitalLinkNormalizeOptions = .init()) throws
      -> String
   {
      guard options.mode == "specqr-deterministic" else {
         throw GS1Error("GS1 Digital Link normalization mode must be \"specqr-deterministic\"")
      }
      var url = try normalizedDigitalLinkURL(uri)
      guard !invalidPercentEncoding(url.path) && !invalidPercentEncoding(url.query ?? "") else {
         throw GS1Error("GS1 Digital Link URI must use valid percent-encoding")
      }
      let parseOptions = DigitalLinkParseOptions(primaryAI: options.primaryAI, unknownQuery: options.unknownQuery)
      let parsed = try parseDigitalLinkURL(url, options: parseOptions)
      let segments = try pathSegments(url.path)
      let start = try firstPrimaryIndex(segments, preferred: options.primaryAI)
      url.path = "/" + segments[..<start].joined(separator: "/")
      url.query = nil
      url.fragment = nil
      let primaryAI = PrimaryAI(rawValue: parsed.primary.ai)!
      var normalized = try GS1URL(
         createDigitalLink(parsed.elements, options: .init(baseURL: url.string, primaryAI: primaryAI)))
      let unknown = parsed.unknownQuery.map {
         percentEncode($0.key, form: true) + "=" + percentEncode($0.value, form: true)
      }.joined(separator: "&")
      if !unknown.isEmpty { normalized.query = normalized.query.map { $0 + "&" + unknown } ?? unknown }
      return normalized.string
   }
   public static func normalizeDigitalLink(_ uri: URL, options: DigitalLinkNormalizeOptions = .init()) throws -> String
   {
      try normalizeDigitalLink(uri.absoluteString, options: options)
   }

   private static func normalizedDigitalLinkURL(_ uri: String) throws -> GS1URL {
      let url = try GS1URL(uri)
      try checkDigitalLinkURL(url)
      return url
   }
   private static func checkDigitalLinkURL(_ url: GS1URL) throws {
      guard url.scheme == "http" || url.scheme == "https" else {
         throw GS1Error("GS1 Digital Link URI must use http or https")
      }
      guard (url.fragment ?? "").isEmpty else { throw GS1Error("GS1 Digital Link URI must not include a fragment") }
   }
   private static func pathSegments(_ path: String) throws -> [String] {
      let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      guard !trimmed.isEmpty else { throw GS1Error("GS1 Digital Link path must include primary AI 00, 01, or 414") }
      let segments = trimmed.components(separatedBy: "/")
      guard !segments.contains("") else { throw GS1Error("GS1 Digital Link path must not contain empty segments") }
      return segments
   }
   private static func firstPrimaryIndex(_ segments: [String], preferred: PrimaryAI?) throws -> Int {
      guard
         let index = segments.firstIndex(where: { segment in
            preferred.map { $0.rawValue == segment } ?? (getAIInfo(segment)?.digitalLinkRole == .primaryKey)
         })
      else {
         throw GS1Error("GS1 Digital Link path must include primary AI 00, 01, or 414")
      }
      return index
   }
   private static func parseDigitalLinkURL(_ url: GS1URL, options: DigitalLinkParseOptions) throws
      -> DigitalLinkParseResult
   {
      let segments = try pathSegments(url.path)
      let start = try firstPrimaryIndex(segments, preferred: options.primaryAI)
      guard (segments.count - start) % 2 == 0 else {
         throw GS1Error("GS1 Digital Link path must contain AI/value pairs")
      }
      var path: [Element] = []
      var query: [Element] = []
      var unknown: [UnknownQuery] = []
      var seen = Set<String>()
      for index in stride(from: start, to: segments.count, by: 2) {
         let ai = segments[index]
         guard isAI(ai) else { throw GS1Error("GS1 Digital Link path segment \(index + 1) must be a GS1 AI") }
         guard let value = percentDecode(segments[index + 1], form: false, strict: true) else {
            throw GS1Error("GS1 Digital Link path value for AI \(ai) must be valid percent-encoding")
         }
         let element = Element(ai: ai, value: value)
         _ = try normalize(element, index: path.count)
         if let primary = path.first { try assertPathPlacement(ai, primary: primary.ai) }
         try rejectDuplicate(seen, ai)
         seen.insert(ai)
         path.append(element)
      }
      for pair in (url.query ?? "").components(separatedBy: "&") where !pair.isEmpty {
         let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
         let key = percentDecode(String(parts[0]), form: true, strict: false)!
         let value = percentDecode(parts.count > 1 ? String(parts[1]) : "", form: true, strict: false)!
         if isAI(key) {
            let element = Element(ai: key, value: value)
            _ = try normalize(element, index: path.count + query.count)
            try rejectDuplicate(seen, key)
            seen.insert(key)
            query.append(element)
         } else if options.unknownQuery == .preserve {
            unknown.append(.init(key: key, value: value))
         } else {
            throw GS1Error("GS1 Digital Link query parameter \(jsonQuote(key)) is not a GS1 AI")
         }
      }
      return .init(
         elements: path + query, primary: path[0], pathElements: path, queryElements: query, unknownQuery: unknown)
   }
   private static func canPlaceInPath(_ ai: String, primary: String) -> Bool {
      guard let info = getAIInfo(ai) else { return false }
      return info.digitalLinkRole == .keyQualifier && (info.digitalLinkPathForPrimary?.contains(primary) ?? false)
   }
   private static func assertPathPlacement(_ ai: String, primary: String) throws {
      guard getAIInfo(ai) != nil else {
         throw GS1Error("Unsupported GS1 AI \(ai). Add explicit support before using it.")
      }
      guard canPlaceInPath(ai, primary: primary) else {
         throw GS1Error("GS1 AI \(ai) cannot be placed in the Digital Link path after primary AI \(primary)")
      }
   }
   private static func rejectDuplicate(_ seen: Set<String>, _ ai: String) throws {
      guard !seen.contains(ai) else { throw GS1Error("GS1 Digital Link input must not contain duplicate AI \(ai)") }
   }
   private static func digitalLinkIssue(_ error: Error) -> ValidationIssue {
      let message = (error as? GS1Error)?.message ?? String(describing: error)
      if message.contains("absolute http or https URL") || message.contains("must use http or https") {
         return .init(
            "GS1_DIGITAL_LINK_INVALID_URI", message, reason: "invalid-uri", expected: "absolute http or https URL")
      }
      if message.contains("must not include a fragment") {
         return .init(
            "GS1_DIGITAL_LINK_FRAGMENT_NOT_ALLOWED", message, reason: "fragment-not-allowed",
            expected: "URI without fragment")
      }
      if message.contains("valid percent-encoding") {
         return .init(
            "GS1_INVALID_PERCENT_ENCODING", message, reason: "invalid-percent-encoding",
            expected: "percent escapes must use two hexadecimal digits")
      }
      if message.contains("query parameter") && message.contains("is not a GS1 AI") {
         var issue = ValidationIssue(
            "GS1_DIGITAL_LINK_UNKNOWN_QUERY", message, reason: "unknown-query",
            expected: "GS1 AI query parameter or unknownQuery: \"preserve\"")
         if let raw = capture("query parameter (\"(?:[^\"\\\\]|\\\\.)*\")", in: message),
            let data = raw.data(using: .utf8)
         {
            issue.key = try? JSONDecoder().decode(String.self, from: data)
         }
         return issue
      }
      if message.contains("path must include primary AI") || message.contains("path must contain AI/value pairs")
         || message.contains("path must not contain empty segments")
         || capture("path segment ([0-9]+) must be a GS1 AI", in: message) != nil
      {
         return .init(
            "GS1_INVALID_INPUT", message, reason: "malformed-path",
            expected: "Digital Link path containing primary AI and AI/value pairs")
      }
      return validationIssue(error)
   }
   private static func invalidPercentEncoding(_ text: String) -> Bool {
      percentDecode(text, form: false, strict: true, checkSyntaxOnly: true) == nil
   }
   private static func percentEncode(_ text: String, form: Bool) -> String {
      let safe = form ? "*-._" : "-_.!~*'()"
      let allowed = Set(safe.utf8)
      return text.utf8.map { byte in
         if (48...57 ~= byte) || (65...90 ~= byte) || (97...122 ~= byte) || allowed.contains(byte) {
            return String(UnicodeScalar(byte))
         }
         if form && byte == 32 { return "+" }
         return String(format: "%%%02X", byte)
      }.joined()
   }
   private static func percentDecode(_ text: String, form: Bool, strict: Bool, checkSyntaxOnly: Bool = false) -> String?
   {
      let bytes = Array(text.utf8)
      var decoded: [UInt8] = []
      decoded.reserveCapacity(bytes.count)
      var index = 0
      func hex(_ byte: UInt8) -> UInt8? {
         switch byte {
         case 48...57: return byte - 48
         case 65...70: return byte - 55
         case 97...102: return byte - 87
         default: return nil
         }
      }
      while index < bytes.count {
         if bytes[index] == 37 {
            if index + 2 < bytes.count, let a = hex(bytes[index + 1]), let b = hex(bytes[index + 2]) {
               decoded.append(a * 16 + b)
               index += 3
               continue
            }
            if strict { return nil }
         }
         decoded.append(form && bytes[index] == 43 ? 32 : bytes[index])
         index += 1
      }
      if checkSyntaxOnly { return "" }
      return strict ? String(bytes: decoded, encoding: .utf8) : String(decoding: decoded, as: UTF8.self)
   }
}

/// Small HTTP URL adapter: Foundation handles authority/IDNA; path/query behavior follows
/// the WHATWG operations used by upstream, preserving malformed escapes for validator errors.
private struct GS1URL {
   var scheme: String
   var authority: String
   var path: String
   var query: String?
   var fragment: String?
   var string: String {
      scheme + "://" + authority + path + (query.map { "?" + $0 } ?? "") + (fragment.map { "#" + $0 } ?? "")
   }

   init(_ input: String) throws {
      let failure = GS1Error("GS1 Digital Link URI must be an absolute http or https URL")
      let controls = CharacterSet(charactersIn: String((0...32).compactMap { UnicodeScalar($0).map(Character.init) }))
      let trimmed = input.trimmingCharacters(in: controls).replacingOccurrences(of: "\t", with: "")
         .replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
      guard let colon = trimmed.firstIndex(of: ":") else { throw failure }
      let rawScheme = String(trimmed[..<colon])
      guard rawScheme.range(of: "^[A-Za-z][A-Za-z0-9+.-]*$", options: .regularExpression) != nil else { throw failure }
      scheme = rawScheme.lowercased()
      var rest = String(trimmed[trimmed.index(after: colon)...])
      if let hash = rest.firstIndex(of: "#") {
         fragment = String(rest[rest.index(after: hash)...])
         rest = String(rest[..<hash])
      }
      if let question = rest.firstIndex(of: "?") {
         query = Self.encodeURLPart(String(rest[rest.index(after: question)...]), query: true)
         rest = String(rest[..<question])
      }
      let special = ["http", "https", "ftp", "ws", "wss"].contains(scheme)
      if special { rest = rest.replacingOccurrences(of: "\\", with: "/") }
      if special {
         rest = String(rest.drop(while: { $0 == "/" }))
      } else if rest.hasPrefix("//") {
         rest = String(rest.dropFirst(2))
      } else {
         authority = ""
         path = rest
         return
      }
      let slash = rest.firstIndex(of: "/") ?? rest.endIndex
      var rawAuthority = String(rest[..<slash])
      let rawPath = String(rest[slash...])
      guard !rawAuthority.isEmpty else { throw failure }
      if let at = rawAuthority.lastIndex(of: "@") {
         let credentials = rawAuthority[..<at].replacingOccurrences(of: "@", with: "%40")
         rawAuthority = credentials + String(rawAuthority[at...])
      }
      let hostAndPort =
         rawAuthority.split(separator: "@", omittingEmptySubsequences: false).last.map(String.init) ?? rawAuthority
      let rawPort: String?
      if hostAndPort.hasPrefix("["), let bracket = hostAndPort.lastIndex(of: "]") {
         let suffix = String(hostAndPort[hostAndPort.index(after: bracket)...])
         guard suffix.isEmpty || suffix.hasPrefix(":") else { throw failure }
         rawPort = suffix.isEmpty ? nil : String(suffix.dropFirst())
      } else if let colon = hostAndPort.lastIndex(of: ":") {
         rawPort = String(hostAndPort[hostAndPort.index(after: colon)...])
      } else {
         rawPort = nil
      }
      if let rawPort, !rawPort.isEmpty {
         guard rawPort.utf8.allSatisfy({ 48...57 ~= $0 }), let port = UInt64(rawPort), port <= 65535 else {
            throw failure
         }
      }
      guard var components = URLComponents(string: scheme + "://" + rawAuthority), let host = components.host,
         !host.isEmpty,
         !host.unicodeScalars.contains(where: { $0.value <= 32 || "#/%?@\\".unicodeScalars.contains($0) })
      else { throw failure }
      components.host = try Self.normalizeHost(host.lowercased())
      if let port = components.port {
         guard (0...65535).contains(port) else { throw failure }
         components.port = port
         if (scheme == "https" && port == 443) || (scheme == "http" && port == 80) || (scheme == "ftp" && port == 21) {
            components.port = nil
         }
      }
      if rawPort == "" { components.port = nil }
      guard let canonical = components.string, let prefix = canonical.range(of: "://") else { throw failure }
      authority = String(canonical[prefix.upperBound...])
      path = Self.normalizePath(Self.encodeURLPart(rawPath.isEmpty ? "/" : rawPath, query: false))
   }
   private static func normalizeHost(_ host: String) throws -> String {
      let failure = GS1Error("GS1 Digital Link URI must be an absolute http or https URL")
      if host.hasPrefix("[") {
         guard host.hasSuffix("]") else { throw failure }
         var address = String(host.dropFirst().dropLast())
         // WHATWG renders embedded dotted IPv4 as two hexadecimal IPv6 pieces.
         if address.contains(".") {
            guard let colon = address.lastIndex(of: ":") else { throw failure }
            let tail = address[address.index(after: colon)...].split(separator: ".", omittingEmptySubsequences: false)
            guard tail.count == 4 else { throw failure }
            let numbers = tail.compactMap { piece -> UInt16? in
               guard !piece.isEmpty, piece.utf8.allSatisfy({ 48...57 ~= $0 }),
                  piece.count == 1 || piece.first != "0", let value = UInt16(piece), value <= 255
               else { return nil }
               return value
            }
            guard numbers.count == 4 else { throw failure }
            address =
               String(address[...colon]) + String(numbers[0] * 256 + numbers[1], radix: 16) + ":"
               + String(numbers[2] * 256 + numbers[3], radix: 16)
         }
         let halves = address.components(separatedBy: "::")
         guard halves.count <= 2 else { throw failure }
         func groups(_ part: String) throws -> [UInt16] {
            if part.isEmpty { return [] }
            return try part.components(separatedBy: ":").map { piece in
               guard (1...4).contains(piece.utf8.count), piece.utf8.allSatisfy({ (48...57 ~= $0) || (97...102 ~= $0) }),
                  let value = UInt16(piece, radix: 16)
               else { throw failure }
               return value
            }
         }
         let left = try groups(halves[0])
         let right = try halves.count == 2 ? groups(halves[1]) : []
         var numbers: [UInt16]
         if halves.count == 2 {
            guard left.count + right.count < 8 else { throw failure }
            numbers = left + Array(repeating: 0, count: 8 - left.count - right.count) + right
         } else {
            guard left.count == 8 else { throw failure }
            numbers = left
         }
         var bestStart = 0
         var bestLength = 0
         var start = 0
         while start < numbers.count {
            if numbers[start] != 0 {
               start += 1
               continue
            }
            var end = start
            while end < numbers.count && numbers[end] == 0 { end += 1 }
            if end - start > bestLength {
               bestStart = start
               bestLength = end - start
            }
            start = end
         }
         let pieces = numbers.map { String($0, radix: 16) }
         if bestLength > 1 {
            return "[" + pieces[..<bestStart].joined(separator: ":") + "::"
               + pieces[(bestStart + bestLength)...].joined(separator: ":") + "]"
         }
         return "[" + pieces.joined(separator: ":") + "]"
      }
      var pieces = host.components(separatedBy: ".")
      if pieces.last == "" { pieces.removeLast() }
      guard let last = pieces.last, !last.isEmpty else { return host }
      func number(_ piece: String) -> UInt64? {
         if piece.hasPrefix("0x") {
            let digits = String(piece.dropFirst(2))
            guard digits.utf8.allSatisfy({ (48...57 ~= $0) || (97...102 ~= $0) }) else { return nil }
            return digits.isEmpty ? 0 : UInt64(digits, radix: 16)
         }
         if piece.count >= 2 && piece.first == "0" {
            let digits = piece.dropFirst()
            return digits.utf8.allSatisfy({ 48...55 ~= $0 }) ? UInt64(digits, radix: 8) : nil
         }
         return piece.utf8.allSatisfy({ 48...57 ~= $0 }) ? UInt64(piece, radix: 10) : nil
      }
      // Syntax decides whether this is an IPv4 host. Bounded conversion must not
      // turn an overflowing hexadecimal address into an ordinary DNS name.
      let hexadecimalLast =
         last.hasPrefix("0x")
         && last.dropFirst(2).utf8.allSatisfy({ (48...57 ~= $0) || (97...102 ~= $0) })
      let endsInNumber = last.utf8.allSatisfy({ 48...57 ~= $0 }) || hexadecimalLast
      guard endsInNumber else { return host }
      guard pieces.count <= 4 else { throw failure }
      let values = pieces.compactMap(number)
      guard values.count == pieces.count, let final = values.last,
         values.dropLast().allSatisfy({ $0 <= 255 }), final < (UInt64(1) << (8 * (5 - pieces.count)))
      else { throw failure }
      var ipv4 = final
      for (index, value) in values.dropLast().enumerated() { ipv4 += value << (8 * (3 - index)) }
      return [24, 16, 8, 0].map { String((ipv4 >> $0) & 255) }.joined(separator: ".")
   }
   static func normalizePath(_ path: String) -> String {
      var result: [String] = []
      let pieces = path.components(separatedBy: "/")
      for (index, piece) in pieces.enumerated() {
         let dot = piece.lowercased().replacingOccurrences(of: "%2e", with: ".")
         if dot == "." {
            if index == pieces.count - 1 { result.append("") }
            continue
         }
         if dot == ".." {
            if result.count > 1 { result.removeLast() }
            if index == pieces.count - 1 { result.append("") }
            continue
         }
         result.append(piece)
      }
      let joined = result.joined(separator: "/")
      return joined.hasPrefix("/") ? joined : "/" + joined
   }
   private static func encodeURLPart(_ text: String, query: Bool) -> String {
      let forbidden: Set<UInt8> = query ? [34, 35, 39, 60, 62] : [34, 35, 60, 62, 63, 96, 123, 125]
      return text.utf8.map { byte in
         byte <= 32 || byte > 126 || forbidden.contains(byte)
            ? String(format: "%%%02X", byte) : String(UnicodeScalar(byte))
      }.joined()
   }
}
