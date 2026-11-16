import XCTest
@testable import wacomd

final class ResolveControlsTests: XCTestCase {
    func testCapturedPanelButtonsAndRelease() {
        var panel = ResolvePanel()
        for index in 0..<6 {
            let report: [UInt8] = [3, 0x80, 0, 0, 1 << index, 0, 0, 0, 0, 0]
            XCTAssertEqual(panel.update(report: report, active: true), [ResolvePanel.buttons[index]])
            XCTAssertEqual(panel.update(report: report, active: true), [])
            XCTAssertEqual(panel.update(report: [3, 0x80, 0, 0, 0, 0, 0, 0, 0, 0], active: true), [])
        }
        XCTAssertEqual(ResolvePanel.buttons[2], .init(key: 6, modifiers: 0x120000))
        // Capacitive touch alone must not activate a mechanical button.
        XCTAssertEqual(panel.update(report: [3, 0x80, 0, 0, 0, 0x3f, 0, 0, 0, 0], active: true), [])
        XCTAssertEqual(panel.update(report: [3, 0x80, 0, 1, 0, 0, 0, 0, 0, 0], active: true), [])
        XCTAssertEqual(panel.mode, 1)
    }

    func testRingWrapDirectionLiftAndInvalidPackets() {
        var panel = ResolvePanel()
        func ring(_ value: UInt8) -> [UInt8] { [3, 0x80, value, 0, 0, 0, 0, 0, 0, 0] }
        XCTAssertEqual(panel.update(report: ring(0xc6), active: true), []) // 70
        XCTAssertEqual(panel.update(report: ring(0x80), active: true), [.init(key: 124)]) // wrap clockwise
        XCTAssertEqual(panel.update(report: ring(0xc6), active: true), [.init(key: 123)])
        XCTAssertEqual(panel.update(report: ring(0), active: true), [])
        XCTAssertEqual(panel.update(report: ring(0x90), active: true), []) // landing must not seek
        XCTAssertEqual(panel.update(report: ring(0xb0), active: true), []) // discard large jump
        XCTAssertEqual(panel.update(report: ring(0xff), active: true), []) // invalid position
        XCTAssertEqual(panel.update(report: [3], active: true), [])
        XCTAssertEqual(panel.update(report: [2, 0x80, 0, 0, 1, 0, 0, 0, 0, 0], active: true), [])
    }

    func testResolveScopeAndHeldButtonOnAppSwitch() {
        var panel = ResolvePanel()
        let held: [UInt8] = [3, 0x80, 0, 0, 1, 0, 0, 0, 0, 0]
        XCTAssertEqual(panel.update(report: held, active: false), [])
        XCTAssertEqual(panel.update(report: held, active: true), [])
        _ = panel.update(report: [3, 0x80, 0, 0, 0, 0, 0, 0, 0, 0], active: true)
        XCTAssertEqual(panel.update(report: held, active: true), [.init(key: 49)])
    }

    func testSeparatePenButtonsOnlyInResolve() {
        let resolve = PenButtonLayout.mapped(first: false, second: true, resolve: true)
        XCTAssertFalse(resolve.right)
        XCTAssertTrue(resolve.middle)
        let other = PenButtonLayout.mapped(first: false, second: true, resolve: false)
        XCTAssertTrue(other.right)
        XCTAssertFalse(other.middle)
        let first = PenButtonLayout.mapped(first: true, second: false, resolve: true)
        XCTAssertTrue(first.right)
        XCTAssertFalse(first.middle)
    }

    func testCentreCyclesFourModesAndLEDReport() {
        var panel = ResolvePanel()
        let pressed: [UInt8] = [3, 0x80, 0, 1, 0, 0, 0, 0, 0, 0]
        let released: [UInt8] = [3, 0x80, 0, 0, 0, 0, 0, 0, 0, 0]
        let expected: [ResolveShortcut] = [
            .init(key: 24, modifiers: 0x100000), .init(key: 125),
            .init(key: 125, modifiers: 0x20000), .init(key: 124)
        ]
        for next in 1...4 {
            XCTAssertEqual(panel.update(report: pressed, active: false), [])
            XCTAssertEqual(panel.mode, next % 4)
            _ = panel.update(report: pressed, active: false)
            XCTAssertEqual(panel.mode, next % 4) // held press must not repeat
            XCTAssertEqual(panel.ledReport, [0x20, UInt8(next % 4) | 4, 0, 0, 0, 0, 0, 0, 0])
            _ = panel.update(report: released, active: true)
            _ = panel.update(report: [3, 0x80, 0x80, 0, 0, 0, 0, 0, 0, 0], active: true)
            XCTAssertEqual(panel.update(report: [3, 0x80, 0x82, 0, 0, 0, 0, 0, 0, 0], active: true), [expected[next - 1]])
        }
    }
}
