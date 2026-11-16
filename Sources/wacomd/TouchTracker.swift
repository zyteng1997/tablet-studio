import Foundation
import AppKit
import WacomdShared

/// Per-finger state we maintain across HID frames. Positions are kept in
/// raw tablet units (0..maxTouchAxis) because the multi-touch surface
/// drives the cursor in RELATIVE / trackpad mode, not as an absolute
/// digitizer like the pen.
private struct ActiveTouch {
    let slotID: Int
    let startTime: CFAbsoluteTime
    let startRaw: (x: Int, y: Int)
    var lastRaw: (x: Int, y: Int)
    /// Exponentially-smoothed raw position used to derive cursor deltas.
    /// Damps sensor jitter that would otherwise pollute the cursor with
    /// ±1-unit noise even on a stationary finger.
    var smoothedRaw: (x: Double, y: Double)
    var maxDistanceFromStart: Double   // in raw tablet units
    /// Last frame timestamp — used to detect "frame gaps" that probably
    /// hide a lift-then-touch sequence which we don't want to interpret
    /// as continuous motion.
    var lastSeenTime: CFAbsoluteTime
}

/// Relative touch input with position smoothing, configurable sensitivity,
/// fractional-pixel accumulation, and separate gesture modes.
final class TouchTracker {
    private let injector: EventInjector
    private let penTouchGate: PenTouchGate
    private var touches: [Int: ActiveTouch] = [:]

    // 2-finger scroll state ---------------------------------------------------
    private var scrollSmoothedCentroid: (x: Double, y: Double)?
    private var scrollAccumDx: Double = 0
    private var scrollAccumDy: Double = 0

    // 1-finger cursor state ---------------------------------------------------
    private var cursorAccumDx: Double = 0
    private var cursorAccumDy: Double = 0

    // 3-finger gesture state machine -----------------------------------------
    private var threeFingerStart: (x: Double, y: Double, time: CFAbsoluteTime)?
    private var threeFingerSwipeFired: Bool = false
    private var drag = ThreeFingerDrag()
    private var fourFingerSequence = false
    private var fourFingerFired = false
    private var tapStartedAt: CFAbsoluteTime?
    private var tapPeakCount = 0
    private var tapEligible = false

    // Config snapshot --------------------------------------------------------
    private let configuration: () -> WacomdConfig
    private var config: WacomdConfig { configuration() }
    private var tapMaxDuration: CFAbsoluteTime { CFAbsoluteTime(config.tapMaxDurationMs) / 1000 }
    private var tapMaxRawMovement: Double { config.tapMaxRawMovement }
    private var threeFingerSwipeThreshold: Double { config.threeFingerSwipeThreshold }
    private var cursorSensitivity: Double { config.cursorSensitivity }
    private var scrollSensitivity: Double { config.scrollSensitivity }

    // Smoothing constants ----------------------------------------------------
    /// Position-smoothing factor. 0.45 lerps roughly halfway each frame ;
    /// the response stays snappy enough to feel native but small noise
    /// gets averaged out across 3-4 frames.
    private let positionSmoothingAlpha: Double = 0.45
    /// Cursor deadband, in raw tablet units. The smoothed delta must
    /// exceed this on at least one axis for any cursor event to fire.
    private let cursorDeadbandRaw: Double = 0.5
    /// Scroll deadband, in raw tablet units of centroid travel.
    private let scrollDeadbandRaw: Double = 2.0
    /// Maximum scroll delta per single CGEvent (post a series of small
    /// events instead of one huge jump for very fast swipes).
    private let scrollMaxPerEvent: Double = 80

    init(injector: EventInjector, penTouchGate: PenTouchGate, configuration: @escaping () -> WacomdConfig = { ConfigStore.shared.current }) {
        self.configuration = configuration
        self.injector = injector
        self.penTouchGate = penTouchGate
    }

    // MARK: - Frame handler

    func handleFrame(contacts: [TouchContact]) {
        // Master switch — when touch is disabled in the config we drop the
        // frame entirely AND flush all per-touch state so that re-enabling
        // it later doesn't replay a stale gesture.
        if !config.touchEnabled || (config.palmRejection && penTouchGate.shouldBlock(
            hasContacts: contacts.contains { $0.inContact }, now: ProcessInfo.processInfo.systemUptime
        )) {
            cancelGesture()
            if !contacts.contains(where: { $0.inContact }) { _ = drag.update(ids: [], enabled: false) }
            return
        }

        let now = CFAbsoluteTimeGetCurrent()

        let activeIDs = Set(contacts.filter { $0.inContact }.map { $0.slotID })
        if activeIDs.count >= 4 { fourFingerSequence = true }
        let previousIDs = Set(touches.keys)
        let appearedIDs = activeIDs.subtracting(previousIDs)
        let releasedIDs = previousIDs.subtracting(activeIDs)

        if previousIDs.isEmpty && !activeIDs.isEmpty {
            tapStartedAt = now; tapPeakCount = 0; tapEligible = true
        }
        tapPeakCount = max(tapPeakCount, activeIDs.count)
        if tapPeakCount > 2 || (!appearedIDs.isEmpty && !releasedIDs.isEmpty) { tapEligible = false }

        // ---- 1. Register newly-arrived contacts ----------------------------
        for id in appearedIDs {
            guard let c = contacts.first(where: { $0.slotID == id && $0.inContact }) else { continue }
            touches[id] = ActiveTouch(
                slotID: id,
                startTime: now,
                startRaw: (c.x, c.y),
                lastRaw: (c.x, c.y),
                smoothedRaw: (Double(c.x), Double(c.y)),
                maxDistanceFromStart: 0,
                lastSeenTime: now
            )
        }

        // ---- 2. Update smoothed position + per-finger delta on smoothed ----
        var smoothedDeltas: [Int: (dx: Double, dy: Double)] = [:]
        for c in contacts where c.inContact {
            guard var touch = touches[c.slotID] else { continue }
            let prevSmooth = touch.smoothedRaw
            let newSmooth = (
                x: prevSmooth.x + (Double(c.x) - prevSmooth.x) * positionSmoothingAlpha,
                y: prevSmooth.y + (Double(c.y) - prevSmooth.y) * positionSmoothingAlpha
            )
            smoothedDeltas[c.slotID] = (newSmooth.x - prevSmooth.x, newSmooth.y - prevSmooth.y)
            touch.smoothedRaw = newSmooth
            touch.lastRaw = (c.x, c.y)
            let dxTotal = Double(c.x - touch.startRaw.x)
            let dyTotal = Double(c.y - touch.startRaw.y)
            touch.maxDistanceFromStart = max(touch.maxDistanceFromStart,
                                              (dxTotal * dxTotal + dyTotal * dyTotal).squareRoot())
            touch.lastSeenTime = now
            touches[c.slotID] = touch
        }

        let moved = appearedIDs.isEmpty && activeIDs.count == 3 && (
            abs(smoothedDeltas.values.reduce(0) { $0 + $1.dx } / 3) >= cursorDeadbandRaw ||
            abs(smoothedDeltas.values.reduce(0) { $0 + $1.dy } / 3) >= cursorDeadbandRaw)
        let dragAction = drag.update(ids: activeIDs, enabled: config.threeFingerDrag && !fourFingerSequence, moved: moved)
        let consumesDrag = dragAction != .pass
        let suppressTap = consumesDrag || fourFingerSequence

        // Decide taps only after the whole contact sequence ends; staggered two-finger
        // lifts must produce one right-click, never a trailing one-finger left-click.
        if suppressTap || touches.values.contains(where: { $0.maxDistanceFromStart > tapMaxRawMovement }) {
            tapEligible = false
        }
        for id in releasedIDs { touches.removeValue(forKey: id) }
        if activeIDs.isEmpty, let started = tapStartedAt {
            if tapEligible && now - started <= tapMaxDuration {
                if tapPeakCount == 1 && config.tapToClick { injector.tapClick() }
                if tapPeakCount == 2 && config.twoFingerTapRightClick { injector.tapClick(button: .right) }
            }
            tapStartedAt = nil; tapEligible = false
        }

        // 3-finger tap → middle click
        if !suppressTap && !config.threeFingerDrag && config.threeFingerSwipes
           && previousIDs.count == 3 && touches.isEmpty
           && !threeFingerSwipeFired
           && threeFingerStart != nil
           && (now - threeFingerStart!.time) <= tapMaxDuration {
            Verbose.log("3-finger tap → middle click")
            injector.middleClick()
        }

        // ---- 4. Mode-switching reset (kills leftover accumulators) ---------
        // Whenever the finger count changes we throw away pending fractional
        // pixels so a 1→2→1 sequence doesn't leak cursor or scroll motion
        // across modes.
        if appearedIDs.isEmpty == false || releasedIDs.isEmpty == false {
            cursorAccumDx = 0
            cursorAccumDy = 0
            scrollAccumDx = 0
            scrollAccumDy = 0
            scrollSmoothedCentroid = nil
            threeFingerStart = nil
            threeFingerSwipeFired = false
        }
        if touches.count != 3 && touches.count != 4 {
            threeFingerStart = nil
            threeFingerSwipeFired = false
        }

        switch dragAction {
        case .begin:
            if !injector.setTouchDragging(true) { _ = drag.cancel() }
        case .move:
            let deltas = activeIDs.compactMap { smoothedDeltas[$0] }
            if deltas.count == 3 {
                applySmoothedCursorDelta(dx: deltas.reduce(0) { $0 + $1.dx } / 3,
                                         dy: deltas.reduce(0) { $0 + $1.dy } / 3)
            }
        case .end:
            _ = injector.setTouchDragging(false)
        case .pass, .consume: break
        }
        if touches.isEmpty { fourFingerSequence = false; fourFingerFired = false }
        // The fourth finger can land after a drag has begun. Release the drag,
        // then allow the four-finger gesture without waiting for another lift.
        if consumesDrag && activeIDs.count != 4 { return }
        // A four-finger lift must not turn into a three-finger drag or one-finger tap.
        if fourFingerSequence && touches.count != 4 { return }

        // ---- 5. Continuous behaviour --------------------------------------
        switch touches.count {
        case 0:
            // idle
            break
        case 1:
            if config.oneFingerCursor, let smoothed = smoothedDeltas.values.first {
                applySmoothedCursorDelta(dx: smoothed.dx, dy: smoothed.dy)
            }
        case 2:
            if config.twoFingerScroll && !(config.twoFingerTapRightClick && tapEligible && now - (tapStartedAt ?? now) <= tapMaxDuration) {
                handleTwoFingerScroll()
            }
        case 3:
            if !config.threeFingerDrag && config.threeFingerSwipes {
                handleThreeFingerSwipe(now: now, count: 3)
            }
        case 4:
            if config.fourFingerAction != .off && !fourFingerFired {
                handleThreeFingerSwipe(now: now, count: 4)
            }
        default:
            // 5+ fingers : palm / ambiguous — ignore.
            break
        }
    }

    func cancelGesture() {
        _ = drag.cancel()
        _ = injector.setTouchDragging(false)
        touches.removeAll()
        scrollSmoothedCentroid = nil
        cursorAccumDx = 0; cursorAccumDy = 0
        scrollAccumDx = 0; scrollAccumDy = 0
        threeFingerStart = nil; threeFingerSwipeFired = false
        fourFingerSequence = false; fourFingerFired = false
        tapStartedAt = nil; tapEligible = false; tapPeakCount = 0
    }

    // MARK: - 1-finger cursor (relative, smoothed)

    /// Convert a smoothed-position delta into a screen-space cursor move,
    /// applying the configured sensitivity and sub-pixel
    /// accumulation.
    private func applySmoothedCursorDelta(dx: Double, dy: Double) {
        // Hard deadband on the smoothed delta — kills any drift while the
        // finger is "stationary" (sensor noise that survived smoothing).
        if abs(dx) < cursorDeadbandRaw && abs(dy) < cursorDeadbandRaw { return }

        // Use the configured speed directly; per-report acceleration amplified sensor jitter.
        cursorAccumDx += dx * cursorSensitivity
        cursorAccumDy += dy * cursorSensitivity

        let outDx = cursorAccumDx.rounded(.toNearestOrEven)
        let outDy = cursorAccumDy.rounded(.toNearestOrEven)
        if outDx == 0 && outDy == 0 { return }
        cursorAccumDx -= outDx
        cursorAccumDy -= outDy

        injector.moveCursorBy(dx: outDx, dy: outDy)
    }

    // MARK: - 2-finger scroll (smoothed centroid + sub-pixel accumulator)

    private func handleTwoFingerScroll() {
        let fingers = Array(touches.values)
        guard fingers.count == 2 else { return }

        let cx = (fingers[0].smoothedRaw.x + fingers[1].smoothedRaw.x) / 2
        let cy = (fingers[0].smoothedRaw.y + fingers[1].smoothedRaw.y) / 2
        let centroid = (x: cx, y: cy)
        defer { scrollSmoothedCentroid = centroid }

        guard let prev = scrollSmoothedCentroid else { return }
        let dx = centroid.x - prev.x
        let dy = centroid.y - prev.y
        if abs(dx) < scrollDeadbandRaw && abs(dy) < scrollDeadbandRaw { return }

        // Sign convention :
        //   natural   : finger ↓  → page ↓  (scrollAccumDy negative when dy>0)
        //   classic   : finger ↓  → page ↑  (scrollAccumDy positive when dy>0)
        let sign: Double = config.naturalScroll ? -1.0 : 1.0
        scrollAccumDx += sign * dx * scrollSensitivity
        scrollAccumDy += sign * dy * scrollSensitivity

        let outDx = clamp(scrollAccumDx, -scrollMaxPerEvent, scrollMaxPerEvent)
                        .rounded(.toNearestOrEven)
        let outDy = clamp(scrollAccumDy, -scrollMaxPerEvent, scrollMaxPerEvent)
                        .rounded(.toNearestOrEven)
        if outDx == 0 && outDy == 0 { return }
        scrollAccumDx -= outDx
        scrollAccumDy -= outDy

        injector.scroll(dx: outDx, dy: outDy)
    }

    // MARK: - 3-finger swipe (centroid trajectory → key combo)

    private func handleThreeFingerSwipe(now: CFAbsoluteTime, count: Int) {
        let fingers = Array(touches.values)
        guard fingers.count == count else { return }

        let cx = fingers.map { $0.smoothedRaw.x }.reduce(0, +) / Double(count)
        let cy = fingers.map { $0.smoothedRaw.y }.reduce(0, +) / Double(count)

        if threeFingerStart == nil {
            threeFingerStart = (x: cx, y: cy, time: now)
            threeFingerSwipeFired = false
            return
        }
        if threeFingerSwipeFired { return }

        let dx = cx - threeFingerStart!.x
        let dy = cy - threeFingerStart!.y
        let absDx = abs(dx)
        let absDy = abs(dy)
        if max(absDx, absDy) < threeFingerSwipeThreshold { return }

        threeFingerSwipeFired = true
        if count == 4 { fourFingerFired = true }

        if count == 4 && absDx > absDy && config.fourFingerAction == .applications {
            injector.postKeyCombo(keyCode: 48, modifiers: dx > 0 ? .maskCommand : [.maskCommand, .maskShift])
            return
        }
        if absDx > absDy {
            if dx > 0 {
                Verbose.log("\(count)-finger swipe → (Ctrl+→)")
                injector.postKeyCombo(keyCode: 0x7C, modifiers: .maskControl)
            } else {
                Verbose.log("\(count)-finger swipe ← (Ctrl+←)")
                injector.postKeyCombo(keyCode: 0x7B, modifiers: .maskControl)
            }
        } else {
            if dy < 0 {
                Verbose.log("\(count)-finger swipe ↑ (Mission Control)")
                injector.postKeyCombo(keyCode: 0x7E, modifiers: .maskControl)
            } else {
                Verbose.log("\(count)-finger swipe ↓ (App Exposé)")
                injector.postKeyCombo(keyCode: 0x7D, modifiers: .maskControl)
            }
        }
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }
}
