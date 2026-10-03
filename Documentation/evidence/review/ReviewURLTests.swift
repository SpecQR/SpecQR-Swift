import XCTest
@testable import SpecQR
final class ReviewURLTests: XCTestCase {
    func testHugeHexAuthorityIsRejected() {
        for host in ["0x10000000000000000", "0xffffffffffffffffffffffffffffffffffff", "999999999999999999999999", "0x100000000"] {
            XCTAssertFalse(GS1.validateDigitalLink("https://"+host+"/01/09501101530003").ok, host)
        }
    }
}
