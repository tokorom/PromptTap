//
//  PromptTapApp.swift
//  PromptTap
//
//  Created by Yuta Tokoro on 2026/05/06.
//

import SwiftUI

@main
struct PromptTapApp: App {
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = PromptTapModel()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(settings)
                .onAppear {
                    model.setup(settings: settings)
                    appDelegate.configure(model: model, settings: settings)
                }
        }
        .commands {
            PromptCommands(model: model)
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .help) {
                Button("PromptTap Help") {
                    if let url = URL(string: "https://github.com/tokorom/PromptTap/blob/main/README.md") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .onChange(of: model.shouldOpenMainWindow) { _, newValue in
            if newValue {
                openWindow(id: "main")
                model.shouldOpenMainWindow = false
            }
        }
        .onChange(of: model.shouldCloseMainWindow) { _, newValue in
            if newValue {
                NSApp.hide(nil)
                model.shouldCloseMainWindow = false
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(settings)
        }
    }
}

struct PromptCommands: Commands {
    @ObservedObject var model: PromptTapModel

    var body: some Commands {
        CommandMenu("Prompt") {
            Button("Global Search") {
                model.requestGlobalSearch()
            }
            .keyboardShortcut("s", modifiers: .command)

            Divider()

            Button("Submit") {
                model.submitPrompt()
            }
            .disabled(!model.canSubmit)

            Button("Copy") {
                model.copyPrompt()
            }
            .disabled(!model.isEditorSelectionEmpty || model.promptText.isEmpty)

            Divider()

            Button("Search Templates") {
                model.requestTemplateSearch()
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Search Reserves") {
                model.requestReserveSearch()
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}
