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
            PromptCommands(model: model, settings: settings)
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

        WindowGroup(id: "keyboard-shortcuts") {
            NavigationStack {
                KeyboardShortcutsSettingsView()
                    .environmentObject(model)
                    .environmentObject(settings)
            }
        }
        .windowResizability(.contentSize)
        .onChange(of: model.shouldOpenKeyboardShortcutsWindow) { _, newValue in
            if newValue {
                defer {
                    model.shouldOpenKeyboardShortcutsWindow = false
                }

                let id = "keyboard-shortcuts"
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("\(id)-") ?? false }) {
                    if window.isMiniaturized {
                        window.deminiaturize(nil)
                    }

                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                } else {
                    openWindow(id: id)
                }
            }
        }
    }
}

struct PromptCommands: Commands {
    @ObservedObject var model: PromptTapModel
    @ObservedObject var settings: AppSettings

    var body: some Commands {
        CommandMenu("Prompt") {
            Button("Submit") {
                model.submitPrompt()
            }
            .appKeyboardShortcut(settings.shortcut(for: .submit))
            .disabled(!model.canSubmit)

            Button("Copy") {
                model.copyPrompt()
            }
            .appKeyboardShortcut(settings.shortcut(for: .copy))
            .disabled(!model.isEditorSelectionEmpty || model.promptText.isEmpty)

            Divider()

            Button("Search") {
                model.requestGlobalSearch()
            }
            .appKeyboardShortcut(settings.shortcut(for: .globalSearch))

            Button("Search Templates") {
                model.requestTemplateSearch()
            }
            .appKeyboardShortcut(settings.shortcut(for: .templateSearch))

            Button("Search Reserves") {
                model.requestReserveSearch()
            }
            .appKeyboardShortcut(settings.shortcut(for: .reserveSearch))
        }
    }
}
