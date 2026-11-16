import Foundation

// Shared by the pen and touch HID interfaces, which receive separate callbacks.
final class PenTouchGate {
    private(set) var penInRange = false
    var cancelTouchDrag: (() -> Void)?
    private var blockedUntil: TimeInterval = 0
    private var needsTouchLift = false
    let releaseDelay: TimeInterval

    init(releaseDelay: TimeInterval = 0.25) {
        self.releaseDelay = max(0, releaseDelay)
    }

    func observe(reportID: UInt32, bytes: [UInt8], now: TimeInterval) {
        // USB status report 192 is an idle heartbeat, not pen proximity.
        guard reportID == 2, bytes.count == 10, bytes[0] == 2 else { return }
        let status = bytes[1]
        if status & 0xfe == 0x80 {
            if penInRange { penRemoved(now: now) }
        } else if status & 0xfe == 0x20 || status & 0xfc == 0xc0 || status & 0xb8 == 0xa0 {
            if !penInRange { cancelTouchDrag?() }
            penInRange = true
            needsTouchLift = true
        }
    }

    func penRemoved(now: TimeInterval) {
        penInRange = false
        blockedUntil = now + releaseDelay
        needsTouchLift = true
    }

    func shouldBlock(hasContacts: Bool, now: TimeInterval) -> Bool {
        if penInRange || now < blockedUntil {
            needsTouchLift = true
            return true
        }
        if needsTouchLift {
            if !hasContacts { needsTouchLift = false }
            return true
        }
        return false
    }
}
