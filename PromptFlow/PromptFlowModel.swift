//
//  PromptFlowModel.swift
//  PromptFlow
//
//  Created by Yuta Tokoro on 2026/05/06.
//

import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class PromptFlowModel: ObservableObject {
    @Published var promptText = ""
    @Published var isEditorSelectionEmpty = true
    @Published private(set) var focusRequestID = 0
    @Published private(set) var previousApplicationName: String?

    private weak var previousApplication: NSRunningApplication?

    var canSubmit: Bool {
        previousApplication != nil
    }

    var statusText: String {
        if let previousApplicationName {
            "Submit target: \(previousApplicationName)"
        } else {
            "Open PromptFlow from another app to enable Submit"
        }
    }

    func noteActivatedApplication(_ application: NSRunningApplication?) {
        guard let application, application.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }

        previousApplication = application
        previousApplicationName = application.localizedName
    }

    func openFromShortcut() {
        noteActivatedApplication(NSWorkspace.shared.frontmostApplication)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
        focusEditor()
    }

    func focusEditor() {
        focusRequestID += 1
    }

    func copyPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(promptText, forType: .string)
    }

    func submitPrompt() {
        guard let previousApplication else {
            return
        }

        copyPrompt()
        previousApplication.activate(options: [.activateAllWindows])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Self.postPasteShortcut()
        }
    }

    private static func postPasteShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        let vKeyCode: CGKeyCode = 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
