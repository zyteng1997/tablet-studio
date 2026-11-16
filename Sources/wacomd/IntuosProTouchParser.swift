import Foundation

struct TouchContact: Equatable {
    let slotID: Int
    let inContact: Bool
    let x: Int
    let y: Int
}

let maxTouchAxis = 4095

/// PTH-451 USB touch uses up to seven *messages*, not a complete finger snapshot.
/// Protocol reference: Linux wacom_wac.c, wacom_bpt3_touch / wacom_bpt3_touch_msg.
struct IntuosProTouchParser {
    static let interfaceUsagePage = 0xff00
    private var active: [Int: TouchContact] = [:]

    /// nil means no contact update. Status messages must not synthesize a lift.
    mutating func decode(data: UnsafeMutablePointer<UInt8>, length: Int) -> [TouchContact]? {
        guard length >= 2, data[0] == 2 else { return nil }
        let count = Int(data[1] & 7)
        guard count > 0, length >= 2 + count * 8 else { return nil }
        var changed = false
        for index in 0..<count {
            let offset = 2 + index * 8
            let id = Int(data[offset])
            guard (2...17).contains(id) else { continue }
            changed = true
            if data[offset + 1] & 0x80 == 0 {
                active.removeValue(forKey: id)
                continue
            }
            let xy = Int(data[offset + 4])
            let contact = TouchContact(slotID: id, inContact: true,
                x: (Int(data[offset + 2]) << 4) | (xy >> 4),
                y: (Int(data[offset + 3]) << 4) | (xy & 15))
            active[id] = contact
            Verbose.log("touch slot=\(id) x=\(contact.x) y=\(contact.y)")
        }
        return changed ? active.values.sorted { $0.slotID < $1.slotID } : nil
    }
}
