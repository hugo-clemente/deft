import AppKit
import Carbon.HIToolbox
import SwiftUI

struct Cell {
    var label = ""
    var icon: NSImage?
    var running = false
    var link = false
}

@MainActor @Observable final class OverlayModel {
    var cells: [Int: Cell] = [:]
    var pressed: Set<Int> = []
    var tilt = 25.0
    var combo = ""
}

/// Built once at launch; show() only refreshes the data and orders the panel front.
@MainActor final class Overlay {
    private let model = OverlayModel()
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var icons: [Target: NSImage] = [:]

    init() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        refresh()
        let host = NSHostingView(rootView: OverlayView(model: model))
        panel.setContentSize(host.fittingSize) // before contentView=, which resizes the view to the window
        panel.contentView = host
    }

    func show() {
        refresh()
        let mouse = NSEvent.mouseLocation
        guard let area = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.midY - panel.frame.height / 2))
        panel.orderFrontRegardless()
        if Store.shared.config.haptic { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    }

    func hide() {
        panel.orderOut(nil)
        model.pressed = []
    }

    func key(_ code: Int, down: Bool) {
        if down { model.pressed.insert(code) } else if model.pressed.contains(code) { model.pressed.remove(code) }
    }

    private func refresh() {
        let config = Store.shared.config
        let labels = keyLabels()
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        model.tilt = config.tilt
        model.combo = symbols(config.combo)
        model.cells = [:]
        for code in keyRows.joined() {
            let target = config.keys[code]
            model.cells[code] = Cell(
                label: labels[code] ?? "", icon: target.map(icon),
                running: target?.kind == .app && running.contains(target!.value), link: target?.isWebLink == true)
        }
    }

    private func icon(_ target: Target) -> NSImage {
        if let cached = icons[target] { return cached }
        let image = target.icon
        icons[target] = image
        return image
    }
}

private struct OverlayView: View {
    let model: OverlayModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 18) {
            KeyboardGrid {
                KeyCap(code: $0, cell: model.cells[$0] ?? Cell(), border: contrast == .increased ? 2.5 : 1.5, pressed: model.pressed.contains($0))
            }
            .rotation3DEffect(.degrees(model.tilt), axis: (x: 1, y: 0, z: 0), anchor: UnitPoint(x: 0.5, y: 0.6))
            Text(model.combo).font(.system(size: 13)).tracking(2.6).foregroundStyle(.secondary)
        }
        .padding(EdgeInsets(top: 24, leading: 48, bottom: 20, trailing: 48)) // sides: room for the near row's perspective growth
        .modifier(GlassBackground())
    }
}

private struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if #available(macOS 26, *) {
            // Clear glass shows whatever is behind it; the window-colour wash keeps .primary text readable
            // on any backdrop (dark text over dark windows in light mode, and vice versa).
            content.background(Color(nsColor: .windowBackgroundColor).opacity(0.8), in: shape).glassEffect(.clear, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

/// Mappable keys laid out like the physical keyboard (overlay and Settings).
struct KeyboardGrid<Key: View>: View {
    @ViewBuilder let key: (Int) -> Key

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(keyRows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 8) { ForEach(row, id: \.self, content: key) }
                    .padding(.leading, [0, 34, 51, 85][index]) // physical row stagger
            }
        }
    }
}

/// A MacBook-style keycap. The lip is a soft 2pt drop under the key (as in ui.aceternity.com's keyboard);
/// pressing sinks the cap by the lip's height.
struct KeyCap: View {
    let code: Int
    let cell: Cell
    var border: CGFloat = 1.5
    var selected = false
    var pressed = false
    var lip = true

    var body: some View {
        let mapped = cell.icon != nil
        let face = RoundedRectangle(cornerRadius: 6)
        let depth: CGFloat = 2
        face.strokeBorder(selected ? Color.accentColor : Color.primary.opacity(mapped ? 0.85 : 0.16), lineWidth: selected ? 3 : border)
            .background(face.fill(Color.primary.opacity(mapped ? 0.05 : 0)))
            .frame(width: 60, height: 60)
            .overlay(alignment: .topLeading) {
                Text(cell.label).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(mapped ? .primary : .secondary)
                    .padding(.top, 4).padding(.leading, 7)
            }
            .overlay {
                if let icon = cell.icon { Image(nsImage: icon).resizable().frame(width: 32, height: 32).offset(y: 3) }
            }
            .overlay(alignment: .bottom) {
                if cell.running { Circle().fill(.primary).frame(width: 4, height: 4).padding(.bottom, 6) } // above F/J bumps
            }
            .overlay(alignment: .bottom) {
                if code == kVK_ANSI_F || code == kVK_ANSI_J { // home-row bumps
                    Capsule().fill(Color.primary.opacity(0.6)).frame(width: 12, height: 2).padding(.bottom, 3)
                }
            }
            .overlay(alignment: .topTrailing) {
                if cell.link {
                    Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary).padding(6)
                }
            }
            // Pressing slides the cap down over its lip while the lip shrinks toward its own bottom edge:
            // the key sinks into the keyboard. The lip sits after .offset so it stays put.
            .offset(y: pressed ? depth : 0)
            .background {
                if lip {
                    face.offset(y: depth).subtracting(face).fill(Color.black.opacity(mapped ? 0.3 : 0.12)).blur(radius: 0.6)
                        .scaleEffect(x: 1, y: pressed ? 0.01 : 1, anchor: UnitPoint(x: 0.5, y: (60 + depth) / 60))
                }
            }
            .animation(.easeOut(duration: 0.1), value: pressed)
    }
}

/// Keycap label per mappable key in the current input source (same key: "A" on QWERTY, "Q" on AZERTY).
func keyLabels() -> [Int: String] {
    guard let layout = layoutData() else { return [:] }
    var labels: [Int: String] = [:]
    for code in keyRows.joined() {
        labels[code] = pickLabel(translate(layout, code, shift: false), translate(layout, code, shift: true))
    }
    return labels
}

/// AZERTY's digit row types &é"'( unshifted; show the digit printed on the keycap instead.
func pickLabel(_ plain: String, _ shifted: String) -> String {
    let shiftedIsDigit = shifted.count == 1 && shifted.first!.isNumber
    return shiftedIsDigit && plain.first?.isNumber != true ? shifted : plain.uppercased()
}

private func layoutData() -> Data? {
    for copySource in [TISCopyCurrentKeyboardLayoutInputSource, TISCopyCurrentASCIICapableKeyboardLayoutInputSource] {
        guard let source = copySource()?.takeRetainedValue(),
              let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { continue }
        return Unmanaged<CFData>.fromOpaque(data).takeUnretainedValue() as Data
    }
    return nil
}

private func translate(_ layout: Data, _ code: Int, shift: Bool) -> String {
    var deadKeys: UInt32 = 0
    var length = 0
    var chars = [UniChar](repeating: 0, count: 4)
    layout.withUnsafeBytes { bytes in
        _ = UCKeyTranslate(
            bytes.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self), UInt16(code), UInt16(kUCKeyActionDisplay),
            shift ? UInt32(shiftKey >> 8) : 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
            &deadKeys, chars.count, &length, &chars)
    }
    return String(utf16CodeUnits: chars, count: length)
}
