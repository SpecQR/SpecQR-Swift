import Foundation

extension GS1 {
   /// Concrete metadata in the same stable order as upstream, including expanded AI families.
   public static func getSupportedAIs() -> [AIInfo] { supportedAIs }
   /// Returns nil for an AI outside the bounded supported catalog.
   public static func getAIInfo(_ ai: String) -> AIInfo? { aiDictionary[ai] }

   private static let aiDictionary = Dictionary(uniqueKeysWithValues: supportedAIs.map { ($0.ai, $0) })
   private static let supportedAIs: [AIInfo] = {
      func entry(
         _ ai: String, _ label: String, _ length: AILength, _ kind: ValueKind = .numeric,
         _ check: CheckDigitRule = .none, _ role: DigitalLinkRole = .dataAttribute
      ) -> AIInfo {
         AIInfo(
            ai: ai, label: label, length: length, valueKind: kind, checkDigitRule: check,
            digitalLinkRole: role, digitalLinkPathForPrimary: role == .keyQualifier ? ["01"] : nil,
            separator: length.isVariable ? .requiredWhenFollowed : .none)
      }
      var result: [AIInfo] = [
         entry("00", "Serial shipping container code", .fixed(exact: 18), .numeric, .sscc, .primaryKey),
         entry("01", "Global trade item number", .fixed(exact: 14), .numeric, .gtin, .primaryKey),
         entry("02", "Contained trade item GTIN", .fixed(exact: 14), .numeric, .gtin),
         entry("10", "Batch or lot number", .variable(min: 1, max: 20), .text, .none, .keyQualifier),
         entry("11", "Production date", .fixed(exact: 6)),
         entry("12", "Due date", .fixed(exact: 6)),
         entry("13", "Packaging date", .fixed(exact: 6)),
         entry("15", "Best before date", .fixed(exact: 6)),
         entry("16", "Sell by date", .fixed(exact: 6)),
         entry("17", "Expiration date", .fixed(exact: 6)),
         entry("20", "Internal product variant", .fixed(exact: 2)),
         entry("21", "Serial number", .variable(min: 1, max: 20), .text, .none, .keyQualifier),
         entry("22", "Consumer product variant", .variable(min: 1, max: 20), .text, .none, .keyQualifier),
         entry("30", "Variable count", .variable(min: 1, max: 8)),
         entry("37", "Count of contained trade items", .variable(min: 1, max: 8)),
         entry("240", "Additional product identification", .variable(min: 1, max: 30), .text),
         entry("241", "Customer part number", .variable(min: 1, max: 30), .text),
         entry("400", "Customer purchase order number", .variable(min: 1, max: 30), .text),
         entry("410", "Ship to global location number", .fixed(exact: 13)),
         entry("411", "Bill to global location number", .fixed(exact: 13)),
         entry("412", "Purchased from global location number", .fixed(exact: 13)),
         entry("413", "Ship for global location number", .fixed(exact: 13)),
         entry("414", "Identification of a physical location", .fixed(exact: 13), .numeric, .none, .primaryKey),
         entry("415", "Global location number of the invoicing party", .fixed(exact: 13)),
         entry("420", "Ship to postal code", .variable(min: 1, max: 20), .text),
         entry("422", "Country of origin", .fixed(exact: 3)),
         entry("424", "Country of processing", .fixed(exact: 3)),
         entry("425", "Country of disassembly", .fixed(exact: 3)),
         entry("426", "Country covering full process chain", .fixed(exact: 3)),
      ]
      result += (3100...3105).map { entry(String($0), "Net weight in kilograms", .fixed(exact: 6)) }
      result += (3200...3205).map { entry(String($0), "Net weight in pounds", .fixed(exact: 6)) }
      result += (91...99).map { entry(String($0), "Company internal information", .variable(min: 1, max: 90), .text) }
      return result
   }()
}
