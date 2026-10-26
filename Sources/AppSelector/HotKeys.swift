import AppKit

/// One session event tap. Combo + mapped key runs the target and swallows the key;
/// combo held alone past `holdDelay` fires `onHold`, releasing it fires `onRelease`.
@MainActor final class HotKeys {
    var onHold: @MainActor () -> Void = {}
    var onRelease: @MainActor () -> Void = {}
    var onKey: @MainActor (_ code: Int, _ down: Bool) -> Void = { _, _ in }
    private var tap: CFMachPort?
    private var armed = false
    private var pending: DispatchWorkItem?
    private var swallowed = Set<Int64>()
    private let click = NSSound(named: "Tink")

    func start() {
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else {
            // Retry until the user grants Accessibility in System Settings.
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                MainActor.assumeIsolated { self.install() }
            }
            return
        }
        install()
    }

    // ponytail: tap runs on the main run loop; move it to its own thread if main ever blocks.
    private func install() {
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue }
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, me in
                let hotKeys = Unmanaged<HotKeys>.fromOpaque(me!).takeUnretainedValue()
                let swallow = MainActor.assumeIsolated { hotKeys.handle(type, event) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    }

    /// Returns true to swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let config = Store.shared.config
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .flagsChanged:
            let held = comboMatches(event.flags, combo: config.combo)
            if held && !armed {
                armed = true
                let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.onHold() } }
                pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + config.holdDelay, execute: work)
            } else if !held && armed {
                armed = false
                pending?.cancel()
                onRelease()
            }
            return false
        case .keyDown:
            pending?.cancel() // any key while holding means "no overlay"
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            guard comboMatches(event.flags, combo: config.combo) else { return false }
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !isRepeat { onKey(Int(code), true) }
            guard let target = config.keys[Int(code)] else { return false }
            swallowed.insert(code)
            if !isRepeat {
                target.run() // overlay stays up until the modifiers are released
                if config.haptic { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
                if config.sound { click?.stop(); click?.play() }
            }
            return true
        case .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            onKey(Int(code), false)
            return swallowed.remove(code) != nil
        default:
            return false
        }
    }
}
