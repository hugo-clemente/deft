import AppKit
import Carbon.HIToolbox
import ServiceManagement

/// Mappable physical keys as ANSI keycodes: digit row, then the three letter rows.
let keyRows: [[Int]] = [
    [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0],
    [kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_R, kVK_ANSI_T, kVK_ANSI_Y, kVK_ANSI_U, kVK_ANSI_I, kVK_ANSI_O, kVK_ANSI_P],
    [kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_Semicolon],
    [kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_B, kVK_ANSI_N, kVK_ANSI_M, kVK_ANSI_Comma, kVK_ANSI_Period, kVK_ANSI_Slash],
]

let modifierSymbols: [(flag: CGEventFlags, symbol: String)] = [
    (.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘"),
]

/// Shift is ignored unless it's part of the combo, so a Hyper key (⌃⌥⌘⇧) also fires ⌃⌥⌘.
func comboMatches(_ flags: CGEventFlags, combo: CGEventFlags) -> Bool {
    var held = flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
    if !combo.contains(.maskShift) { held.remove(.maskShift) }
    return !combo.isEmpty && held == combo
}

func symbols(_ combo: CGEventFlags) -> String {
    modifierSymbols.filter { combo.contains($0.flag) }.map(\.symbol).joined()
}

struct Target: Codable, Hashable {
    enum Kind: String, Codable { case app, url, shell }
    var kind: Kind
    /// Bundle id, URL or path (`~` allowed), or shell command.
    var value: String

    var url: URL? {
        switch kind {
        case .app: NSWorkspace.shared.urlForApplication(withBundleIdentifier: value)
        case .url where value.hasPrefix("/") || value.hasPrefix("~"): URL(filePath: NSString(string: value).expandingTildeInPath)
        case .url: URL(string: value)
        case .shell: nil
        }
    }

    var isWebLink: Bool { kind == .url && url?.isFileURL == false }

    var name: String {
        guard kind == .app, let url else { return value }
        return FileManager.default.displayName(atPath: url.path)
    }

    /// Real Finder/Dock icon: the app's, the folder's, or the app that opens the URL.
    var icon: NSImage {
        let workspace = NSWorkspace.shared
        if kind != .shell, let url, let file = url.isFileURL ? url : workspace.urlForApplication(toOpen: url) {
            return workspace.icon(forFile: file.path)
        }
        return NSImage(systemSymbolName: kind == .shell ? "terminal" : "questionmark.app.dashed", accessibilityDescription: nil)!
    }

    @MainActor func run() {
        let workspace = NSWorkspace.shared
        switch kind {
        case .app:
            if let front = workspace.frontmostApplication, front.bundleIdentifier == value { front.hide(); return }
            guard let url else { return NSSound.beep() }
            // LaunchServices launches or focuses (reopening a window like a Dock click);
            // NSRunningApplication.activate() from a background app isn't honored since macOS 14.
            workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case .url:
            guard let url else { return NSSound.beep() }
            workspace.open(url)
        case .shell:
            let process = Process()
            process.executableURL = URL(filePath: "/bin/zsh")
            process.arguments = ["-lc", value] // login shell for the user's PATH
            try? process.run()
        }
    }
}

struct Config: Codable, Equatable {
    var modifiers = CGEventFlags([.maskControl, .maskAlternate, .maskCommand]).rawValue
    var holdDelay = 0.3
    var tilt = 25.0
    var sound = true
    var haptic = true
    var keys: [Int: Target] = [:]

    var combo: CGEventFlags {
        get { CGEventFlags(rawValue: modifiers) }
        set { modifiers = newValue.rawValue }
    }

    init() {}

    // Missing fields fall back to defaults so a config from an older version keeps its keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modifiers = try c.decodeIfPresent(UInt64.self, forKey: .modifiers) ?? modifiers
        holdDelay = try c.decodeIfPresent(Double.self, forKey: .holdDelay) ?? holdDelay
        tilt = try c.decodeIfPresent(Double.self, forKey: .tilt) ?? tilt
        sound = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? sound
        haptic = try c.decodeIfPresent(Bool.self, forKey: .haptic) ?? haptic
        keys = try c.decodeIfPresent([Int: Target].self, forKey: .keys) ?? keys
    }
}

@MainActor @Observable final class Store {
    static let shared = Store()
    private static let file = URL.applicationSupportDirectory.appending(path: "Deft/config.json")

    var config: Config { didSet { save() } }

    /// Key being edited in Settings; UI state, not persisted.
    var selectedKey: Int?

    var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet { _ = try? launchAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
    }

    private init() {
        guard let data = try? Data(contentsOf: Self.file) else { config = Config(); return }
        do {
            config = try JSONDecoder().decode(Config.self, from: data)
        } catch {
            // Keep the unreadable file aside instead of overwriting it on the next save.
            let backup = Self.file.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: Self.file, to: backup)
            config = Config()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(config).write(to: Self.file, options: .atomic)
    }
}
