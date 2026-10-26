import SwiftUI

// No @State: it's a macro whose plugin ships only with Xcode, and this builds with Command Line Tools.
struct SettingsView: View {
    @Bindable private var store = Store.shared
    private let labels = keyLabels()

    var body: some View {
        VStack(spacing: 0) {
            KeyboardGrid { code in
                let target = store.config.keys[code]
                let label = labels[code] ?? "?"
                Button { store.selectedKey = code } label: {
                    KeyCap(code: code, cell: Cell(label: label, icon: target?.icon, link: target?.isWebLink == true), selected: store.selectedKey == code, lip: false)
                        .contentShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .help(target?.name ?? "Not assigned")
                .accessibilityLabel("\(label): \(target?.name ?? "not assigned")")
            }
            .padding(24)
            form
        }
        .frame(width: 805, height: 800)
    }

    private var form: some View {
        Form {
            Section("Assignment") {
                if let code = store.selectedKey {
                    KeyEditor(label: labels[code] ?? "?", target: $store.config.keys[code])
                } else {
                    Text("Click a key to assign an app, folder, URL or shell command.").foregroundStyle(.secondary)
                }
            }
            Section("Trigger") {
                LabeledContent("Modifiers") {
                    HStack(spacing: 4) {
                        ForEach(modifierSymbols, id: \.symbol) { Toggle($0.symbol, isOn: modifier($0.flag)).toggleStyle(.button) }
                    }
                }
                LabeledContent("Overlay delay") {
                    HStack {
                        Slider(value: $store.config.holdDelay, in: 0.1...1.5)
                        Text("\(Int(store.config.holdDelay * 1000)) ms").monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
            }
            Section("Overlay") {
                LabeledContent("Tilt") {
                    HStack {
                        Slider(value: $store.config.tilt, in: 0...45)
                        Text("\(Int(store.config.tilt))°").monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
            }
            Section("Feedback") {
                Toggle("Sound", isOn: $store.config.sound)
                Toggle("Haptic", isOn: $store.config.haptic)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $store.launchAtLogin)
                if !AXIsProcessTrusted() {
                    LabeledContent("Accessibility access needed") {
                        Button("Open Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func modifier(_ flag: CGEventFlags) -> Binding<Bool> {
        Binding(
            get: { store.config.combo.contains(flag) },
            set: { on in
                var combo = store.config.combo
                if on { combo.insert(flag) } else { combo.remove(flag) }
                if !combo.isEmpty { store.config.combo = combo } // zero modifiers would hijack every key
            })
    }
}

private struct KeyEditor: View {
    let label: String
    @Binding var target: Target?

    var body: some View {
        HStack {
            Text(label).font(.body.monospaced().weight(.semibold)).frame(width: 22)
            if let current = target {
                Image(nsImage: current.icon).resizable().frame(width: 20, height: 20)
                if current.kind == .app {
                    Text(current.name)
                } else {
                    TextField(
                        current.kind == .url ? "https://… or ~/Folder" : "Shell command",
                        text: Binding(get: { current.value }, set: { target?.value = $0 })
                    )
                    .labelsHidden()
                }
            } else {
                Text("Not assigned").foregroundStyle(.secondary)
            }
            Spacer()
            Menu("Assign") {
                Button("Choose App…") { choose(app: true) }
                Button("Choose Folder…") { choose(app: false) }
                Button("Open URL") { target = Target(kind: .url, value: "https://") }
                Button("Run Shell Command") { target = Target(kind: .shell, value: "") }
            }
            .fixedSize()
            if target != nil { Button("Clear") { target = nil } }
        }
    }

    private func choose(app: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = app
        panel.canChooseDirectories = !app
        if app {
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(filePath: "/Applications")
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !app {
            target = Target(kind: .url, value: url.path)
        } else if let id = Bundle(url: url)?.bundleIdentifier {
            target = Target(kind: .app, value: id)
        }
    }
}
