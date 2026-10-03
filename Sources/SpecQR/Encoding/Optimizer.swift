internal enum SegmentOptimizer {
   private struct State {
      let mode: QRMode
      let remainder: Int
      let bits: Int
      let segmentCount: Int
      let previous: Int
      func precedes(_ other: State) -> Bool {
         bits < other.bits || (bits == other.bits && segmentCount < other.segmentCount)
      }
   }
   static func segment(_ text: String, mode: QRMode) -> QRSegment {
      switch mode {
      case .numeric: return .numeric(text)
      case .alphanumeric: return .alphanumeric(text)
      case .kanji: return .kanji(text)
      default: return .byteText(text)
      }
   }
   static func single(_ text: String, requested: QRMode, allowKanji: Bool) throws -> [QRSegment] {
      let selected: QRMode
      if requested != .auto {
         selected = requested
      } else if !text.isEmpty && text.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) {
         selected = .numeric
      } else if !text.isEmpty && text.unicodeScalars.allSatisfy({ SegmentEncoder.alphaValues[$0.value] != nil }) {
         selected = .alphanumeric
      } else if allowKanji && !text.isEmpty && text.unicodeScalars.allSatisfy({ KanjiMap.value($0) != nil }) {
         selected = .kanji
      } else {
         selected = .byte
      }
      let result = segment(text, mode: selected)
      try SegmentEncoder.validate(result)
      return [result]
   }
   /// Dynamic programming with at most seven live states per Unicode scalar.
   /// Remainders preserve the exact 10/3-bit and 11/2-bit packing costs.
   static func optimized(_ text: String, version: Int, allowKanji: Bool) -> [QRSegment] {
      let scalars = Array(text.unicodeScalars)
      if scalars.isEmpty { return [.byteText("")] }
      let modes: [QRMode] = allowKanji ? [.numeric, .alphanumeric, .kanji, .byte] : [.numeric, .alphanumeric, .byte]
      var layers: [[State]] = [[State(mode: .auto, remainder: 0, bits: 0, segmentCount: 0, previous: 0)]]
      layers.reserveCapacity(scalars.count + 1)
      for scalar in scalars {
         var next: [State] = []
         let utf8Count = String(scalar).utf8.count
         for (previous, state) in layers.last!.enumerated() {
            for mode in modes {
               if mode == .numeric && !(48...57).contains(scalar.value) { continue }
               if mode == .alphanumeric && SegmentEncoder.alphaValues[scalar.value] == nil { continue }
               if mode == .kanji && KanjiMap.value(scalar) == nil { continue }
               let same = mode == state.mode
               let remainder = same ? state.remainder : 0
               let extra: Int
               let nextRemainder: Int
               switch mode {
               case .numeric:
                  extra = remainder == 0 ? 4 : 3
                  nextRemainder = (remainder + 1) % 3
               case .alphanumeric:
                  extra = remainder == 0 ? 6 : 5
                  nextRemainder = (remainder + 1) % 2
               case .kanji:
                  extra = 13
                  nextRemainder = 0
               default:
                  extra = utf8Count * 8
                  nextRemainder = 0
               }
               let candidate = State(
                  mode: mode, remainder: nextRemainder,
                  bits: state.bits + extra + (same ? 0 : 4 + QRTables.countBits(mode, version)),
                  segmentCount: state.segmentCount + (same ? 0 : 1), previous: previous)
               if let index = next.firstIndex(where: { $0.mode == mode && $0.remainder == nextRemainder }) {
                  if candidate.precedes(next[index]) { next[index] = candidate }
               } else {
                  next.append(candidate)
               }
            }
         }
         layers.append(next)
      }
      var best = 0
      for i in layers.last!.indices where layers.last![i].precedes(layers.last![best]) { best = i }
      var assignments = [QRMode](repeating: .byte, count: scalars.count)
      for i in stride(from: scalars.count, through: 1, by: -1) {
         let state = layers[i][best]
         assignments[i - 1] = state.mode
         best = state.previous
      }
      var result: [QRSegment] = []
      var start = 0
      for end in 1...scalars.count {
         if end == scalars.count || assignments[end] != assignments[start] {
            let part = String(String.UnicodeScalarView(scalars[start..<end]))
            result.append(segment(part, mode: assignments[start]))
            start = end
         }
      }
      return result
   }
}
