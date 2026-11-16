import Foundation
class XCTestCase {}
func XCTFail(_ message: String = "") { fatalError(message) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "") { precondition(a == b, message) }
func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "") { precondition(a != b, message) }
func XCTAssertGreaterThan<T: Comparable>(_ a: T, _ b: T, _ message: String = "") { precondition(a > b, message) }
func XCTAssertTrue(_ a: Bool, _ message: String = "") { precondition(a, message) }
func XCTAssertFalse(_ a: Bool, _ message: String = "") { precondition(!a, message) }
func XCTAssertNil<T>(_ a: T?, _ message: String = "") { precondition(a == nil, message) }
func XCTAssertNotNil<T>(_ a: T?, _ message: String = "") { precondition(a != nil, message) }
















/// Vecteurs de test issus de captures HID réelles d'une PTH-451 (toutes les
/// frames débutent par l'octet `0x02` qui est le Report ID).
final class IntuosProParserTests: XCTestCase {

    /// Décode un tableau d'octets via le parseur.
    private func decode(_ bytes: [UInt8]) -> IntuosProParser.Result {
        var buffer = bytes
        return buffer.withUnsafeMutableBufferPointer { buf in
            IntuosProParser.decode(reportID: UInt32(buf.baseAddress!.pointee),
                                   data: buf.baseAddress!,
                                   length: buf.count)
        }
    }

    func testRealPenSampleWithPressure() {
        // Frame capturée en live, pen pressant la surface :
        //   02 e0 0f 6c 1a 37 91 e6 52 43
        let res = decode([0x02, 0xe0, 0x0f, 0x6c, 0x1a, 0x37, 0x91, 0xe6, 0x52, 0x43])
        guard case .pen(let s) = res else {
            return XCTFail("attendu .pen, obtenu \(res)")
        }
        // Vérifications calculées manuellement à partir des formules Intuos Pro
        XCTAssertEqual(s.x, (0x0f << 9) | (0x6c << 1) | ((0x43 >> 1) & 1))   // 7897
        XCTAssertEqual(s.y, (0x1a << 9) | (0x37 << 1) | (0x43 & 1))           // 6767
        XCTAssertEqual(s.pressure,
                       (((0x91 << 2) | ((0xe6 >> 6) & 3)) << 1) | (0xe0 & 1)) // 1166
        XCTAssertTrue(s.tipDown, "pression > seuil → tip-switch attendu")
        XCTAssertEqual(s.distance, (0x43 >> 2) & 0x3f)
    }

    func testHoverPacketHasZeroPressureAndNoTip() {
        // Frame avec pression nulle (pen en survol) :
        //   02 e0 22 9d 1f 3f 00 22 52 64
        let res = decode([0x02, 0xe0, 0x22, 0x9d, 0x1f, 0x3f, 0x00, 0x22, 0x52, 0x64])
        guard case .pen(let s) = res else {
            return XCTFail("attendu .pen, obtenu \(res)")
        }
        XCTAssertEqual(s.pressure, 0)
        XCTAssertFalse(s.tipDown)
    }

    func testProximityLeaveRecognised() {
        // (data[1] & 0xfe) == 0x80 → sortie de proximité.
        let res = decode([0x02, 0x80, 0, 0, 0, 0, 0, 0, 0, 0])
        guard case .proximityLeave = res else {
            return XCTFail("attendu .proximityLeave, obtenu \(res)")
        }
    }

    func testProximityEnterDecodesToolID() {
        // (data[1] & 0xfc) == 0xc0 → entrée en proximité.
        // Octets choisis pour produire un toolID non-nul.
        let res = decode([0x02, 0xc2,
                          0x80, 0x10,
                          0x00, 0x00, 0x00, 0x02,
                          0x30, 0x00])
        guard case .proximityEnter(let toolID, _) = res else {
            return XCTFail("attendu .proximityEnter, obtenu \(res)")
        }
        XCTAssertNotEqual(toolID, 0)
    }

    func testWrongLengthIsIgnored() {
        let res = decode([0x02, 0xe0, 0x0f, 0x6c])  // tronqué
        guard case .ignored = res else {
            return XCTFail("attendu .ignored")
        }
    }

    func testWrongReportIDIsIgnored() {
        // Report ID 12 = pad (différent du pen, on ne le décode pas encore).
        let res = decode([0x0c, 0xe0, 0x0f, 0x6c, 0x1a, 0x37, 0x91, 0xe6, 0x52, 0x43])
        guard case .ignored = res else {
            return XCTFail("attendu .ignored")
        }
    }
}




final class ModelTests: XCTestCase {
    func testIntuosProSmallIdentity() {
        let m = IntuosProSmall()
        XCTAssertEqual(m.vendorID, 0x056a)
        XCTAssertEqual(m.productID, 0x0314)
        XCTAssertEqual(m.maxPressure, 2047)
        XCTAssertGreaterThan(m.maxX, 0)
        XCTAssertGreaterThan(m.maxY, 0)
    }

    func testKnownModelsLookup() {
        XCTAssertNotNil(KnownModels.lookup(vendorID: 0x056a, productID: 0x0314))
        XCTAssertNil(KnownModels.lookup(vendorID: 0x056a, productID: 0xffff))
    }
}




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

IntuosProParserTests().testRealPenSampleWithPressure()
IntuosProParserTests().testHoverPacketHasZeroPressureAndNoTip()
IntuosProParserTests().testProximityLeaveRecognised()
IntuosProParserTests().testProximityEnterDecodesToolID()
IntuosProParserTests().testWrongLengthIsIgnored()
IntuosProParserTests().testWrongReportIDIsIgnored()
ModelTests().testIntuosProSmallIdentity()
ModelTests().testKnownModelsLookup()
PenTouchGateTests().testHoverBlocksTouchUntilPenAndPalmAreLifted()
PenTouchGateTests().testIdleHeartbeatAndPanelCannotBlockTouch()
PenTouchGateTests().testPenSampleAndDisconnectRecovery()
ResolveControlsTests().testCapturedPanelButtonsAndRelease()
ResolveControlsTests().testRingWrapDirectionLiftAndInvalidPackets()
ResolveControlsTests().testResolveScopeAndHeldButtonOnAppSwitch()
ResolveControlsTests().testSeparatePenButtonsOnlyInResolve()
ResolveControlsTests().testCentreCyclesFourModesAndLEDReport()
print("Passed 16 upstream, Resolve and palm-rejection checks")

import Foundation
import WacomdShared

let old = try JSONDecoder().decode(WacomdConfig.self, from: Data("{\"naturalScroll\":true,\"cursorSensitivity\":0.7}".utf8))
precondition(old.naturalScroll && old.cursorSensitivity == 0.7 && old.palmRejection)
precondition(old.tabletShortcuts.count == 6 && old.penActions == [.leftClick, .rightClick])
var custom = old
custom.tabletShortcuts[0] = .init(title: "Custom", key: 40, modifiers: 1 << 19)
custom.ringShortcuts[1] = .init(title: "Forward", key: 12)
custom.ringStep = 4
let restored = try JSONDecoder().decode(WacomdConfig.self, from: JSONEncoder().encode(custom))
precondition(restored == custom)
precondition(custom.pressure(0) == 0 && custom.pressure(1) == 1 && custom.pressure(0.5) == 0.5)
custom.penPressureExponent = 0.5
precondition(custom.pressure(0.5) > 0.5)
for data in ["{\"tabletShortcuts\":[]}", "{\"ringStep\":0}", "{\"penPressureExponent\":0}", "{\"cursorSensitivity\":100}", "{\"penActions\":[\"invalid\"]}"] {
    do { _ = try JSONDecoder().decode(WacomdConfig.self, from: Data(data.utf8)); fatalError("Accepted invalid config") } catch {}
}
var panel = ResolvePanel()
let released: [UInt8] = [3,128,0,0,0,0,0,0,0,0]
precondition(panel.update(report: [3,128,0,0,1,0,0,0,0,0], active: true, config: custom) == [.init(key:40, modifiers:1 << 19)])
_ = panel.update(report: released, active: true, config: custom)
custom.tabletShortcuts[0].enabled = false
precondition(panel.update(report: [3,128,0,0,1,0,0,0,0,0], active:true, config:custom).isEmpty)
_ = panel.update(report:[3,128,128,0,0,0,0,0,0,0], active:true, config:custom)
precondition(panel.update(report:[3,128,130,0,0,0,0,0,0,0],active:true,config:custom).isEmpty)
precondition(panel.update(report:[3,128,132,0,0,0,0,0,0,0],active:true,config:custom) == [.init(key:12)])
print("Settings checks passed: migration, roundtrip, invalid imports, pressure, custom button/ring, ring speed")

var dragCheck = ThreeFingerDrag()
precondition(dragCheck.update(ids: [1], enabled: true) == .pass)
precondition(dragCheck.update(ids: [1,2,3], enabled: true) == .begin)
precondition(dragCheck.update(ids: [1,2,3], enabled: true) == .move)
precondition(dragCheck.update(ids: [1,2], enabled: true) == .end)
precondition(dragCheck.update(ids: [1], enabled: true) == .consume)
precondition(dragCheck.update(ids: [1,2,3], enabled: true) == .consume)
precondition(dragCheck.update(ids: [], enabled: true) == .consume)
precondition(dragCheck.update(ids: [1,2,3], enabled: true) == .begin)
precondition(dragCheck.update(ids: [1,2,4], enabled: true) == .end) // replaced contact cannot jump
_ = dragCheck.update(ids: [], enabled: true)
precondition(dragCheck.update(ids: [1,2,3], enabled: false) == .pass)
precondition(dragCheck.update(ids: [1,2,3], enabled: true) == .begin)
precondition(dragCheck.update(ids: [1,2,3], enabled: false) == .end)
_ = dragCheck.update(ids: [], enabled: true)
_ = dragCheck.update(ids: [1,2,3], enabled: true)
precondition(dragCheck.cancel())
precondition(!dragCheck.isDragging)
precondition(dragCheck.update(ids: [1,2,3], enabled: true) == .consume)
var cancelledByPen = false
let dragGate = PenTouchGate()
dragGate.cancelTouchDrag = { cancelledByPen = true }
dragGate.observe(reportID: 2, bytes: [2,0xa0,0,0,0,0,0,0,0,0], now: 1)
precondition(cancelledByPen)
print("Three-finger checks passed: drag, motion, staggered lift, contact replacement, disable, cancel, pen takeover")

var penConfig = WacomdConfig()
var pen = PenState()
func contact(_ tip: Bool = false, _ lower: Bool = false, _ upper: Bool = false, eraser: Bool = false) {
    pen.applyContact(tip:tip,lower:lower,upper:upper,eraserInRange:eraser,config:penConfig,shortcutsActive:false)
}
contact(false,true);precondition(pen.tipDown && !pen.barrelButton)
contact();precondition(!pen.tipDown)
contact(false,false,true);precondition(!pen.tipDown && pen.barrelButton)
contact(true,true);contact(true);precondition(pen.tipDown) // Releasing the side button must not release a touching tip.
contact(true,eraser:true);precondition(pen.eraser && pen.tipDown)
penConfig.eraserAction = .pen
contact(true,eraser:true);precondition(!pen.eraser && pen.tipDown)
penConfig.eraserAction = .disabled
contact(true,true,true,eraser:true);precondition(!pen.inRange && !pen.tipDown && !pen.barrelButton)
contact(true);precondition(pen.inRange && pen.tipDown && !pen.eraser)
penConfig.penActions = [.shortcut,.middleClick]
precondition(penConfig.penAction(at:0,shortcutsActive:false) == .disabled)
precondition(penConfig.penAction(at:0,shortcutsActive:true) == .shortcut)
contact(false,false,true);precondition(pen.middleButton)
let penRoundtrip = try JSONDecoder().decode(WacomdConfig.self,from:JSONEncoder().encode(penConfig))
precondition(penRoundtrip == penConfig)
print("Pen settings passed: lower-left, upper-right, hold/release, tip overlap, eraser modes, shortcut scope, persistence")
