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

struct PromptTemplate: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var text: String
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, text: String, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.text = text
        self.updatedAt = updatedAt
    }
}

enum SidebarSelection: Hashable {
    case current
    case history(UUID)
    case template(UUID)
    case newTemplate
}

@MainActor
final class PromptFlowModel: ObservableObject {
    @Published private(set) var promptText = ""
    @Published private(set) var currentPromptBuffer = ""
    @Published var templateNameBuffer = ""
    @Published var isEditorSelectionEmpty = true
    @Published private(set) var focusRequestID = 0
    @Published private(set) var focusListRequestID = 0
    @Published var selection: Set<SidebarSelection> = [.current] {
        didSet {
            updatePromptTextFromSelection()
        }
    }
    @Published private(set) var previousApplicationName: String?
    @Published private(set) var previousApplicationIcon: NSImage?
    @Published private(set) var targetHistory: [NSRunningApplication] = []
    @Published private(set) var history: [PromptHistory] = []
    @Published private(set) var templates: [PromptTemplate] = []
    @Published private(set) var isSubmitting = false
    @Published private(set) var isCopying = false
    @Published var shouldOpenMainWindow = false

    private var previousApplication: NSRunningApplication?
    private var settings: AppSettings?
    private var cancellables = Set<AnyCancellable>()

    var isCurrentPromptSelected: Bool {
        selection.contains(.current)
    }

    var isTemplateSelected: Bool {
        if let first = selection.first {
            switch first {
            case .template, .newTemplate: return true
            default: return false
            }
        }
        return false
    }

    var canSubmit: Bool {
        previousApplication != nil && !promptText.isEmpty && isCurrentPromptSelected
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
        loadTemplates()
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
            case .template(let id):
                if let template = templates.first(where: { $0.id == id }) {
                    templateNameBuffer = template.name
                    promptText = template.text
                }
            case .newTemplate:
                templateNameBuffer = ""
                promptText = ""
            }
        }
    }

    func updateTextFromEditor(_ text: String) {
        if promptText != text {
            promptText = text
            if isCurrentPromptSelected {
                currentPromptBuffer = text
            } else if selection.count == 1, case .history(let id) = selection.first {
                if let index = history.firstIndex(where: { $0.id == id }) {
                    if history[index].text != text {
                        history[index] = PromptHistory(id: id, text: text, date: Date())
                        saveHistory()
                    }
                }
            } else if selection.count == 1, case .template(let id) = selection.first {
                // For templates, we don't auto-save to allow cancel/discard if needed?
                // But the requirement says "Save button for updating", so we just keep it in promptText for now.
            }
        }
    }

    func saveTemplate() {
        guard selection.count == 1, let first = selection.first else { return }
        
        var finalName = templateNameBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalName.isEmpty {
            let firstWord = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .whitespacesAndNewlines)
                .first ?? "Untitled"
            finalName = String(firstWord.prefix(10))
            if finalName.isEmpty {
                finalName = "Untitled"
            }
            templateNameBuffer = finalName
        }

        switch first {
        case .template(let id):
            if let index = templates.firstIndex(where: { $0.id == id }) {
                templates[index].name = finalName
                templates[index].text = promptText
                templates[index].updatedAt = Date()
                sortTemplates()
                saveTemplates()
            }
        case .newTemplate:
            let newTemplate = PromptTemplate(name: finalName, text: promptText)
            templates.insert(newTemplate, at: 0)
            sortTemplates()
            saveTemplates()
            selection = [.template(newTemplate.id)]
        default:
            break
        }
    }

    func applyTemplate() {
        currentPromptBuffer = promptText
        selection = [.current]
        
        // Update template's updatedAt to move it to top
        if case .template(let id) = selection.first {
            if let index = templates.firstIndex(where: { $0.id == id }) {
                templates[index].updatedAt = Date()
                sortTemplates()
                saveTemplates()
            }
        }
    }

    private func sortTemplates() {
        templates.sort { $0.updatedAt > $1.updatedAt }
    }

    func deleteTemplate(_ template: PromptTemplate) {
        templates.removeAll { $0.id == template.id }
        saveTemplates()
        if case .template(let id) = selection.first, id == template.id {
            selection = [.current]
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
        previousApplicationIcon = application.icon

        // Update history: remove if exists, insert at front, limit to 10
        if let index = targetHistory.firstIndex(where: { $0.bundleIdentifier == application.bundleIdentifier }) {
            targetHistory.remove(at: index)
        }
        targetHistory.insert(application, at: 0)
        if targetHistory.count > 10 {
            targetHistory.removeLast()
        }
    }

    func openFromShortcut(isHotkey: Bool = true) {
        if isHotkey && NSApp.isActive {
            returnToTarget()
            return
        }

        if isHotkey {
            if !currentPromptBuffer.isEmpty && !history.contains(where: { $0.text == currentPromptBuffer }) {
                addToHistory(currentPromptBuffer)
                currentPromptBuffer = ""
            }
            
            selection = [.current]
            promptText = currentPromptBuffer
        }

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
            self.focusEditor(enterVimInsertMode: isHotkey)
        }
    }

    func returnToTarget() {
        previousApplication?.activate(options: [.activateAllWindows])
    }

    func focusEditor(enterVimInsertMode: Bool = false) {
        if enterVimInsertMode {
            focusRequestID = (focusRequestID % 1000) + 1001 // Use 1001+ for insert mode
        } else {
            focusRequestID = (focusRequestID % 1000) + 1
        }
    }

    func focusList() {
        focusListRequestID += 1
    }

    func copyPrompt() {
        isCopying = true
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(promptText, forType: .string)

        var updateID: UUID? = nil
        if case .history(let id) = selection.first {
            updateID = id
        }
        addToHistory(promptText, id: updateID)

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

    private func addToHistory(_ text: String, id: UUID? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let id = id {
            history.removeAll { $0.id == id }
        }
        if let existingIndex = history.firstIndex(where: { $0.text == text }) {
            history.remove(at: existingIndex)
        }
        let entry = PromptHistory(id: id ?? UUID(), text: text)
        history.insert(entry, at: 0)
        shrinkHistory(to: settings?.historyLimit ?? 100)
        saveHistory()

        if id != nil {
            selection = [.history(entry.id)]
        }
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

    func mergeHistoryItems(_ entries: [PromptHistory]) {
        guard entries.count > 1 else { return }

        let sortedInDisplayOrder = entries.sorted { a, b in
            let indexA = history.firstIndex(where: { $0.id == a.id }) ?? Int.max
            let indexB = history.firstIndex(where: { $0.id == b.id }) ?? Int.max
            return indexA < indexB
        }

        let mergedText = sortedInDisplayOrder.map { $0.text }.joined(separator: "\n\n")

        let idsToRemove = Set(entries.map { $0.id })
        history.removeAll { idsToRemove.contains($0.id) }

        let newEntry = PromptHistory(text: mergedText)
        history.insert(newEntry, at: 0)

        shrinkHistory(to: settings?.historyLimit ?? 100)
        saveHistory()

        selection = [.history(newEntry.id)]
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

    private var templatesURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "PromptFlow")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("templates.json")
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

    private func saveTemplates() {
        do {
            let data = try JSONEncoder().encode(templates)
            try data.write(to: templatesURL)
        } catch {
            print("Failed to save templates: \(error)")
        }
    }

    private func loadTemplates() {
        do {
            let data = try Data(contentsOf: templatesURL)
            templates = try JSONDecoder().decode([PromptTemplate].self, from: data)
        } catch {
            print("No templates found or failed to load: \(error)")
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
