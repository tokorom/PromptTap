//
//  AppSettings.swift
//  PromptFlow
//
//  Created by Yuta Tokoro on 2026/05/06.
//

import AppKit
import Combine
import Foundation
import ServiceManagement

enum HotkeyTrigger: String, CaseIterable, Identifiable {
    case doubleShift
    case doubleCommand
    case doubleOption
    case doubleControl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .doubleShift:
            "Shift, Shift"
        case .doubleCommand:
            "Command, Command"
        case .doubleOption:
            "Option, Option"
        case .doubleControl:
            "Control, Control"
        }
    }

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .doubleShift:
            .shift
        case .doubleCommand:
            .command
        case .doubleOption:
            .option
        case .doubleControl:
            .control
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var hotkey: HotkeyTrigger {
        didSet {
            UserDefaults.standard.set(hotkey.rawValue, forKey: Self.hotkeyKey)
        }
    }

    @Published var usesVimKeyBindings: Bool {
        didSet {
            UserDefaults.standard.set(usesVimKeyBindings, forKey: Self.vimKeyBindingsKey)
        }
    }

    @Published var historyLimit: Int {
        didSet {
            UserDefaults.standard.set(historyLimit, forKey: Self.historyLimitKey)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Self.launchAtLoginKey)
            updateLaunchAtLogin()
        }
    }

    @Published var sendEnterAfterSubmit: Bool {
        didSet {
            UserDefaults.standard.set(sendEnterAfterSubmit, forKey: Self.sendEnterAfterSubmitKey)
        }
    }

    @Published var lineWrapping: Bool {
        didSet {
            UserDefaults.standard.set(lineWrapping, forKey: Self.lineWrappingKey)
        }
    }

    @Published var historyEditingMode: Bool = false

    private static let hotkeyKey = "hotkeyTrigger"
    private static let vimKeyBindingsKey = "usesVimKeyBindings"
    private static let historyLimitKey = "historyLimit"
    private static let launchAtLoginKey = "launchAtLogin"
    private static let sendEnterAfterSubmitKey = "sendEnterAfterSubmit"
    private static let lineWrappingKey = "lineWrapping"

    init(userDefaults: UserDefaults = .standard) {
        let rawHotkey = userDefaults.string(forKey: Self.hotkeyKey)
        hotkey = rawHotkey.flatMap(HotkeyTrigger.init(rawValue:)) ?? .doubleShift
        usesVimKeyBindings = userDefaults.bool(forKey: Self.vimKeyBindingsKey)
        
        var limit = userDefaults.integer(forKey: Self.historyLimitKey)
        if limit == 0 {
            limit = 100
        }
        historyLimit = limit
        
        launchAtLogin = userDefaults.bool(forKey: Self.launchAtLoginKey)
        sendEnterAfterSubmit = userDefaults.bool(forKey: Self.sendEnterAfterSubmitKey)
        lineWrapping = userDefaults.bool(forKey: Self.lineWrappingKey)
    }

    private func updateLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                if service.status == .enabled {
                    try? service.unregister()
                }
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }
}
