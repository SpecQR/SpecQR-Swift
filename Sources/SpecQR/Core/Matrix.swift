// QR Model 2 symbol construction. Coordinates are (column, row); exported
// matrices are indexed [row][column]. All storage and operations are native Swift.

internal struct MatrixBuildResult {
   let matrix: [[Bool]]
   let maskPattern: Int
   let penalty: Int
   let penalties: [QRMaskPenalty]
}

internal enum MatrixBuilder {
   static func build(
      codewords: [UInt8],
      version: Int,
      level: ErrorCorrectionLevel,
      mask: Int?
   ) -> MatrixBuildResult {
      precondition((1...40).contains(version), "QR versions range from 1 through 40")
      precondition(mask == nil || (0...7).contains(mask!), "QR masks range from 0 through 7")

      var template = SymbolGrid(size: 17 + 4 * version)
      template.installPatterns(version: version, level: level)
      template.place(codewords)

      var scores: [QRMaskPenalty] = []
      var selected: SymbolGrid?
      var selectedMask = 0
      var selectedPenalty = Int.max
      for pattern in mask.map({ [$0] }) ?? Array(0...7) {
         var candidate = template
         candidate.maskData(using: pattern)
         candidate.installFormat(level: level, mask: pattern)
         let score = MaskPenaltyEvaluator.score(candidate.modules, size: candidate.size)
         scores.append(QRMaskPenalty(maskPattern: pattern, penalty: score))
         // Strict comparison retains the first (lowest numbered) tied mask.
         if score < selectedPenalty {
            selected = candidate
            selectedMask = pattern
            selectedPenalty = score
         }
      }
      return MatrixBuildResult(
         matrix: selected!.rows,
         maskPattern: selectedMask,
         penalty: selectedPenalty,
         penalties: scores
      )
   }
}

/// Flat storage avoids accidental row/column transposition and keeps reserved
/// modules separate from their current color, including reserved light modules.
private struct SymbolGrid {
   let size: Int
   var modules: [Bool]
   private var reserved: [Bool]

   init(size: Int) {
      self.size = size
      modules = Array(repeating: false, count: size * size)
      reserved = Array(repeating: false, count: size * size)
   }

   var rows: [[Bool]] {
      (0..<size).map { row in
         Array(modules[(row * size)..<((row + 1) * size)])
      }
   }

   private mutating func function(_ x: Int, _ y: Int, _ dark: Bool) {
      guard x >= 0, y >= 0, x < size, y < size else { return }
      let index = y * size + x
      modules[index] = dark
      reserved[index] = true
   }

   mutating func installPatterns(version: Int, level: ErrorCorrectionLevel) {
      // A finder has a dark 3x3 center and a dark 7x7 outer ring.
      // The outer light ring is its separator and is clipped at the border.
      for (centerX, centerY) in [(3, 3), (size - 4, 3), (3, size - 4)] {
         for y in -4...4 {
            for x in -4...4 {
               let radius = max(abs(x), abs(y))
               function(centerX + x, centerY + y, radius != 2 && radius != 4)
            }
         }
      }
      for coordinate in 8..<(size - 8) {
         let dark = coordinate.isMultiple(of: 2)
         function(coordinate, 6, dark)
         function(6, coordinate, dark)
      }

      let centers = Self.alignmentCenters(version: version)
      if !centers.isEmpty {
         let last = centers.count - 1
         for row in centers.indices {
            for column in centers.indices {
               // Only the three finder corners omit alignment patterns.
               if (row == 0 && (column == 0 || column == last)) || (row == last && column == 0) { continue }
               for y in -2...2 {
                  for x in -2...2 {
                     function(
                        centers[column] + x, centers[row] + y,
                        max(abs(x), abs(y)) != 1)
                  }
               }
            }
         }
      }

      // Reserving the format areas before placement also reserves light bits.
      installFormat(level: level, mask: 0)
      function(8, size - 8, true)
      if version >= 7 {
         let versionWord = Self.bch(payload: version, degree: 12, generator: 0x1F25)
         for bit in 0..<18 {
            let nearEdge = size - 11 + bit % 3
            let nearCorner = bit / 3
            let dark = versionWord & (1 << bit) != 0
            function(nearEdge, nearCorner, dark)
            function(nearCorner, nearEdge, dark)
         }
      }
   }

   /// Centers are evenly spaced backwards from the far edge. The first center
   /// stays at 6; version 32 uses the standard's exceptional 26-module spacing.
   private static func alignmentCenters(version: Int) -> [Int] {
      guard version > 1 else { return [] }
      let count = version / 7 + 2
      let denominator = 2 * (count - 1)
      let spacing = version == 32 ? 26 : 2 * ((4 * version + 4 + denominator - 1) / denominator)
      let finalCenter = 4 * version + 10
      return [6] + (0..<(count - 1)).map { finalCenter - (count - 2 - $0) * spacing }
   }

   /// Polynomial long division over GF(2), yielding the systematic BCH word.
   private static func bch(payload: Int, degree: Int, generator: Int) -> Int {
      let shifted = payload << degree
      var remainder = shifted
      let highestBit = Int.bitWidth - shifted.leadingZeroBitCount - 1
      if highestBit >= degree {
         for bit in stride(from: highestBit, through: degree, by: -1) {
            if remainder & (1 << bit) != 0 {
               remainder ^= generator << (bit - degree)
            }
         }
      }
      return shifted | remainder
   }

   mutating func installFormat(level: ErrorCorrectionLevel, mask: Int) {
      let payload = (level.formatBits << 3) | mask
      let word = Self.bch(payload: payload, degree: 10, generator: 0x537) ^ 0x5412
      let firstCopy: [(Int, Int)] = (0...5).map { (8, $0) } + [(8, 7), (8, 8), (7, 8)] + (0...5).map { (5 - $0, 8) }
      let secondCopy: [(Int, Int)] = (0...7).map { (size - 1 - $0, 8) } + (0...6).map { (8, size - 7 + $0) }
      for bit in 0..<15 {
         let dark = word & (1 << bit) != 0
         function(firstCopy[bit].0, firstCopy[bit].1, dark)
         function(secondCopy[bit].0, secondCopy[bit].1, dark)
      }
   }

   mutating func place(_ codewords: [UInt8]) {
      var rightColumn = size - 1
      var upward = true
      var bit = 0
      while rightColumn > 0 {
         // The vertical timing column is skipped as a complete column.
         if rightColumn == 6 { rightColumn -= 1 }
         for step in 0..<size {
            let row = upward ? size - 1 - step : step
            for column in [rightColumn, rightColumn - 1] {
               let index = row * size + column
               guard !reserved[index] else { continue }
               if bit < codewords.count * 8 {
                  modules[index] = codewords[bit / 8] & (1 << (7 - bit % 8)) != 0
               }
               // Any unfilled data modules are the zero-valued remainder bits.
               bit += 1
            }
         }
         upward.toggle()
         rightColumn -= 2
      }
   }

   mutating func maskData(using pattern: Int) {
      for row in 0..<size {
         for column in 0..<size {
            let index = row * size + column
            if !reserved[index] && Self.shouldInvert(pattern, column: column, row: row) {
               modules[index].toggle()
            }
         }
      }
   }

   private static func shouldInvert(_ pattern: Int, column: Int, row: Int) -> Bool {
      let product = column * row
      switch pattern {
      case 0: return (column + row) % 2 == 0
      case 1: return row % 2 == 0
      case 2: return column % 3 == 0
      case 3: return (column + row) % 3 == 0
      case 4: return (row / 2 + column / 3) % 2 == 0
      case 5: return product % 2 + product % 3 == 0
      case 6: return (product % 2 + product % 3) % 2 == 0
      case 7: return ((column + row) % 2 + product % 3) % 2 == 0
      default: preconditionFailure("Invalid QR mask")
      }
   }
}

/// Penalties N1...N4 evaluated on the completed symbol, including format bits.
/// N3 counts exact 11-module windows with four light modules on either side of
/// 1011101, matching the canonical SpecQR scoring convention at symbol edges.
internal enum MaskPenaltyEvaluator {
   static func score(_ matrix: [[Bool]]) -> Int {
      precondition(!matrix.isEmpty && matrix.allSatisfy { $0.count == matrix.count })
      return score(matrix.flatMap { $0 }, size: matrix.count)
   }

   static func score(_ modules: [Bool], size: Int) -> Int {
      var total = 0
      for line in 0..<size {
         total += linePenalty(modules, start: line * size, step: 1, count: size)
         total += linePenalty(modules, start: line, step: size, count: size)
      }
      for row in 0..<(size - 1) {
         for column in 0..<(size - 1) {
            let index = row * size + column
            let color = modules[index]
            if modules[index + 1] == color && modules[index + size] == color && modules[index + size + 1] == color {
               total += 3
            }
         }
      }
      let darkCount = modules.reduce(0) { $0 + ($1 ? 1 : 0) }
      total += (abs(darkCount * 20 - size * size * 10) / (size * size)) * 10
      return total
   }

   private static func linePenalty(_ modules: [Bool], start: Int, step: Int, count: Int) -> Int {
      var total = 0
      var previous = modules[start]
      var run = 0
      var window = 0
      for offset in 0..<count {
         let color = modules[start + offset * step]
         if color == previous {
            run += 1
         } else {
            if run >= 5 { total += run - 2 }
            previous = color
            run = 1
         }
         window = ((window << 1) | (color ? 1 : 0)) & 0x7FF
         if offset >= 10 && (window == 0b101_11010000 || window == 0b000_01011101) {
            total += 40
         }
      }
      if run >= 5 { total += run - 2 }
      return total
   }
}
