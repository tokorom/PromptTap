//
//  SettingsView.swift
//  PromptFlow
//
//  Created by Yuta Tokoro on 2026/05/06.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: PromptFlowModel
    @EnvironmentObject private var settings: AppSettings

    @State private var showingClearConfirmation = false

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
                Picker("Hotkey", selection: $settings.hotkey) {
                    ForEach(HotkeyTrigger.allCases) { trigger in
                        Text(trigger.title)
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
    }
}
