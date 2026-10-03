// QR Model 2 standard parameter data; values verified against the SpecQR JS reference.
internal enum QRTables {
   static let eccPerBlock: [[Int]] = [
      [
         -1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30,
         30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
      ],
      [
         -1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28,
         28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
      ],
      [
         -1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30,
         30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
      ],
      [
         -1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30,
         30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
      ],
   ]
   static let blockCount: [[Int]] = [
      [
         -1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17,
         18, 19, 19, 20, 21, 22, 24, 25,
      ],
      [
         -1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29,
         31, 33, 35, 37, 38, 40, 43, 45, 47, 49,
      ],
      [
         -1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38,
         40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68,
      ],
      [
         -1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45,
         48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81,
      ],
   ]

   static func rawCodewords(_ version: Int) -> Int {
      var modules = (16 * version + 128) * version + 64
      if version > 1 {
         let alignments = version / 7 + 2
         modules -= (25 * alignments - 10) * alignments - 55
         if version > 6 { modules -= 36 }
      }
      return modules / 8
   }
   static func dataCodewords(_ version: Int, _ level: ErrorCorrectionLevel) -> Int {
      rawCodewords(version) - blockCount[level.ordinal][version] * eccPerBlock[level.ordinal][version]
   }
   static func countBits(_ mode: QRMode, _ version: Int) -> Int {
      let band = version < 10 ? 0 : version < 27 ? 1 : 2
      switch mode {
      case .numeric: return [10, 12, 14][band]
      case .alphanumeric: return [9, 11, 13][band]
      case .byte: return [8, 16, 16][band]
      case .kanji: return [8, 10, 12][band]
      default: return 0
      }
   }
}
