//
//  AppSettings.swift
//  PromptTap
//
//  Created by Yuta Tokoro on 2026/05/06.
//

import AppKit
import Combine
import Foundation
import ServiceManagement

struct CustomHotkey: Codable, Equatable {
    let keyCode: UInt16
    let modifiersRawValue: UInt
    let keyEquivalent: String

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRawValue)
            .intersection(Self.supportedModifiers)
    }

    var title: String {
        "\(Self.modifierSymbols(for: modifiers))\(keyEquivalent)"
    }

    static let defaultValue = CustomHotkey(
        keyCode: 5,
        modifiersRawValue: NSEvent.ModifierFlags([.shift, .control]).rawValue,
        keyEquivalent: "G"
    )

    static let supportedModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    static func from(event: NSEvent) -> CustomHotkey? {
        guard event.type == .keyDown, !event.isARepeat else {
            return nil
        }

        let keyEquivalent = keyName(for: event)
        guard !keyEquivalent.isEmpty else {
            return nil
        }

        let modifiers = event.modifierFlags.intersection(supportedModifiers)
        return CustomHotkey(
            keyCode: UInt16(event.keyCode),
            modifiersRawValue: modifiers.rawValue,
            keyEquivalent: keyEquivalent
        )
    }

    static func modifierSymbols(for modifiers: NSEvent.ModifierFlags) -> String {
        var symbols = ""
        if modifiers.contains(.control) {
            symbols += "⌃"
        }
        if modifiers.contains(.option) {
            symbols += "⌥"
        }
        if modifiers.contains(.shift) {
            symbols += "⇧"
        }
        if modifiers.contains(.command) {
            symbols += "⌘"
        }
        return symbols
    }

    private static func keyName(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36:
            return "Return"
        case 48:
            return "Tab"
        case 49:
            return "Space"
        case 51:
            return "Delete"
        case 53:
            return "Esc"
        case 71:
            return "Clear"
        case 76:
            return "Enter"
        case 117:
            return "Forward Delete"
        case 123:
            return "←"
        case 124:
            return "→"
        case 125:
            return "↓"
        case 126:
            return "↑"
        case 122:
            return "F1"
        case 120:
            return "F2"
        case 99:
            return "F3"
        case 118:
            return "F4"
        case 96:
            return "F5"
        case 97:
            return "F6"
        case 98:
            return "F7"
        case 100:
            return "F8"
        case 101:
            return "F9"
        case 109:
            return "F10"
        case 103:
            return "F11"
        case 111:
            return "F12"
        default:
            return event.charactersIgnoringModifiers?.uppercased() ?? ""
        }
    }
}

enum HotkeyTrigger: String, CaseIterable, Identifiable {
    case doubleShift
    case doubleCommand
    case doubleOption
    case doubleControl
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .doubleShift:
            "⇧Shift, ⇧Shift"
        case .doubleCommand:
            "⌘Command, ⌘Command"
        case .doubleOption:
            "⌥Option, ⌥Option"
        case .doubleControl:
            "⌃Control, ⌃Control"
        case .custom:
            "Custom"
        }
    }

    var modifierFlag: NSEvent.ModifierFlags? {
        switch self {
        case .doubleShift:
            .shift
        case .doubleCommand:
            .command
        case .doubleOption:
            .option
        case .doubleControl:
            .control
        case .custom:
            nil
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

    @Published var customHotkey: CustomHotkey {
        didSet {
            if let data = try? JSONEncoder().encode(customHotkey) {
                UserDefaults.standard.set(data, forKey: Self.customHotkeyKey)
            }
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

    @Published var storagePath: String? {
        didSet {
            UserDefaults.standard.set(storagePath, forKey: Self.storagePathKey)
        }
    }

    @Published var historyEditingMode: Bool = false

    private static let hotkeyKey = "hotkeyTrigger"
    private static let customHotkeyKey = "customHotkey"
    private static let vimKeyBindingsKey = "usesVimKeyBindings"
    private static let historyLimitKey = "historyLimit"
    private static let launchAtLoginKey = "launchAtLogin"
    private static let sendEnterAfterSubmitKey = "sendEnterAfterSubmit"
    private static let lineWrappingKey = "lineWrapping"
    private static let storagePathKey = "templatesPath"

    init(userDefaults: UserDefaults = .standard) {
        let rawHotkey = userDefaults.string(forKey: Self.hotkeyKey)
        hotkey = rawHotkey.flatMap(HotkeyTrigger.init(rawValue:)) ?? .doubleCommand

        if let data = userDefaults.data(forKey: Self.customHotkeyKey),
           let decoded = try? JSONDecoder().decode(CustomHotkey.self, from: data) {
            customHotkey = decoded
        } else {
            customHotkey = .defaultValue
        }

        usesVimKeyBindings = userDefaults.bool(forKey: Self.vimKeyBindingsKey)
        
        var limit = userDefaults.integer(forKey: Self.historyLimitKey)
        if limit == 0 {
            limit = 100
        }
        historyLimit = limit
        
        launchAtLogin = userDefaults.bool(forKey: Self.launchAtLoginKey)
        sendEnterAfterSubmit = userDefaults.bool(forKey: Self.sendEnterAfterSubmitKey)
        
        if userDefaults.object(forKey: Self.lineWrappingKey) == nil {
            lineWrapping = true
        } else {
            lineWrapping = userDefaults.bool(forKey: Self.lineWrappingKey)
        }

        storagePath = userDefaults.string(forKey: Self.storagePathKey)
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
