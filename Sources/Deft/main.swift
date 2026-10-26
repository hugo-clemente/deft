import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeys = HotKeys()
    private var statusItem: NSStatusItem?
    private var settings: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let overlay = Overlay()
        hotKeys.onHold = overlay.show
        hotKeys.onRelease = overlay.hide
        hotKeys.onKey = overlay.key
        hotKeys.start()

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Deft", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Deft")
        statusItem?.menu = menu

        if Store.shared.config.keys.isEmpty { openSettings() }
    }

    /// Relaunching the app (Finder, Spotlight, `open`) shows Settings, like most menu bar apps.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettings()
        return false
    }

    @objc private func openSettings() {
        showSettings()
        // NSApp.activate() is only a request since macOS 14 and often loses to the frontmost app, leaving
        // Settings behind it. Activating ourselves through LaunchServices is reliable; it also fires reopen.
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: NSWorkspace.OpenConfiguration())
    }

    private func showSettings() {
        if settings == nil {
            settings = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            settings?.title = "Deft Settings"
            settings?.isReleasedWhenClosed = false
            settings?.center()
        }
        settings?.makeKeyAndOrderFront(nil)
        settings?.orderFrontRegardless()
    }
}

if CommandLine.arguments.contains("--self-test") { selfTest(); exit(0) }

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.accessory)
// `-appearance NSAppearanceNameDarkAqua` previews the other theme without touching the system setting.
if let name = UserDefaults.standard.string(forKey: "appearance") { NSApplication.shared.appearance = NSAppearance(named: .init(name)) }
NSApplication.shared.run()
