import Foundation
import Testing

@testable import SpecQR

struct ConcurrencyTests {
   @Test
   func testConcurrentDeterministicGenerationAndRendering() async throws {
      let payloads = ["HELLO", "漢字かな123", "https://example.com", "😀 e\u{0301}"]
      let expected = try payloads.map { try SpecQR.generate($0) }
      let expectedPNG = try expected.map { try $0.png(options: .init(scale: 2)) }
      let outcomes = try await withThrowingTaskGroup(of: Bool.self, returning: [Bool].self) { group in
         for i in 0..<96 {
            group.addTask {
               let index = i % payloads.count
               let code = try SpecQR.generate(payloads[index])
               let bytes = try code.png(options: .init(scale: 2))
               let gs1 = try GS1.createElementString([.init(ai: "01", value: "09501101530003")])
               return code == expected[index] && bytes == expectedPNG[index] && gs1 == "0109501101530003"
            }
         }
         var results: [Bool] = []
         for try await value in group { results.append(value) }
         return results
      }
      #expect(outcomes.count == 96)
      #expect(outcomes.allSatisfy { $0 })
   }
   @Test
   func testCopiedMatricesDoNotMutateResults() throws {
      let original = try SpecQR.generate("immutable")
      let before = original.matrix
      var matrix = original.matrix
      matrix[0][0].toggle()
      #expect(original.matrix == before)
      #expect(matrix != original.matrix)
   }
}
