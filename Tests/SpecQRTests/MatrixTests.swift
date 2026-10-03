import XCTest

@testable import SpecQR

final class MatrixTests: XCTestCase {
   func testPenaltyForUniformAndCheckerboardMatrices() {
      let white = Array(repeating: Array(repeating: false, count: 21), count: 21)
      let black = Array(repeating: Array(repeating: true, count: 21), count: 21)
      // 42 runs of length 21, 400 uniform 2x2 blocks, 100 balance points.
      XCTAssertEqual(MaskPenaltyEvaluator.score(white), 2_098)
      XCTAssertEqual(MaskPenaltyEvaluator.score(black), 2_098)
      let alternating = (0..<21).map { row in (0..<21).map { (row + $0) % 2 == 0 } }
      XCTAssertEqual(MaskPenaltyEvaluator.score(alternating), 0)
   }

   func testFinderSeparatorsTimingAndDarkModuleRemainFixed() {
      for mask in 0...7 {
         let result = MatrixBuilder.build(
            codewords: Array(repeating: 0, count: 26),
            version: 1, level: .L, mask: mask)
         let symbol = result.matrix
         XCTAssertEqual(symbol.count, 21)
         XCTAssertTrue(symbol.allSatisfy { $0.count == 21 })
         for (left, top) in [(0, 0), (14, 0), (0, 14)] {
            for row in 0..<7 {
               for column in 0..<7 {
                  let radius = max(abs(row - 3), abs(column - 3))
                  XCTAssertEqual(symbol[top + row][left + column], radius != 2)
               }
            }
         }
         for offset in 0...7 {
            XCTAssertFalse(symbol[7][offset])
            XCTAssertFalse(symbol[offset][7])
         }
         for coordinate in 8..<13 {
            XCTAssertEqual(symbol[6][coordinate], coordinate % 2 == 0)
            XCTAssertEqual(symbol[coordinate][6], coordinate % 2 == 0)
         }
         XCTAssertTrue(symbol[13][8])
         XCTAssertEqual(result.maskPattern, mask)
         XCTAssertEqual(result.penalties.count, 1)
         XCTAssertEqual(result.penalties.first?.penalty, result.penalty)
         XCTAssertEqual(MaskPenaltyEvaluator.score(symbol), result.penalty)
      }
   }

   func testFormatAndVersionBCHWords() {
      let small = MatrixBuilder.build(codewords: [], version: 1, level: .L, mask: 0).matrix
      let formatWord = 0x77C4  // L/0 format codeword including XOR mask 0x5412.
      let formatCoordinates = (0...5).map { (8, $0) } + [(8, 7), (8, 8), (7, 8)] + (0...5).map { (5 - $0, 8) }
      for bit in 0..<15 {
         let (column, row) = formatCoordinates[bit]
         XCTAssertEqual(small[row][column], formatWord & (1 << bit) != 0)
      }
      let large = MatrixBuilder.build(codewords: [], version: 7, level: .H, mask: 3).matrix
      let versionWord = 0x07C94
      for bit in 0..<18 {
         let far = 45 - 11 + bit % 3
         let near = bit / 3
         let dark = versionWord & (1 << bit) != 0
         XCTAssertEqual(large[near][far], dark)
         XCTAssertEqual(large[far][near], dark)
      }
   }

   func testAlignmentCentersIncludingVersion32Exception() {
      let cases: [(Int, [Int])] = [
         (2, [6, 18]), (7, [6, 22, 38]),
         (32, [6, 34, 60, 86, 112, 138]),
         (40, [6, 30, 58, 86, 114, 142, 170]),
      ]
      for (version, centers) in cases {
         let symbol = MatrixBuilder.build(codewords: [], version: version, level: .M, mask: 7).matrix
         for (rowIndex, row) in centers.enumerated() {
            for (columnIndex, column) in centers.enumerated() {
               let last = centers.count - 1
               if (rowIndex == 0 && (columnIndex == 0 || columnIndex == last)) || (rowIndex == last && columnIndex == 0)
               {
                  continue
               }
               for dy in -2...2 {
                  for dx in -2...2 {
                     XCTAssertEqual(symbol[row + dy][column + dx], max(abs(dx), abs(dy)) != 1)
                  }
               }
            }
         }
      }
   }

   func testAutomaticSelectionUsesLowestPenalty() {
      let codewords = (0..<26).map { UInt8(($0 * 37 + 11) % 256) }
      let result = MatrixBuilder.build(codewords: codewords, version: 1, level: .Q, mask: nil)
      XCTAssertEqual(result.penalties.map(\.maskPattern), Array(0...7))
      let best = result.penalties.min {
         ($0.penalty, $0.maskPattern) < ($1.penalty, $1.maskPattern)
      }!
      XCTAssertEqual(result.maskPattern, best.maskPattern)
      XCTAssertEqual(result.penalty, best.penalty)
      let forced = MatrixBuilder.build(codewords: codewords, version: 1, level: .Q, mask: result.maskPattern)
      XCTAssertEqual(forced.matrix, result.matrix)
   }
}
