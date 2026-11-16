import CoreGraphics

// Build the complete chord before posting so allocation failure cannot leave a modifier held.
func keyChordEvents(key: CGKeyCode, modifiers: CGEventFlags, held: CGEventFlags,
                    source: CGEventSource?) -> [CGEvent]? {
    let keys: [(CGEventFlags, CGKeyCode)] = [(.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55)]
    let added = keys.filter { modifiers.contains($0.0) && !held.contains($0.0) }
    var flags = held
    var events: [CGEvent] = []
    for (flag, code) in added {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) else { return nil }
        flags.insert(flag); event.type = .flagsChanged; event.flags = flags; events.append(event)
    }
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return nil }
        // Arrow keys carry Fn/numpad identity flags even without the physical Fn key.
        // Mission Control ignores synthetic Control-arrows missing those flags.
        event.flags = (123...126).contains(key) ? flags.union([.maskSecondaryFn, .maskNumericPad]) : flags
        events.append(event)
    }
    for (flag, code) in added.reversed() {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return nil }
        flags.remove(flag); event.type = .flagsChanged; event.flags = flags; events.append(event)
    }
    return events
}
