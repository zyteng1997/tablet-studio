import Foundation
import WacomdShared

struct PenState {
    var x: Double = 0
    var y: Double = 0
    var pressure: Double = 0
    var tiltX: Double = 0
    var tiltY: Double = 0
    var inRange: Bool = false
    var tipDown: Bool = false
    var barrelButton: Bool = false
    var middleButton: Bool = false
    var eraser: Bool = false

    mutating func applyContact(tip: Bool, lower: Bool, upper: Bool, eraserInRange: Bool,
                               config: WacomdConfig, shortcutsActive: Bool) {
        inRange = !(eraserInRange && config.eraserAction == .disabled)
        eraser = eraserInRange && config.eraserAction == .erase
        let actions = [(lower, 0), (upper, 1)].filter { $0.0 && inRange }
            .map { config.penAction(at: $0.1, shortcutsActive: shortcutsActive) }
        tipDown = inRange && (tip || actions.contains(.leftClick))
        barrelButton = actions.contains(.rightClick)
        middleButton = actions.contains(.middleClick)
    }
}

enum ToolKind {
    case pen
    case eraser
}
