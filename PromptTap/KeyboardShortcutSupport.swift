//
//  KeyboardShortcutSupport.swift
//  PromptTap
//
//  Created by Codex on 2026/05/15.
//

import AppKit
import SwiftUI

extension CustomHotkey {
    var swiftUIKeyEquivalent: KeyEquivalent {
        KeyEquivalent(Character(keyEquivalent.lowercased()))
    }

    var swiftUIModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if self.modifiers.contains(.command) {
            modifiers.insert(.command)
        }
        if self.modifiers.contains(.shift) {
            modifiers.insert(.shift)
        }
        if self.modifiers.contains(.option) {
            modifiers.insert(.option)
        }
        if self.modifiers.contains(.control) {
            modifiers.insert(.control)
        }
        return modifiers
    }

    var webShortcutDescriptor: WebShortcutDescriptor {
        WebShortcutDescriptor(
            key: keyEquivalent.lowercased(),
            command: modifiers.contains(.command),
            shift: modifiers.contains(.shift),
            option: modifiers.contains(.option),
            control: modifiers.contains(.control)
        )
    }
}

struct WebShortcutDescriptor: Encodable, Equatable {
    let key: String
    let command: Bool
    let shift: Bool
    let option: Bool
    let control: Bool
}

extension View {
    func appKeyboardShortcut(_ hotkey: CustomHotkey) -> some View {
        keyboardShortcut(hotkey.swiftUIKeyEquivalent, modifiers: hotkey.swiftUIModifiers)
    }
}
