import Foundation
import IOKit.hid
import AppKit
import WacomdShared

/// Page HID *vendor-defined* utilisée par les Intuos Pro pour l'interface du
/// stylet. Tous les rapports pen (X/Y/pression/tilt) arrivent ici, en raw.
private let wacomDigitizerUsagePage = 0xff0d

/// Page HID vendor pour l'interface tactile (multi-touch surface).
/// Rapports Report ID 2 de longueur 64 quand des doigts sont en contact.
private let wacomTouchUsagePage = 0xff00

final class WacomDevice {
    private let device: IOHIDDevice
    let model: WacomModel
    private let injector: EventInjector
    private let touchTracker: TouchTracker
    private let penTouchGate: PenTouchGate
    private var state = PenState()
    private var panel = ResolvePanel()
    private var touchParser = IntuosProTouchParser()
    private var penSwitches = [false, false]
    private var eraserInRange = false
    private var config: WacomdConfig { ConfigStore.shared.current }
    private var shortcutsActive: Bool { !config.resolveOnly || resolveActive }
    private var resolveActive: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.blackmagic-design.DaVinciResolve"
    }
    private var reportBuffer = [UInt8](repeating: 0, count: 64)
    private let usagePage: Int
    private let usage: Int
    private let interfaceLabel: String
    private let isPenInterface: Bool
    private let isTouchInterface: Bool
    /// Dedup state for proximity-enter packets, which the firmware emits
    /// periodically even when no tool transition happens.
    private var lastSeenToolID: UInt32 = 0
    private var lastSeenSerial: UInt64 = 0

    var modelName: String { model.name }

    init(device: IOHIDDevice, model: WacomModel, penTouchGate: PenTouchGate) {
        self.device = device
        self.model = model
        self.penTouchGate = penTouchGate
        let injector = EventInjector()
        self.injector = injector
        self.touchTracker = TouchTracker(injector: injector, penTouchGate: penTouchGate)

        let pu  = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int) ?? 0
        let pup = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? 0
        self.usagePage = pup
        self.usage = pu
        self.interfaceLabel = String(format: "page=0x%02x usage=0x%02x", pup, pu)
        self.isPenInterface = (pup == wacomDigitizerUsagePage)
        self.isTouchInterface = (pup == wacomTouchUsagePage)
        if isTouchInterface {
            penTouchGate.cancelTouchDrag = { [weak self] in
                if ConfigStore.shared.current.palmRejection { self?.touchTracker.cancelGesture() }
            }
        }
    }

    func start() {
        let opaque = Unmanaged.passUnretained(self).toOpaque()

        IOHIDDeviceRegisterInputValueCallback(device, { ctx, _, _, value in
            guard let ctx = ctx else { return }
            let dev = Unmanaged<WacomDevice>.fromOpaque(ctx).takeUnretainedValue()
            dev.handle(value: value)
        }, opaque)

        reportBuffer.withUnsafeMutableBufferPointer { buf in
            IOHIDDeviceRegisterInputReportCallback(
                device,
                buf.baseAddress!,
                CFIndex(buf.count),
                // (context, result, sender, type, reportID, report, reportLength)
                { ctx, _, _, _, reportID, report, reportLength in
                    guard let ctx = ctx else { return }
                    let dev = Unmanaged<WacomDevice>.fromOpaque(ctx).takeUnretainedValue()
                    dev.handle(report: report, length: reportLength, id: reportID)
                },
                opaque
            )
        }

        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            let hex = String(format: "0x%08x", result)
            FileHandle.standardError.write(Data("[wacomd] IOHIDDeviceOpen a échoué (\(hex)) sur \(interfaceLabel)\n".utf8))
        } else {
            Verbose.log("Ouvert interface \(interfaceLabel) (penInterface=\(isPenInterface))")
            dumpElements()
            if isPenInterface {
                enableWacomVendorMode()
                updateRingLED()
            }
        }
    }

    /// Send the magic Feature Reports that switch the tablet from
    /// HID-mouse-fallback to Wacom-vendor mode (raw 10-byte pen reports +
    /// multi-touch reports on Report ID 13).
    ///
    /// Linux reference : `wacom_query_tablet_data` in `drivers/hid/wacom_wac.c`
    /// — for the Intuos5/Pro family this sends `Feature Report 0x02` with
    /// payload `[mode]` where mode = 2 enables full vendor mode.
    ///
    /// We try a few known incantations and log which one (if any) succeeds.
    private func enableWacomVendorMode() {
        // The single SetReport that empirically enables digitizer + touch
        // on the PTH-451. We deliberately don't probe other variants
        // because some of them (e.g. id=0x02 payload=[02 82], id=0x04
        // payload=[04 02]) make the device reply with kIOReturnNotPrivileged
        // and then stop emitting reports entirely for ~30 seconds.
        let payload: [UInt8] = [0x02, 0x02]
        let r = payload.withUnsafeBufferPointer { buf -> IOReturn in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0x02,
                                 buf.baseAddress!, buf.count)
        }
        let hex = String(format: "0x%08x", r)
        if r == kIOReturnSuccess {
            Verbose.log("✓ SetReport Feature id=0x02 payload=[02 02] (Wacom vendor mode)")
        } else {
            Verbose.log("  SetReport Feature id=0x02 payload=[02 02] → \(hex)")
        }
    }

    func cancelTouchGestures() { touchTracker.cancelGesture() }

    func stop() {
        cancelTouchGestures()
        if isPenInterface {
            penTouchGate.penRemoved(now: ProcessInfo.processInfo.systemUptime)
            state.inRange = false
            penSwitches = [false, false]
            injector.update(state: state, model: model)
        }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    private func updateRingLED() {
        // USB PTH-451 feature report 0x20, as documented by Linux wacom_led_control.
        let result = panel.ledReport.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0x20, $0.baseAddress!, $0.count)
        }
        print("[wacomd] Ring mode \(panel.mode + 1): \(ResolvePanel.modeNames[panel.mode]); LED result \(String(format: "0x%08x", result))")
    }

    private func dumpElements() {
        guard Verbose.enabled else { return }
        let elems = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] ?? []
        Verbose.log("  \(elems.count) éléments HID :")
        for e in elems {
            let p = IOHIDElementGetUsagePage(e)
            let u = IOHIDElementGetUsage(e)
            let k = IOHIDElementGetType(e)
            let lo = IOHIDElementGetLogicalMin(e), hi = IOHIDElementGetLogicalMax(e)
            Verbose.log(String(format: "    type=%d page=0x%04x usage=0x%04x range=%d..%d",
                               k.rawValue, p, u, lo, hi))
        }
    }

    // MARK: - Rapports HID bruts (Wacom vendor-defined)

    private func handle(report: UnsafeMutablePointer<UInt8>?, length: CFIndex, id: UInt32) {
        guard let report = report, length > 0 else { return }

        if Verbose.enabled {
            let bytes = (0..<min(Int(length), 24)).map { String(format: "%02x", report[$0]) }.joined(separator: " ")
            Verbose.log("rapport id=\(id) len=\(length) [\(interfaceLabel)] : \(bytes)\(length > 24 ? " …" : "")")
        }

        // The mouse-fallback interface (page 0x01) duplicates the pen data
        // as standard HID mouse — we ignore it to avoid double events.
        // Pen interface (0xff0d) and touch interface (0xff00) both pass.
        guard isPenInterface || isTouchInterface else { return }

        if isPenInterface {
            // The panel shares the pen interface; report 3 carries its controls.
            if id == 3 {
                let previousMode = panel.mode
                let actions = panel.update(report: Array(UnsafeBufferPointer(start: report, count: Int(length))), active: shortcutsActive, config: config)
                if panel.mode != previousMode { updateRingLED() }
                for action in actions {
                    injector.postKeyCombo(keyCode: action.key, modifiers: CGEventFlags(rawValue: action.modifiers))
                }
                return
            }
            handlePenReport(data: report, length: Int(length), id: id)
        } else if isTouchInterface {
            // Touch interface also uses Report ID 2 but with length 64.
            // Disambiguation is done inside the parser by inspecting the
            // status byte.
            if let contacts = touchParser.decode(data: report, length: Int(length)) {
                touchTracker.handleFrame(contacts: contacts)
            }
        }
    }

    private func handlePenReport(data: UnsafeMutablePointer<UInt8>, length: Int, id: UInt32) {
        penTouchGate.observe(reportID: id, bytes: Array(UnsafeBufferPointer(start: data, count: length)),
                            now: ProcessInfo.processInfo.systemUptime)
        switch IntuosProParser.decode(reportID: id, data: data, length: length) {
        case .ignored:
            return
        case .proximityLeave:
            state.inRange = false
            penSwitches = [false, false]
            state.tipDown = false
            state.barrelButton = false
            state.middleButton = false
            state.eraser = false
            eraserInRange = false
            injector.update(state: state, model: model)
        case .proximityEnter(let toolID, let serial):
            // Dedup : la PTH-451 émet périodiquement des paquets de
            // proximité même quand aucune transition n'a lieu. On
            // n'agit que si le couple (toolID, serial) a changé.
            let isNewTool = (toolID != lastSeenToolID) || (serial != lastSeenSerial)
            lastSeenToolID = toolID
            lastSeenSerial = serial

            // Linux `wacom_intuos_get_tool_type` : les outils gomme
            // ont le bit `0x008` du low byte mis, et leur low nibble
            // est `a` ou `b` (0x80a, 0x82a, 0x84a, 0x80c, 0x82b…).
            // Les outils stylet (tip) ont le low nibble à 2 ou 3
            // (0x802, 0x812, 0x822, 0x823…).
            let lowNibble = toolID & 0x00f
            let isEraser = (lowNibble == 0xa) || (lowNibble == 0xb) || (lowNibble == 0xc)

            state.inRange = true
            eraserInRange = isEraser
            state.eraser = isEraser && config.eraserAction == .erase
            injector.updateToolIdentity(toolID: toolID, serial: serial, isEraser: isEraser)

            if isNewTool {
                Verbose.log(String(format: "proximité ON, toolID=0x%05x serial=0x%llx (eraser=%@)",
                                   toolID, serial, isEraser ? "OUI" : "non"))
            }
        case .pen(let sample):
            state.x = Double(sample.x)
            state.y = Double(sample.y)
            state.pressure = config.pressure(Double(sample.pressure) / model.maxPressure)
            state.tiltX = Double(sample.tiltX)
            state.tiltY = Double(sample.tiltY)
            let switches = [sample.barrelButton1, sample.barrelButton2]
            state.applyContact(tip: sample.tipDown, lower: switches[0], upper: switches[1],
                               eraserInRange: eraserInRange, config: config, shortcutsActive: shortcutsActive)
            for index in 0..<2 {
                let action = config.penAction(at: index, shortcutsActive: shortcutsActive)
                if switches[index] && state.inRange {
                    let shortcut = config.penShortcuts[index]
                    if action == .shortcut && !penSwitches[index] && shortcut.enabled {
                        injector.postKeyCombo(keyCode: shortcut.key, modifiers: CGEventFlags(rawValue: shortcut.modifiers))
                    }
                }
            }
            penSwitches = switches
            injector.update(state: state, model: model)
        }
    }

    // MARK: - Évènements HID structurés (utilisés si Apple décode quelque chose)

    private func handle(value: IOHIDValue) {
        guard Verbose.enabled else { return }
        let element = IOHIDValueGetElement(value)
        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let raw = IOHIDValueGetIntegerValue(value)
        Verbose.log(String(format: "valeur page=0x%04x usage=0x%04x v=%d [\(interfaceLabel)]", page, usage, raw))
    }
}
