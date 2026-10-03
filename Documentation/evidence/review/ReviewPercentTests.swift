import XCTest
@testable import SpecQR
final class ReviewPercentTests: XCTestCase {
    func testFNC1SecondAndManualOptionSafeguards() throws {
        for indicator in ["00", "37", "A", "z"] {
            for optimize in [true, false] {
                let options = QROptions(optimizeSegments: optimize, fnc1Second:indicator)
                let text = "A%%B%\u{1D}C%"
                let plan = try SpecQR.estimate(text, options:options)
                let code = try SpecQR.generate(text, options:options)
                XCTAssertEqual(plan, code.planning)
                XCTAssertEqual(plan.segments, [.fnc1Second(indicator), .byteText(text)])
                XCTAssertEqual(code.matrix, try SpecQR.generate(text, options:.init(mode:.byte,fnc1Second:indicator)).matrix)
                XCTAssertThrowsError(try SpecQR.generate(text, options:.init(mode:.alphanumeric,fnc1Second:indicator))) { error in
                    XCTAssertEqual((error as? QRError)?.code, "INVALID_MODE")
                }
            }
        }
        for options in [QROptions(gs1:true), .init(fnc1Second:"A")] {
            XCTAssertThrowsError(try SpecQR.generate(segments:[.alphanumeric("A%%B")],options:options))
            XCTAssertNoThrow(try SpecQR.generate(segments:[.byteText("A%%B")],options:options))
        }
        XCTAssertNoThrow(try SpecQR.generate(segments:[.fnc1, .alphanumeric("A%%B")]))
        XCTAssertNoThrow(try SpecQR.generate(segments:[.fnc1Second("37"), .alphanumeric("A%%B")]))
    }
    func testGS1LiteralPercentHonorsCapacityAndDisabledOptimization() throws {
        let texts = ["10ABC%DEF", "10ABC%%DEF", "10%", "10%%%", "10LOT%\u{1D}21SER%IAL"]
        for text in texts {
            for optimize in [true, false] {
                let options = QROptions(optimizeSegments: optimize, gs1: true)
                let plan = try SpecQR.estimate(text, options: options)
                let code = try SpecQR.generate(text, options: options)
                XCTAssertEqual(plan, code.planning)
                XCTAssertEqual(plan.mode, .byte)
                XCTAssertEqual(plan.segments, [.fnc1, .byteText(text)])
                XCTAssertEqual(plan.inputBytes, text.utf8.count)
                XCTAssertEqual(code.matrix, try SpecQR.generate(text, options:.init(mode:.byte, gs1:true)).matrix)
            }
        }
        let options = QROptions(errorCorrectionLevel:.L, version:1, gs1:true)
        let exact = "10" + String(repeating:"X", count:14) + "%"
        XCTAssertEqual(exact.utf8.count, 17)
        XCTAssertTrue(try SpecQR.estimate(exact, options:options).ok)
        let overflow = exact + "X"
        XCTAssertFalse(try SpecQR.estimate(overflow, options:options).ok)
        XCTAssertThrowsError(try SpecQR.generate(overflow, options:options))
        XCTAssertEqual(try SpecQR.generate("10ABC%DEF").segments, [.alphanumeric("10ABC%DEF")])
        XCTAssertThrowsError(try SpecQR.generate("10ABC%DEF", options:.init(mode:.alphanumeric, gs1:true)))
    }
}
