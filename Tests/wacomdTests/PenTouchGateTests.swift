import XCTest
@testable import wacomd

final class PenTouchGateTests: XCTestCase {
    func testHoverBlocksTouchUntilPenAndPalmAreLifted() {
        let gate = PenTouchGate()
        XCTAssertFalse(gate.shouldBlock(hasContacts: true, now: 1))
        gate.observe(reportID: 2, bytes: [2, 0x20, 0, 0, 0, 0, 0, 0, 0, 0], now: 2)
        XCTAssertTrue(gate.shouldBlock(hasContacts: true, now: 2))
        // A stationary hovering pen stays protected without a report timeout.
        XCTAssertTrue(gate.shouldBlock(hasContacts: true, now: 20))
        gate.observe(reportID: 2, bytes: [2, 0x80, 0, 0, 0, 0, 0, 0, 0, 0], now: 21)
        XCTAssertTrue(gate.shouldBlock(hasContacts: false, now: 21.1))
        XCTAssertTrue(gate.shouldBlock(hasContacts: true, now: 22))
        XCTAssertTrue(gate.shouldBlock(hasContacts: false, now: 22.1))
        XCTAssertFalse(gate.shouldBlock(hasContacts: true, now: 22.2))
    }

    func testIdleHeartbeatAndPanelCannotBlockTouch() {
        let gate = PenTouchGate()
        gate.observe(reportID: 192, bytes: [0xc0, 0, 0, 1, 0x10, 0x9c, 0x3b, 0xae, 0, 3], now: 1)
        gate.observe(reportID: 3, bytes: [3, 0x80, 0, 1, 0, 0, 0, 0, 0, 0], now: 1)
        gate.observe(reportID: 2, bytes: [2, 0xe0], now: 1)
        XCTAssertFalse(gate.penInRange)
        XCTAssertFalse(gate.shouldBlock(hasContacts: true, now: 2))
    }

    func testPenSampleAndDisconnectRecovery() {
        let gate = PenTouchGate()
        gate.observe(reportID: 2, bytes: [2, 0xe0, 0x0f, 0x6c, 0x1a, 0x37, 0x91, 0xe6, 0x52, 0x43], now: 1)
        XCTAssertTrue(gate.penInRange)
        gate.penRemoved(now: 2)
        XCTAssertFalse(gate.penInRange)
        XCTAssertTrue(gate.shouldBlock(hasContacts: false, now: 3))
        XCTAssertFalse(gate.shouldBlock(hasContacts: true, now: 4))
    }
}
