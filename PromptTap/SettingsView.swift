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
        NavigationStack {
            settingsForm
                .navigationTitle("Settings")
        }
    }

    private var settingsForm: some View {
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

                Button {
                    model.openKeyboardShortcutsWindow()
                } label: {
                    HStack {
                        Text("Keyboard Shortcuts")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

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
                title: "Custom Hotkey",
                candidateHotkey: $draftCustomHotkey,
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
