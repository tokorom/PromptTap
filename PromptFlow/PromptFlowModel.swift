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
import SwiftUI

struct PromptHistory: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let date: Date

    init(id: UUID = UUID(), text: String, date: Date = Date()) {
        self.id = id
        self.text = text
        self.date = date
    }
}

enum SidebarSelection: Hashable {
    case current
    case history(UUID)
}

@MainActor
final class PromptFlowModel: ObservableObject {
    @Published private(set) var promptText = ""
    @Published private(set) var currentPromptBuffer = ""
    @Published var isEditorSelectionEmpty = true
    @Published private(set) var focusRequestID = 0
    @Published private(set) var focusListRequestID = 0
    @Published var selection: Set<SidebarSelection> = [.current] {
        didSet {
            updatePromptTextFromSelection()
        }
    }
    @Published private(set) var previousApplicationName: String?
    @Published private(set) var targetHistory: [NSRunningApplication] = []
    @Published private(set) var history: [PromptHistory] = []
    @Published private(set) var isSubmitting = false
    @Published private(set) var isCopying = false
    @Published var shouldOpenMainWindow = false

    private var previousApplication: NSRunningApplication?
    private var settings: AppSettings?
    private var cancellables = Set<AnyCancellable>()

    var isCurrentPromptSelected: Bool {
        selection.contains(.current)
    }

    var canSubmit: Bool {
        previousApplication != nil && !promptText.isEmpty
    }

    var statusText: String {
        if let previousApplicationName {
            "Submit target: \(previousApplicationName)"
        } else {
            "Open PromptFlow from another app to enable Submit"
        }
    }

    init() {
        loadHistory()
    }

    private func updatePromptTextFromSelection() {
        guard let lastSelection = selection.first else { return }

        Task { @MainActor in
            switch lastSelection {
            case .current:
                promptText = currentPromptBuffer
            case .history(let id):
                if let entry = history.first(where: { $0.id == id }) {
                    promptText = entry.text
                }
            }
        }
    }

    func updateTextFromEditor(_ text: String) {
        if promptText != text {
            promptText = text
            if isCurrentPromptSelected {
                currentPromptBuffer = text
            }
        }
    }

    func setup(settings: AppSettings) {
        self.settings = settings
        settings.$historyLimit
            .sink { [weak self] limit in
                Task { @MainActor in
                    self?.shrinkHistory(to: limit)
                }
            }
            .store(in: &cancellables)
    }

    func noteActivatedApplication(_ application: NSRunningApplication?) {
        guard let application, application.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }

        setTarget(application)
    }

    func setTarget(_ application: NSRunningApplication) {
        previousApplication = application
        previousApplicationName = application.localizedName

        // Update history: remove if exists, insert at front, limit to 10
        if let index = targetHistory.firstIndex(where: { $0.bundleIdentifier == application.bundleIdentifier }) {
            targetHistory.remove(at: index)
        }
        targetHistory.insert(application, at: 0)
        if targetHistory.count > 10 {
            targetHistory.removeLast()
        }
    }

    func openFromShortcut() {
        if NSApp.isActive {
            returnToTarget()
            return
        }

        if !currentPromptBuffer.isEmpty && !history.contains(where: { $0.text == currentPromptBuffer }) {
            addToHistory(currentPromptBuffer)
            currentPromptBuffer = ""
        }
        
        selection = [.current]
        promptText = currentPromptBuffer

        noteActivatedApplication(NSWorkspace.shared.frontmostApplication)
        NSApp.activate(ignoringOtherApps: true)
        
        let mainWindows = NSApp.windows.filter { window in
            window.identifier?.rawValue.hasPrefix("main") == true
        }
        if mainWindows.isEmpty {
            shouldOpenMainWindow = true
        } else {
            for window in mainWindows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        
        // Use a slight delay to ensure SwiftUI finished updating the view hierarchy
        // before requesting focus on the WebView.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.focusEditor()
        }
    }

    func returnToTarget() {
        previousApplication?.activate(options: [.activateAllWindows])
    }

    func focusEditor() {
        focusRequestID += 1
    }

    func focusList() {
        focusListRequestID += 1
    }

    func copyPrompt() {
        isCopying = true
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(promptText, forType: .string)
        addToHistory(promptText)

        if isCurrentPromptSelected {
            currentPromptBuffer = ""
            promptText = ""
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isCopying = false
        }
    }

    func submitPrompt() {
        guard let previousApplication else {
            return
        }

        isSubmitting = true
        copyPrompt()
        previousApplication.activate(options: [.activateAllWindows])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Self.postPasteShortcut()
            
            if self.settings?.sendEnterAfterSubmit == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    Self.postEnterKey()
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isSubmitting = false
        }
    }

    private func addToHistory(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existingIndex = history.firstIndex(where: { $0.text == text }) {
            history.remove(at: existingIndex)
        }
        let entry = PromptHistory(text: text)
        history.insert(entry, at: 0)
        shrinkHistory(to: settings?.historyLimit ?? 100)
        saveHistory()
    }

    func deleteHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        saveHistory()
        
        // Clear selection if the deleted item was selected
        selection = selection.filter { sel in
            if case .history(let id) = sel {
                return history.contains(where: { $0.id == id })
            }
            return true
        }
        if selection.isEmpty {
            selection = [.current]
        }
    }

    func deleteHistoryItems(_ entries: Set<PromptHistory>) {
        let ids = Set(entries.map { $0.id })
        history.removeAll { ids.contains($0.id) }
        saveHistory()
        
        // Clear selection if the deleted item was selected
        selection = selection.filter { sel in
            if case .history(let id) = sel {
                return !ids.contains(id)
            }
            return true
        }
        if selection.isEmpty {
            selection = [.current]
        }
    }

    func deleteHistoryItem(_ entry: PromptHistory) {
        deleteHistoryItems([entry])
    }

    private func shrinkHistory(to limit: Int) {
        if history.count > limit {
            history = Array(history.prefix(limit))
            saveHistory()
        }
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    private var historyURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "PromptFlow")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("history.json")
    }

    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: historyURL)
        } catch {
            print("Failed to save history: \(error)")
        }
    }

    private func loadHistory() {
        do {
            let data = try Data(contentsOf: historyURL)
            history = try JSONDecoder().decode([PromptHistory].self, from: data)
        } catch {
            print("No history found or failed to load: \(error)")
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

    private static func postEnterKey() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        let enterKeyCode: CGKeyCode = 36
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: enterKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: enterKeyCode, keyDown: false)

        // Explicitly clear flags to ensure Command (from Command+S) is not included
        keyDown?.flags = []
        keyUp?.flags = []

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
