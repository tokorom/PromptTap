//
//  PromptFlowApp.swift
//  PromptFlow
//
//  Created by Yuta Tokoro on 2026/05/06.
//

import SwiftUI

@main
struct PromptFlowApp: App {
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = PromptFlowModel()
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
        }
        .onChange(of: model.shouldOpenMainWindow) { newValue in
            if newValue {
                openWindow(id: "main")
                model.shouldOpenMainWindow = false
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
    @ObservedObject var model: PromptFlowModel

    var body: some Commands {
        CommandMenu("Prompt") {
            Button("Submit") {
                model.submitPrompt()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!model.canSubmit)

            Button("Copy") {
                model.copyPrompt()
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(!model.isEditorSelectionEmpty)
        }
    }
}
