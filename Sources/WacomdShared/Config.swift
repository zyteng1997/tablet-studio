import Foundation

public struct TabletShortcut: Codable, Equatable {
    public var title: String
    public var key: UInt16
    public var modifiers: UInt64
    public var enabled: Bool
    public init(title: String = "Shortcut", key: UInt16, modifiers: UInt64 = 0, enabled: Bool = true) {
        self.title = title; self.key = key; self.modifiers = modifiers; self.enabled = enabled
    }
}
public enum FourFingerAction: String, Codable { case off, desktops, applications }

public enum EraserAction: String, Codable { case erase, pen, disabled }

public enum PenAction: String, Codable, CaseIterable {
    case leftClick, rightClick, middleClick, shortcut, disabled
}

/// User-tunable configuration for the touch surface behaviour.
/// Persisted to `~/Library/Application Support/wacomd/config.json` and
/// reloaded on SIGHUP so the user can iterate without restarting the daemon.
public struct WacomdConfig: Codable, Equatable {
    // ---- Touch enable toggles ---------------------------------------------
    /// Master switch — when false, the whole multi-touch surface is
    /// ignored regardless of the per-gesture toggles below.
    public var touchEnabled: Bool = true

    public var oneFingerCursor:   Bool = true
    public var twoFingerScroll:   Bool = true
    public var threeFingerSwipes: Bool = true
    public var tapToClick:        Bool = true
    public var twoFingerTapRightClick: Bool = true

    /// When true : finger moves down → page goes down (macOS "Natural
    /// scrolling" feel). When false : finger moves down → page goes up
    /// (Windows / pre-Lion macOS / classic mouse-wheel feel).
    public var naturalScroll: Bool = false

    // ---- Sensitivities (raw-tablet-units → screen-pixels) -----------------
    /// 1-finger cursor : 0.35 ≈ MacBook trackpad "Tracking speed 5/10"
    public var cursorSensitivity: Double = 0.35
    /// 2-finger scroll : 0.5 ≈ ~one page per full-tablet swipe
    public var scrollSensitivity: Double = 0.5
    /// 3-finger swipe trigger threshold, in raw units of centroid travel.
    public var threeFingerSwipeThreshold: Double = 200

    // ---- Tap recognition --------------------------------------------------
    /// Max contact duration to still be considered a "tap" (not a drag).
    /// Allow a relaxed tap while keeping long presses distinct.
    public var tapMaxDurationMs: Int = 250
    /// Max drift in raw tablet units during a contact for it to still be a tap.
    /// 25 ≈ 0.6 mm on a PTH-451 ; tighter than this and even real taps miss,
    /// looser and slow short cursor movements get hijacked as taps.
    public var tapMaxRawMovement: Double = 25

    public var fourFingerAction: FourFingerAction = .off
    public var threeFingerDrag: Bool = false
    public var palmRejection: Bool = true
    public var penPressureExponent: Double = 1
    public var resolveOnly: Bool = true
    public var ringStep: Int = 2
    public var penActions: [PenAction] = [.leftClick, .rightClick]
    public var eraserAction: EraserAction = .erase
    public var penShortcuts: [TabletShortcut] = [.init(title: "Undo", key: 6, modifiers: 1 << 20), .init(title: "Play / pause", key: 49)]
    public var tabletShortcuts: [TabletShortcut] = [
        .init(title: "Play / pause", key: 49), .init(title: "Undo", key: 6, modifiers: 1 << 20),
        .init(title: "Redo", key: 6, modifiers: (1 << 20) | (1 << 17)),
        .init(title: "Selection", key: 0), .init(title: "Blade", key: 11), .init(title: "Snapping", key: 1)
    ]
    // Each pair is counterclockwise, clockwise; centre always cycles the four modes.
    public var ringShortcuts: [TabletShortcut] = [
        .init(title: "Previous frame", key: 123), .init(title: "Next frame", key: 124),
        .init(title: "Zoom out", key: 27, modifiers: 1 << 20), .init(title: "Zoom in", key: 24, modifiers: 1 << 20),
        .init(title: "Previous clip", key: 126), .init(title: "Next clip", key: 125),
        .init(title: "Previous marker", key: 126, modifiers: 1 << 17), .init(title: "Next marker", key: 125, modifiers: 1 << 17)
    ]

    public func validate() throws {
        let shortcuts = tabletShortcuts + penShortcuts + ringShortcuts
        guard tabletShortcuts.count == 6, penShortcuts.count == 2, ringShortcuts.count == 8, penActions.count == 2,
              shortcuts.allSatisfy({ $0.key <= 127 && $0.title.count <= 80 && $0.modifiers & ~UInt64(0x1e0000) == 0 }),
              (0.05...1.5).contains(cursorSensitivity), (0.05...2).contains(scrollSensitivity),
              (50...500).contains(threeFingerSwipeThreshold), (50...300).contains(tapMaxDurationMs),
              (5...100).contains(tapMaxRawMovement), (0.25...3).contains(penPressureExponent), (1...12).contains(ringStep)
        else { throw NSError(domain: "WacomdConfig", code: 1, userInfo: [NSLocalizedDescriptionKey: "Settings contain an invalid shortcut or sensitivity value."]) }
    }
    public func penAction(at index: Int, shortcutsActive: Bool) -> PenAction {
        let action = penActions[index]
        return action == .shortcut && !shortcutsActive ? .disabled : action
    }

    public func pressure(_ raw: Double) -> Double { pow(min(1, max(0, raw)), penPressureExponent) }

    public init() {}

    /// Custom decoder so adding new fields doesn't reject existing config
    /// files — missing keys fall back to the default value of that field.
    private enum CodingKeys: String, CodingKey {
        case fourFingerAction, eraserAction
        case threeFingerDrag
        case palmRejection, penPressureExponent, resolveOnly, ringStep, penActions, penShortcuts, tabletShortcuts, ringShortcuts
        case touchEnabled
        case oneFingerCursor, twoFingerScroll, threeFingerSwipes, tapToClick, twoFingerTapRightClick
        case naturalScroll
        case cursorSensitivity, scrollSensitivity, threeFingerSwipeThreshold
        case tapMaxDurationMs, tapMaxRawMovement
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WacomdConfig()  // baseline of defaults
        self.eraserAction = try c.decodeIfPresent(EraserAction.self, forKey: .eraserAction) ?? d.eraserAction
        self.fourFingerAction = try c.decodeIfPresent(FourFingerAction.self, forKey: .fourFingerAction) ?? d.fourFingerAction
        self.threeFingerDrag = try c.decodeIfPresent(Bool.self, forKey: .threeFingerDrag) ?? d.threeFingerDrag
        self.palmRejection = try c.decodeIfPresent(Bool.self, forKey: .palmRejection) ?? d.palmRejection
        self.penPressureExponent = try c.decodeIfPresent(Double.self, forKey: .penPressureExponent) ?? d.penPressureExponent
        self.resolveOnly = try c.decodeIfPresent(Bool.self, forKey: .resolveOnly) ?? d.resolveOnly
        self.ringStep = try c.decodeIfPresent(Int.self, forKey: .ringStep) ?? d.ringStep
        self.penActions = try c.decodeIfPresent([PenAction].self, forKey: .penActions) ?? d.penActions
        self.penShortcuts = try c.decodeIfPresent([TabletShortcut].self, forKey: .penShortcuts) ?? d.penShortcuts
        self.tabletShortcuts = try c.decodeIfPresent([TabletShortcut].self, forKey: .tabletShortcuts) ?? d.tabletShortcuts
        self.ringShortcuts = try c.decodeIfPresent([TabletShortcut].self, forKey: .ringShortcuts) ?? d.ringShortcuts
        self.touchEnabled      = try c.decodeIfPresent(Bool.self,   forKey: .touchEnabled)      ?? d.touchEnabled
        self.oneFingerCursor   = try c.decodeIfPresent(Bool.self,   forKey: .oneFingerCursor)   ?? d.oneFingerCursor
        self.twoFingerScroll   = try c.decodeIfPresent(Bool.self,   forKey: .twoFingerScroll)   ?? d.twoFingerScroll
        self.threeFingerSwipes = try c.decodeIfPresent(Bool.self,   forKey: .threeFingerSwipes) ?? d.threeFingerSwipes
        self.tapToClick        = try c.decodeIfPresent(Bool.self,   forKey: .tapToClick)        ?? d.tapToClick
        self.twoFingerTapRightClick = try c.decodeIfPresent(Bool.self, forKey: .twoFingerTapRightClick) ?? d.twoFingerTapRightClick
        self.naturalScroll     = try c.decodeIfPresent(Bool.self,   forKey: .naturalScroll)     ?? d.naturalScroll
        self.cursorSensitivity = try c.decodeIfPresent(Double.self, forKey: .cursorSensitivity) ?? d.cursorSensitivity
        self.scrollSensitivity = try c.decodeIfPresent(Double.self, forKey: .scrollSensitivity) ?? d.scrollSensitivity
        self.threeFingerSwipeThreshold = try c.decodeIfPresent(Double.self, forKey: .threeFingerSwipeThreshold) ?? d.threeFingerSwipeThreshold
        self.tapMaxDurationMs  = try c.decodeIfPresent(Int.self,    forKey: .tapMaxDurationMs)  ?? d.tapMaxDurationMs
        self.tapMaxRawMovement = try c.decodeIfPresent(Double.self, forKey: .tapMaxRawMovement) ?? d.tapMaxRawMovement
        try validate()
    }

    // ---- Where the config lives ------------------------------------------
    public static var defaultPath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Application Support/wacomd")
            .appendingPathComponent("config.json")
    }
}

/// Thread-safe, hot-reloadable configuration store. Loads from disk on
/// init, exposes the current snapshot via `current`, and reloads on
/// `reload()` (called from a SIGHUP signal handler).
public final class ConfigStore {
    public static let shared = ConfigStore()

    private let queue = DispatchQueue(label: "wacomd.config")
    private var _current: WacomdConfig = WacomdConfig()
    public let path: URL = WacomdConfig.defaultPath

    public var current: WacomdConfig {
        queue.sync { _current }
    }

    private init() {
        loadFromDisk()
    }

    /// Re-read the config file. Safe to call from a signal handler context
    /// via DispatchSource.makeSignalSource (which dispatches on a queue).
    public func reload() {
        loadFromDisk()
        print("[wacomd] Config rechargée depuis \(path.path)")
        print("[wacomd]   cursor=\(_current.cursorSensitivity) scroll=\(_current.scrollSensitivity)")
        print("[wacomd]   1f=\(_current.oneFingerCursor) 2f=\(_current.twoFingerScroll) 3f=\(_current.threeFingerSwipes) tap=\(_current.tapToClick)")
    }

    /// Write a fresh config to disk. Returns false if the write failed.
    @discardableResult
    public func save(_ config: WacomdConfig) -> Bool {
        do {
            try writeToDisk(config)
            queue.sync { _current = config }
            return true
        } catch {
            FileHandle.standardError.write(Data(
                "[wacomd] Échec écriture config : \(error)\n".utf8))
            return false
        }
    }

    private func loadFromDisk() {
        queue.sync {
            do {
                let data = try Data(contentsOf: path)
                _current = try JSONDecoder().decode(WacomdConfig.self, from: data)
            } catch CocoaError.fileReadNoSuchFile {
                _current = WacomdConfig()
                try? writeToDisk(_current)
            } catch {
                FileHandle.standardError.write(Data(
                    "[wacomd] Config illisible (\(error)). Valeurs par défaut.\n".utf8))
                // Keep the last valid snapshot when a reload fails.
            }
        }
    }

    private func writeToDisk(_ config: WacomdConfig) throws {
        try config.validate()
        let dir = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: path, options: .atomic)
    }
}

// MARK: - Daemon control helpers (used by the configurator)

public enum DaemonControl {
    /// Find the PID of the running wacomd (if any). Returns nil if none.
    public static func runningPID() -> pid_t? {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-x", "-u", String(getuid()), "wacomd"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        // waitUntilExit pumps the UI run loop and can re-enter SwiftUI layout.
        let completed = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in completed.signal() }
        do {
            try task.run()
            completed.wait()
        } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let myPID = ProcessInfo.processInfo.processIdentifier
        for line in String(data: data, encoding: .utf8)?.split(separator: "\n") ?? [] {
            if let pid = pid_t(line.trimmingCharacters(in: .whitespaces)),
               pid != myPID {
                return pid
            }
        }
        return nil
    }

    /// Send SIGHUP to the running daemon to hot-reload its config.
    @discardableResult
    public static func sendReloadSignal() -> Bool {
        guard let pid = runningPID() else { return false }
        return kill(pid, SIGHUP) == 0
    }
}
