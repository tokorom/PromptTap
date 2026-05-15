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
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
        .navigationTitle("Keyboard Shortcuts")
        // .toolbar {
        //     ToolbarItem(placement: .confirmationAction) {
        //         Button("Save") {
        //             settings.keyboardShortcuts = draftShortcuts
        //             dismiss()
        //         }
        //         .disabled(!hasChanges)
        //     }
        // }
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
}
