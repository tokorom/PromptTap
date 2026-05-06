//
//  AppSettings.swift
//  PromptFlow
//
//  Created by Yuta Tokoro on 2026/05/06.
//

import AppKit
import Combine
import Foundation

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

    @Published var historyEditingMode: Bool = false

    private static let hotkeyKey = "hotkeyTrigger"
    private static let vimKeyBindingsKey = "usesVimKeyBindings"
    private static let historyLimitKey = "historyLimit"

    init(userDefaults: UserDefaults = .standard) {
        let rawHotkey = userDefaults.string(forKey: Self.hotkeyKey)
        hotkey = rawHotkey.flatMap(HotkeyTrigger.init(rawValue:)) ?? .doubleShift
        usesVimKeyBindings = userDefaults.bool(forKey: Self.vimKeyBindingsKey)
        historyLimit = userDefaults.integer(forKey: Self.historyLimitKey)
        if historyLimit == 0 {
            historyLimit = 100
        }
    }
}
