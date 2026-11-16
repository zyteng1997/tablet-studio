import SwiftUI
import AppKit
import WacomdShared

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(), item = NSMenuItem(), submenu = NSMenu()
        menu.addItem(item); item.submenu = submenu
        submenu.addItem(withTitle: "Quit Tablet Studio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.mainMenu = menu
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        win.title = "Tablet Studio · PTH-451"; win.contentView = NSHostingView(rootView: ConfigView())
        win.isReleasedWhenClosed = false; win.center(); win.makeKeyAndOrderFront(nil)
        window = win; app.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

final class ConfigModel: ObservableObject {
    @Published var config = ConfigStore.shared.current
    @Published var message = "Changes take effect when you click Apply."
    @Published var running = DaemonControl.runningPID() != nil
    func apply() {
        guard ConfigStore.shared.save(config) else { message = "Could not save settings. Check values and folder permissions."; return }
        running = DaemonControl.runningPID() != nil
        message = DaemonControl.sendReloadSignal() ? "Saved and sent to the driver." : "Saved. Start the driver in Setup to use these settings."
    }
    func transfer(importing: Bool) {
        do {
            if importing {
                let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
                guard panel.runModal() == .OK, let url = panel.url else { return }
                let data = try Data(contentsOf: url)
                guard data.count <= 100_000 else { throw NSError(domain: "Import", code: 1, userInfo: [NSLocalizedDescriptionKey: "Settings file is too large."]) }
                config = try JSONDecoder().decode(WacomdConfig.self, from: data)
                message = "Imported. Review the settings, then Apply."
            } else {
                let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "PTH-451-settings.json"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try config.validate()
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(config).write(to: url, options: .atomic); message = "Settings exported."
            }
        } catch { message = error.localizedDescription }
    }
    func service(start: Bool) {
        do {
            try DriverSetup.setRunning(start); running = DaemonControl.runningPID() != nil
            message = start ? "Driver started. Grant permissions if macOS asks, then test your pen." : "Driver stopped and login startup removed."
        } catch { message = error.localizedDescription }
    }
}

enum DriverSetup {
    static func run(_ arguments: [String], allowMissing: Bool = false) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/launchctl"); process.arguments = arguments
        let pipe = Pipe(); process.standardError = pipe
        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        try process.run(); completed.wait()
        let details = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if process.terminationStatus != 0 && !(allowMissing && (process.terminationStatus == 3 || process.terminationStatus == 113)) {
            throw NSError(domain: "DriverSetup", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "launchctl: \(details)"])
        }
    }
    static func setRunning(_ start: Bool) throws {
        let fm = FileManager.default, home = FileManager.default.homeDirectoryForCurrentUser
        let label = "com.local.wacomd.pth451", domain = "gui/\(getuid())"
        let agent = home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
        // Stop only our own service; leave unrelated tablet software untouched.
        try run(["bootout", "\(domain)/\(label)"], allowMissing: true)
        if !start {
            if fm.fileExists(atPath: agent.path) { try fm.removeItem(at: agent) }; return
        }
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("Wacom PTH-451 Driver.app"), fm.fileExists(atPath: source.path) else {
            throw NSError(domain: "DriverSetup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bundled driver missing. Reinstall Tablet Studio."])
        }
        let target = home.appendingPathComponent("Applications/Wacom PTH-451 Driver.app")
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = target.deletingLastPathComponent().appendingPathComponent("Wacom PTH-451 Driver.previous.app")
        if fm.fileExists(atPath: target.path) {
            if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
            try fm.moveItem(at: target, to: backup)
        }
        do { try fm.copyItem(at: source, to: target) }
        catch { if fm.fileExists(atPath: backup.path) { try fm.moveItem(at: backup, to: target) }; throw error }
        let log = home.appendingPathComponent("Library/Logs/WacomPTH451/driver.log")
        try fm.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
        let plist: [String: Any] = ["Label": label, "ProgramArguments": [target.appendingPathComponent("Contents/MacOS/wacomd").path], "RunAtLoad": true, "KeepAlive": ["SuccessfulExit": false], "ThrottleInterval": 10, "ProcessType": "Interactive", "StandardOutPath": log.path, "StandardErrorPath": log.path]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agent, options: .atomic)
        try run(["enable", "\(domain)/\(label)"]); try run(["bootstrap", domain, agent.path])
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: TabletShortcut
    func makeNSView(context: Context) -> RecordButton { let b = RecordButton(); b.bezelStyle = .rounded; b.target = b; b.action = #selector(RecordButton.beginRecording); return b }
    func updateNSView(_ view: RecordButton, context: Context) {
        view.value = shortcut; view.changed = { shortcut.key = $0.key; shortcut.modifiers = $0.modifiers }
        if !view.recording { view.title = RecordButton.label(shortcut) }
        view.setAccessibilityLabel("Record shortcut for \(shortcut.title)")
    }
}
final class RecordButton: NSButton {
    var value = TabletShortcut(key: 49)
    var changed: ((TabletShortcut) -> Void)?
    var recording = false
    override var acceptsFirstResponder: Bool { true }
    @objc func beginRecording() { recording = true; title = "Press keys… Esc cancels"; window?.makeFirstResponder(self) }
    override func mouseDown(with event: NSEvent) { beginRecording() }
    override func keyDown(with event: NSEvent) {
        guard recording else {
            if event.keyCode == 49 || event.keyCode == 36 { recording = true; title = "Press keys… Esc cancels" }
            else { super.keyDown(with: event) }; return
        }
        recording = false
        if event.keyCode != 53 { value.key = event.keyCode; value.modifiers = UInt64(event.modifierFlags.rawValue) & 0x1e0000; changed?(value) }
        title = Self.label(value)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { if recording { keyDown(with: event); return true }; return false }
    override func resignFirstResponder() -> Bool { recording = false; title = Self.label(value); return super.resignFirstResponder() }
    static func label(_ value: TabletShortcut) -> String {
        let keys: [UInt16: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",36:"Return",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",48:"Tab",49:"Space",50:"`",51:"Delete",53:"Esc",123:"←",124:"→",125:"↓",126:"↑"]
        return [(1 << 18,"⌃"),(1 << 19,"⌥"),(1 << 17,"⇧"),(1 << 20,"⌘")].filter { value.modifiers & UInt64($0.0) != 0 }.map { $0.1 }.joined() + (keys[value.key] ?? "Key \(value.key)")
    }
}

struct ConfigView: View {
    @StateObject private var model = ConfigModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "pencil.and.outline").font(.largeTitle).foregroundStyle(.blue)
                VStack(alignment: .leading) { Text("Tablet Studio").font(.title2.bold()); Text("Intuos Pro Small · PTH-451").foregroundStyle(.secondary) }
                Spacer()
                Text(model.running ? "● Driver running" : "Driver stopped").foregroundStyle(model.running ? .green : .secondary)
            }
            TabView {
                ScrollView { buttons.padding(20) }.tabItem { Label("Buttons", systemImage: "keyboard") }
                ScrollView { ring.padding(20) }.tabItem { Label("Touch Ring", systemImage: "circle.circle") }
                ScrollView { touch.padding(20) }.tabItem { Label("Pen & Touch", systemImage: "hand.draw") }
                ScrollView { setup.padding(20) }.tabItem { Label("Setup", systemImage: "gearshape") }
            }
            HStack { Text(model.message).font(.caption).foregroundStyle(.secondary); Spacer(); Button("Apply") { model.apply() }.buttonStyle(.borderedProminent) }
        }.padding(22).frame(minWidth: 760, minHeight: 620)
    }
    private var buttons: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Use keyboard shortcuts and ring only in DaVinci Resolve", isOn: $model.config.resolveOnly)
            Text("Tablet buttons · top to bottom").font(.headline)
            ForEach(0..<6) { i in shortcutRow("\(i + 1)", $model.config.tabletShortcuts[i]) }
            Divider(); Text("Pen side buttons").font(.headline)
            ForEach(0..<2) { i in
                HStack {
                    Text(i == 0 ? "Lower button" : "Upper button").frame(width: 120, alignment: .leading)
                    Picker("Action", selection: $model.config.penActions[i]) {
                        Text("Left click / drag").tag(PenAction.leftClick)
                        Text("Right click").tag(PenAction.rightClick); Text("Middle click / pan").tag(PenAction.middleClick)
                        Text("Keyboard shortcut").tag(PenAction.shortcut); Text("Disabled").tag(PenAction.disabled)
                    }.labelsHidden()
                }
                if model.config.penActions[i] == .shortcut { shortcutRow("", $model.config.penShortcuts[i]) }
            }
            Picker("Eraser end", selection: $model.config.eraserAction) {
                Text("Erase").tag(EraserAction.erase)
                Text("Use as pen").tag(EraserAction.pen)
                Text("Disabled").tag(EraserAction.disabled)
            }
            Text("Pen clicks and the eraser setting apply in all apps. Hold a left-click button to drag. Erasing requires an app that supports tablet erasers.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var ring: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Press the ring centre to cycle the four lights.").font(.headline)
            Text("Record the keys your editor uses for each direction. The application scope in Buttons also applies here.").foregroundStyle(.secondary)
            ForEach(0..<4) { i in
                GroupBox("Light \(i + 1)") { VStack {
                    shortcutRow("↶", $model.config.ringShortcuts[i * 2]); shortcutRow("↷", $model.config.ringShortcuts[i * 2 + 1])
                }.padding(6) }
            }
            Stepper("Ring distance per shortcut: \(model.config.ringStep) (higher = slower)", value: $model.config.ringStep, in: 1...12)
        }
    }
    private var touch: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Pen pressure").font(.headline)
            slider("Pressure response · soft ← → firm", $model.config.penPressureExponent, 0.25...3)
            Text("1.00 is linear. Pressure changes drawing strength in apps that support it. The pen maps directly to the primary display.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("Enable finger touch", isOn: $model.config.touchEnabled)
            Toggle("Block palm / finger touch while the pen is nearby", isOn: $model.config.palmRejection)
            Text("After lifting the pen, lift your palm too. Touch resumes after a short delay and a clear surface.").font(.caption).foregroundStyle(.secondary)
            Group {
                Toggle("One finger moves the cursor", isOn: $model.config.oneFingerCursor)
                Toggle("Two fingers scroll", isOn: $model.config.twoFingerScroll)
                Toggle("Fingers downward → scroll page down", isOn: $model.config.naturalScroll)
                Toggle("One-finger tap left-clicks", isOn: $model.config.tapToClick)
                Toggle("Two-finger tap right-clicks", isOn: $model.config.twoFingerTapRightClick)
                Picker("Three-finger action", selection: Binding(
                    get: { model.config.threeFingerDrag ? 2 : (model.config.threeFingerSwipes ? 1 : 0) },
                    set: { model.config.threeFingerDrag = $0 == 2; model.config.threeFingerSwipes = $0 == 1 }
                )) {
                    Text("Drag windows / items").tag(2)
                    Text("Desktops / Mission Control").tag(1)
                    Text("Off").tag(0)
                }
                Text("To move a window, point at its title bar, then slide three fingers. Lift a finger to drop; lift all fingers before starting again. These controls are managed here, not in macOS Trackpad settings.").font(.caption).foregroundStyle(.secondary)
                Picker("Four-finger left / right", selection: $model.config.fourFingerAction) {
                    Text("Switch desktops / full-screen apps").tag(FourFingerAction.desktops)
                    Text("Switch applications").tag(FourFingerAction.applications)
                    Text("Off").tag(FourFingerAction.off)
                }
                Text("Four fingers up: Mission Control. Down: app windows. Uses macOS’s Control-arrow shortcuts; custom keyboard shortcuts may need restoring in System Settings.").font(.caption).foregroundStyle(.secondary)
                slider("Finger cursor speed", $model.config.cursorSensitivity, 0.05...1.5)
                slider("Scroll speed", $model.config.scrollSensitivity, 0.05...2)
                slider("Swipe distance (three / four fingers)", $model.config.threeFingerSwipeThreshold, 50...500)
                slider("Tap movement tolerance", $model.config.tapMaxRawMovement, 5...100)
                Stepper("Maximum tap duration: \(model.config.tapMaxDurationMs) ms", value: $model.config.tapMaxDurationMs, in: 50...300, step: 10)
            }.disabled(!model.config.touchEnabled)
        }
    }
    private var setup: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Set up this Mac").font(.headline)
            Text("Connect your PTH-451 by USB. If another tablet driver controls it, stop that driver first. Start installs the bundled driver for your account and enables it at login.")
            HStack { Button("Install / Start Driver") { model.service(start: true) }; Button("Stop Driver & Login Startup") { model.service(start: false) } }
            Text("Allow Wacom PTH-451 Driver in Accessibility and Input Monitoring. macOS may require your password or Touch ID.")
            HStack {
                Button("Accessibility") { openPrivacy("Privacy_Accessibility") }; Button("Input Monitoring") { openPrivacy("Privacy_ListenEvent") }
                Button("Show driver log") { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/WacomPTH451/driver.log")) }
            }
            Divider(); Text("Move your Mac settings").font(.headline)
            HStack { Button("Export Settings…") { model.transfer(importing: false) }; Button("Import Settings…") { model.transfer(importing: true) } }
            Text("Windows PCs").font(.headline)
            Text("Use Wacom 6.4.10-3. In Wacom Tablet Properties, select Touch → Standard Gestures: set Three Fingers to Drag and enable Four Fingers → Swipe left/right to switch application. My Gestures provides additional assignments. Mac settings files cannot be imported into Wacom’s Windows driver.")
            Link("Wacom PTH-451 gesture settings guide", destination: URL(string: "https://101.wacom.com/UserHelpPDF_Legacy/PTH-451_en.pdf")!)
            Link("Get the compatible Windows driver", destination: URL(string: "https://cdn.wacom.com/u/productsupport/drivers/win/professional/WacomTablet_6.4.10-3.exe")!)
            Text("Community build based on wacomd (MIT). Locally signed; not Apple-notarized. Intel Macs and other computers require hardware testing.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func shortcutRow(_ label: String, _ shortcut: Binding<TabletShortcut>) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.headline).frame(width: 26)
            Toggle("Enabled", isOn: shortcut.enabled).labelsHidden().help("Enable this shortcut")
            TextField("Action name", text: shortcut.title).textFieldStyle(.roundedBorder)
            ShortcutRecorder(shortcut: shortcut).frame(width: 230, height: 28).disabled(!shortcut.wrappedValue.enabled)
        }
    }
    private func slider(_ name: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) { HStack { Text(name); Spacer(); Text(String(format: "%.2f", value.wrappedValue)).monospacedDigit() }; Slider(value: value, in: range) }
    }
    private func openPrivacy(_ pane: String) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!) }
}
