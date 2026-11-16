import Foundation
import WacomdShared

struct ResolveShortcut: Equatable {
    let key: UInt16
    var modifiers: UInt64 = 0
}

struct ResolvePanel {
    private(set) var mode = 0
    var ledReport: [UInt8] { [0x20, UInt8(mode) | 0x04, 0, 0, 0, 0, 0, 0, 0] }
    static let modeNames = ["Frame stepping", "Timeline zoom", "Previous/next clip", "Previous/next marker"]
    private var lastButtons: UInt8 = 0
    private var lastCentre = false
    private var lastRing: Int?
    private var ringTravel = 0

    // Matches the user's existing Resolve keyboard preset.
    static var buttons: [ResolveShortcut] { WacomdConfig().tabletShortcuts.map { .init(key: $0.key, modifiers: $0.modifiers) } }

    mutating func update(report: [UInt8], active: Bool, config: WacomdConfig = WacomdConfig()) -> [ResolveShortcut] {
        guard report.count == 10, report[0] == 3 else { return [] }
        let buttons = report[4] & 0x3f
        let centre = report[3] & 1 != 0
        let position = Int(report[2] & 0x7f)
        let ring: Int? = report[2] & 0x80 != 0 && position < 72 ? position : nil
        defer {
            lastButtons = buttons
            lastCentre = centre
            lastRing = active ? ring : nil
        }
        if centre && !lastCentre {
            mode = (mode + 1) % 4
            ringTravel = 0
            return []
        }
        // Switching apps with a control held must not trigger a shortcut.
        guard active else { ringTravel = 0; return [] }
        let pressed = buttons & ~lastButtons
        var result = config.tabletShortcuts.enumerated().compactMap { index, shortcut -> ResolveShortcut? in
            pressed & (1 << index) != 0 && shortcut.enabled ? .init(key: shortcut.key, modifiers: shortcut.modifiers) : nil
        }
        if let ring = ring, let previous = lastRing {
            let delta = (ring - previous + 108) % 72 - 36
            // ponytail: reject jumps over a quarter-turn; tune after physical testing.
            if abs(delta) <= 18 {
                ringTravel += delta
                while abs(ringTravel) >= config.ringStep {
                    let forward = ringTravel > 0
                    let shortcut = config.ringShortcuts[mode * 2 + (forward ? 1 : 0)]
                    if shortcut.enabled { result.append(.init(key: shortcut.key, modifiers: shortcut.modifiers)) }
                    ringTravel += forward ? -config.ringStep : config.ringStep
                }
            } else { ringTravel = 0 }
        } else { ringTravel = 0 }
        return result
    }
}

enum PenButtonLayout {
    static func mapped(first: Bool, second: Bool, resolve: Bool) -> (right: Bool, middle: Bool) {
        (first || (second && !resolve), second && resolve)
    }
}
