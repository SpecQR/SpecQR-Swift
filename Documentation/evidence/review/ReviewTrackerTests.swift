import XCTest
@testable import SpecQR
final class ReviewTrackerTests: XCTestCase {
    func testCostOnlyTrackerMatchesFullOptimizer() throws {
        var seed: UInt32 = 773311
        let scalars = Array("0123456789ABCDEFGHIJKLMNOPQ $%*+-./:abcxyz漢字日本é😀\u{301}\u{0}".unicodeScalars)
        func next(_ limit: Int) -> Int { seed = seed &* 1664525 &+ 1013904223; return Int(seed) % limit }
        for version in [1, 9, 10, 26, 27, 40] {
            for _ in 0..<300 {
                var tracker = StructuredAppendEncoder.TextBitLengthTracker(version: version)
                let input = (0..<(1 + next(200))).map { _ in scalars[next(scalars.count)] }
                for scalar in input { _ = tracker.append(scalar) }
                let text = String(String.UnicodeScalarView(input))
                let segments = SegmentOptimizer.optimized(text, version: version, allowKanji: true)
                let expected = segments.reduce(0) { $0 + SegmentEncoder.bitLength($1, version: version) }
                XCTAssertEqual(tracker.best, expected, "version \(version): \(text)")
            }
        }
    }
}
