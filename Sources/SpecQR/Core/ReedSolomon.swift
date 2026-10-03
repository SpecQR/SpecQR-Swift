/// Reed-Solomon over GF(256), primitive polynomial x⁸+x⁴+x³+x²+1 (0x11D).
/// Polynomial coefficients are stored in descending power order.
internal enum ReedSolomon {
   static func multiply(_ a: UInt8, _ b: UInt8) -> UInt8 {
      var x = Int(a)
      var y = Int(b)
      var product = 0
      while y != 0 {
         if y & 1 != 0 { product ^= x }
         y >>= 1
         x <<= 1
         if x & 0x100 != 0 { x ^= 0x11D }
      }
      return UInt8(product)
   }
   static func generator(degree: Int) -> [UInt8] {
      var polynomial: [UInt8] = [1]
      var root: UInt8 = 1
      for _ in 0..<degree {
         var next = [UInt8](repeating: 0, count: polynomial.count + 1)
         for (i, coefficient) in polynomial.enumerated() {
            next[i] ^= coefficient
            next[i + 1] ^= multiply(coefficient, root)
         }
         polynomial = next
         root = multiply(root, 2)
      }
      return polynomial
   }
   static func remainder(data: [UInt8], generator: [UInt8]) -> [UInt8] {
      let degree = generator.count - 1
      var work = data + [UInt8](repeating: 0, count: degree)
      for i in data.indices {
         let factor = work[i]
         if factor == 0 { continue }
         for j in generator.indices { work[i + j] ^= multiply(generator[j], factor) }
      }
      return Array(work.suffix(degree))
   }
   static func interleave(_ data: [UInt8], version: Int, level: ErrorCorrectionLevel) -> [UInt8] {
      let count = QRTables.blockCount[level.ordinal][version]
      let ecc = QRTables.eccPerBlock[level.ordinal][version]
      let shortCount = count - QRTables.rawCodewords(version) % count
      let shortLength = data.count / count
      let polynomial = generator(degree: ecc)
      var blocks: [[UInt8]] = []
      var checks: [[UInt8]] = []
      var offset = 0
      for i in 0..<count {
         let length = shortLength + (i < shortCount ? 0 : 1)
         let block = Array(data[offset..<(offset + length)])
         blocks.append(block)
         checks.append(remainder(data: block, generator: polynomial))
         offset += length
      }
      var result: [UInt8] = []
      result.reserveCapacity(QRTables.rawCodewords(version))
      for column in 0...shortLength {
         for block in blocks where column < block.count { result.append(block[column]) }
      }
      for column in 0..<ecc {
         for check in checks { result.append(check[column]) }
      }
      return result
   }
}
