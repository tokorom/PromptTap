//
//  KeyboardShortcutsSettingsView.swift
//  PromptTap
//
//  Created by Gemini on 2026/05/15.
//

import SwiftUI

struct KeyboardShortcutsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    @State private var draftShortcuts = KeyboardShortcutAction.defaultShortcuts
    @State private var editingAction: KeyboardShortcutAction?
    @State private var draftEditingHotkey: CustomHotkey?

    var body: some View {
        Form {
            Section("Keyboard Shortcuts") {
                ForEach(KeyboardShortcutAction.allCases) { action in
                    Button {
                        draftEditingHotkey = shortcut(for: action)
                        editingAction = action
                    } label: {
                        HStack {
                            Text(action.title)
                            Spacer()
                            Text(shortcut(for: action).title)
                                .foregroundStyle(hasChange(for: action) ? Color.accentColor : Color.secondary)
                        }
                        .padding(10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
        .background(
            WindowCloseHandler {
                hasChanges
            } onCancel: {
                draftShortcuts = settings.keyboardShortcuts
                editingAction = nil
                draftEditingHotkey = nil
            }
        )
        .navigationTitle("Keyboard Shortcuts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    settings.keyboardShortcuts = draftShortcuts
                    dismiss()
                }
                .foregroundStyle(Color.accentColor)
                .disabled(!hasChanges)
            }
        }
        .onAppear {
            draftShortcuts = settings.keyboardShortcuts
        }
        .sheet(item: $editingAction) { action in
            CustomHotkeySheet(
                title: action.title,
                buttonCaption: "Set",
                candidateHotkey: $draftEditingHotkey,
                currentHotkey: shortcut(for: action),
                onCancel: {
                    draftEditingHotkey = nil
                    editingAction = nil
                },
                onSave: { hotkey in
                    draftShortcuts[action] = hotkey
                    draftEditingHotkey = nil
                    editingAction = nil
                }
            )
        }
    }

    private var hasChanges: Bool {
        draftShortcuts != settings.keyboardShortcuts
    }

    private func shortcut(for action: KeyboardShortcutAction) -> CustomHotkey {
        draftShortcuts[action] ?? action.defaultHotkey
    }

    private func hasChange(for action: KeyboardShortcutAction) -> Bool {
        shortcut(for: action) != settings.keyboardShortcuts[action]
    }
}

extension KeyboardShortcutsSettingsView {
    struct WindowCloseHandler: NSViewRepresentable {
        let hasChanges: () -> Bool
        let onCancel: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(hasChanges: hasChanges, onCancel: onCancel)
        }

        func makeNSView(context: Context) -> NSView {
            let view = NSView()

            DispatchQueue.main.async {
                if let window = view.window {
                    context.coordinator.window = window
                    window.delegate = context.coordinator
                }
            }

            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            DispatchQueue.main.async {
                if let window = nsView.window {
                    context.coordinator.window = window
                    window.delegate = context.coordinator
                }
            }
        }

        final class Coordinator: NSObject, NSWindowDelegate {
            let hasChanges: () -> Bool
            let onCancel: () -> Void

            weak var window: NSWindow?
            var shouldReallyClose = false

            init(hasChanges: @escaping () -> Bool, onCancel: @escaping () -> Void) {
                self.hasChanges = hasChanges
                self.onCancel = onCancel
            }

            func windowShouldClose(_ sender: NSWindow) -> Bool {
                if shouldReallyClose {
                    shouldReallyClose = false
                    if hasChanges() {
                        onCancel()
                    }
                    return true
                }

                if !hasChanges() {
                    return true
                }

                let alert = NSAlert()
                alert.messageText = "Discard keyboard shortcut changes?"
                alert.informativeText = "Your unsaved keyboard shortcut changes will not be applied."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Discard Changes")
                alert.addButton(withTitle: "Cancel")

                if alert.runModal() == .alertFirstButtonReturn {
                    shouldReallyClose = true
                    sender.performClose(nil)
                }

                return false
            }

            func windowWillClose(_ notification: Notification) {
                if let window {
                    window.delegate = nil
                }
            }
        }
    }
}
