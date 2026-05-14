//
//  SettingsView.swift
//  PromptTap
//
//  Created by Yuta Tokoro on 2026/05/06.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: PromptTapModel
    @EnvironmentObject private var settings: AppSettings

    @State private var showingClearConfirmation = false
    @State private var showingCustomHotkey = false
    @State private var draftCustomHotkey: CustomHotkey?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")")
                        .foregroundStyle(.secondary)
                }
            }

            Section("General") {
                Picker("Hotkey", selection: hotkeySelection) {
                    ForEach(HotkeyTrigger.allCases) { trigger in
                        Text(title(for: trigger))
                            .tag(trigger)
                    }
                }

                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }

            Section("Editor") {
                Toggle("Vim key bindings", isOn: $settings.usesVimKeyBindings)
                Toggle("Line wrapping", isOn: $settings.lineWrapping)
            }

            Section("Submit") {
                Toggle("Send Enter after Submit", isOn: $settings.sendEnterAfterSubmit)
            }

            Section("Storage") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button {
                            let path = settings.storagePath ?? model.defaultStorageDirectoryURL.path
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                        } label: {
                            Text(settings.storagePath ?? "Default (Application Support)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")

                        Spacer()

                        Button("Change...") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.canCreateDirectories = true
                            if panel.runModal() == .OK {
                                settings.storagePath = panel.url?.path
                            }
                        }

                        Button("Reset") {
                            settings.storagePath = nil
                        }
                        .disabled(settings.storagePath == nil)
                    }
                }
            }
            Section("History") {
                Stepper("History Limit: \(settings.historyLimit)", value: $settings.historyLimit, in: 10...1000, step: 10)

                Button("Clear History", role: .destructive) {
                    showingClearConfirmation = true
                }
                .confirmationDialog(
                    "Are you sure you want to clear your history?",
                    isPresented: $showingClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear All", role: .destructive) {
                        model.clearHistory()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This action cannot be undone.")
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
        .sheet(isPresented: $showingCustomHotkey) {
            CustomHotkeySheet(
                draftHotkey: $draftCustomHotkey,
                currentHotkey: settings.customHotkey,
                onCancel: {
                    draftCustomHotkey = nil
                    showingCustomHotkey = false
                },
                onSave: { hotkey in
                    settings.customHotkey = hotkey
                    settings.hotkey = .custom
                    draftCustomHotkey = nil
                    showingCustomHotkey = false
                }
            )
        }
    }

    private var hotkeySelection: Binding<HotkeyTrigger> {
        Binding {
            settings.hotkey
        } set: { trigger in
            if trigger == .custom {
                draftCustomHotkey = settings.customHotkey
                showingCustomHotkey = true
            } else {
                settings.hotkey = trigger
            }
        }
    }

    private func title(for trigger: HotkeyTrigger) -> String {
        if trigger == .custom {
            return "Custom (\(settings.customHotkey.title))"
        }
        return trigger.title
    }
}

private struct CustomHotkeySheet: View {
    @Binding var draftHotkey: CustomHotkey?

    let currentHotkey: CustomHotkey
    let onCancel: () -> Void
    let onSave: (CustomHotkey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Hotkey")
                .font(.headline)

            HotkeyCaptureField(hotkey: $draftHotkey)
                .frame(height: 34)

            HStack {
                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    onSave(draftHotkey ?? currentHotkey)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftHotkey == nil)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            draftHotkey = currentHotkey
        }
    }
}

private struct HotkeyCaptureField: NSViewRepresentable {
    @Binding var hotkey: CustomHotkey?

    func makeNSView(context: Context) -> CapturingHotkeyField {
        let view = CapturingHotkeyField()
        view.onCapture = { hotkey in
            self.hotkey = hotkey
        }
        return view
    }

    func updateNSView(_ nsView: CapturingHotkeyField, context: Context) {
        nsView.hotkey = hotkey
        nsView.onCapture = { hotkey in
            self.hotkey = hotkey
        }

        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class CapturingHotkeyField: NSView {
    var hotkey: CustomHotkey? {
        didSet {
            displayedModifiers = hotkey?.modifiers ?? []
            needsDisplay = true
        }
    }

    var onCapture: ((CustomHotkey) -> Void)?
    private var displayedModifiers: NSEvent.ModifierFlags = []

    override var acceptsFirstResponder: Bool {
        true
    }

    override var focusRingType: NSFocusRingType {
        get { .exterior }
        set {}
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard let captured = CustomHotkey.from(event: event) else {
            return
        }
        displayedModifiers = captured.modifiers
        onCapture?(captured)
    }

    override func flagsChanged(with event: NSEvent) {
        displayedModifiers = event.modifierFlags.intersection(CustomHotkey.supportedModifiers)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        let borderColor = window?.firstResponder === self ? NSColor.keyboardFocusIndicatorColor : NSColor.separatorColor
        let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        borderColor.setStroke()
        border.lineWidth = window?.firstResponder === self ? 2 : 1
        border.stroke()

        drawShortcutText()
    }

    private func drawShortcutText() {
        let font = NSFont.systemFont(ofSize: 18, weight: .regular)
        let text = NSMutableAttributedString()

        appendModifier("⌃", flag: .control, font: font, to: text)
        appendModifier("⌥", flag: .option, font: font, to: text)
        appendModifier("⇧", flag: .shift, font: font, to: text)
        appendModifier("⌘", flag: .command, font: font, to: text)

        let keyText = hotkey?.keyEquivalent ?? ""
        text.append(
            NSAttributedString(
                string: keyText.isEmpty ? " Press Shortcut" : " \(keyText)",
                attributes: [
                    .font: font,
                    .foregroundColor: keyText.isEmpty ? NSColor.placeholderTextColor : NSColor.labelColor
                ]
            )
        )

        let rect = NSRect(x: 8, y: (bounds.height - text.size().height) / 2, width: bounds.width - 16, height: text.size().height)
        text.draw(in: rect)
    }

    private func appendModifier(
        _ symbol: String,
        flag: NSEvent.ModifierFlags,
        font: NSFont,
        to text: NSMutableAttributedString
    ) {
        let isPressed = displayedModifiers.contains(flag)
        text.append(
            NSAttributedString(
                string: symbol,
                attributes: [
                    .font: font,
                    .foregroundColor: isPressed ? NSColor.labelColor : NSColor.placeholderTextColor.withAlphaComponent(0.35)
                ]
            )
        )
    }
}
