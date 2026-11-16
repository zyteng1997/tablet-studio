import CoreGraphics
// Inspect real Quartz events; do not post them or alter desktop input state.
let source = CGEventSource(stateID: .privateState)
let control = keyChordEvents(key:126,modifiers:.maskControl,held:[],source:source)!
precondition(control.map { $0.type } == [.flagsChanged,.keyDown,.keyUp,.flagsChanged])
let arrowFlags: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
precondition(control.map { $0.flags.rawValue } == [CGEventFlags.maskControl.rawValue,arrowFlags.rawValue,arrowFlags.rawValue,0])
for key: CGKeyCode in 123...126 {
    let events = keyChordEvents(key:key,modifiers:.maskControl,held:[],source:source)!
    precondition(events[1].flags == arrowFlags && events[2].flags == arrowFlags)
    precondition(events.last!.flags.isEmpty)
}
precondition(control.first!.getIntegerValueField(.keyboardEventKeycode) == 59)
precondition(control.last!.getIntegerValueField(.keyboardEventKeycode) == 59)
let shifted = keyChordEvents(key:6,modifiers:[.maskCommand,.maskShift],held:.maskShift,source:source)!
precondition(shifted.last!.flags == .maskShift) // Preserve a modifier the user is already holding.
let plain = keyChordEvents(key:49,modifiers:[],held:[],source:source)!
precondition(plain.map { $0.type } == [.keyDown,.keyUp])
print("Keyboard event checks passed: modifier press/release, physical modifier preservation, unmodified keys")
