import Foundation

/// Consume the entire contact sequence after a drag, including staggered lifts.
struct ThreeFingerDrag {
    enum Action { case pass, begin, move, end, consume }
    private var fingers: Set<Int> = []
    private var waitingForLift = false
    var isDragging: Bool { !fingers.isEmpty }

    mutating func update(ids: Set<Int>, enabled: Bool, moved: Bool = true) -> Action {
        if isDragging {
            if enabled && ids == fingers { return .move }
            fingers.removeAll()
            waitingForLift = !ids.isEmpty
            return .end
        }
        if waitingForLift {
            waitingForLift = !ids.isEmpty
            return .consume
        }
        if enabled && ids.count == 3 {
            guard moved else { return .consume }
            fingers = ids
            return .begin
        }
        return .pass
    }

    mutating func cancel() -> Bool {
        let held = isDragging
        fingers.removeAll()
        waitingForLift = true
        return held
    }
}
