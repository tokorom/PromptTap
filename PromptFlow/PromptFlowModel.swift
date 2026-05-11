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
    var filename: String?

    init(id: UUID = UUID(), name: String, text: String, updatedAt: Date = Date(), filename: String? = nil) {
        self.id = id
        self.name = name
        self.text = text
        self.updatedAt = updatedAt
        self.filename = filename
    }
}

struct PromptReserve: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var text: String
    var updatedAt: Date
    var filename: String?

    init(id: UUID = UUID(), name: String, text: String, updatedAt: Date = Date(), filename: String? = nil) {
        self.id = id
        self.name = name
        self.text = text
        self.updatedAt = updatedAt
        self.filename = filename
    }
}

enum SidebarSelection: Hashable {
    case current
    case history(UUID)
    case template(UUID)
    case reserve(UUID)
    case newTemplate
    case newReserve
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
        willSet {
            handleUnsavedChangesBeforeSelectionChange(to: newValue)
        }
        didSet {
            updatePromptTextFromSelection()
        }
    }

    private func handleUnsavedChangesBeforeSelectionChange(to newSelection: Set<SidebarSelection>) {
        guard newSelection.contains(.current) else { return }
        guard let currentSelection = selection.first else { return }

        switch currentSelection {
        case .template(let id):
            if let template = templates.first(where: { $0.id == id }), template.text != promptText {
                addToHistory(promptText)
            }
        case .newTemplate:
            if !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                addToHistory(promptText)
            }
        case .reserve(let id):
            if let reserve = reserves.first(where: { $0.id == id }), reserve.text != promptText {
                addToHistory(promptText)
            }
        case .newReserve:
            if !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                addToHistory(promptText)
            }
        default:
            break
        }
    }
    @Published private(set) var previousApplicationName: String?
    @Published private(set) var previousApplicationIcon: NSImage?
    @Published private(set) var targetHistory: [NSRunningApplication] = []
    @Published private(set) var history: [PromptHistory] = []
    @Published private(set) var templates: [PromptTemplate] = []
    @Published private(set) var reserves: [PromptReserve] = []
    @Published private(set) var isSubmitting = false
    @Published private(set) var isCopying = false
    @Published var shouldOpenMainWindow = false
    @Published private(set) var templateSearchRequestID = 0
    @Published private(set) var reserveSearchRequestID = 0

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

    var isReserveSelected: Bool {
        if let first = selection.first {
            switch first {
            case .reserve, .newReserve: return true
            default: return false
            }
        }
        return false
    }

    var canSubmit: Bool {
        previousApplication != nil && !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        loadReserves()
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
            case .reserve(let id):
                if let reserve = reserves.first(where: { $0.id == id }) {
                    templateNameBuffer = reserve.name
                    promptText = reserve.text
                }
            case .newTemplate, .newReserve:
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
            } else if selection.count == 1, case .template = selection.first {
                // For templates, we don't auto-save to allow cancel/discard if needed?
                // But the requirement says "Save button for updating", so we just keep it in promptText for now.
            } else if selection.count == 1, case .reserve = selection.first {
                // Same as templates
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
                saveTemplateFile(&templates[index])
                sortTemplates()
            }
        case .newTemplate:
            var newTemplate = PromptTemplate(name: finalName, text: promptText)
            saveTemplateFile(&newTemplate)
            templates.insert(newTemplate, at: 0)
            sortTemplates()
            selection = [.template(newTemplate.id)]
        default:
            break
        }
    }

    func saveReserve() {
        guard selection.count == 1, let first = selection.first else { return }

        switch first {
        case .reserve(let id):
            if let index = reserves.firstIndex(where: { $0.id == id }) {
                reserves[index].text = promptText
                reserves[index].updatedAt = Date()
                saveReserveFile(&reserves[index])
                sortReserves()
            }
        case .newReserve:
            let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }

            let firstWord = text.components(separatedBy: .whitespacesAndNewlines).first ?? "Untitled"
            var finalName = String(firstWord.prefix(10))
            if finalName.isEmpty {
                finalName = "Untitled"
            }

            var newReserve = PromptReserve(name: finalName, text: text)
            saveReserveFile(&newReserve)
            reserves.insert(newReserve, at: 0)
            sortReserves()
            selection = [.reserve(newReserve.id)]
        default:
            break
        }
    }

    func applyTemplate() {
        // Update template's updatedAt to move it to top
        if case .template(let id) = selection.first {
            if let index = templates.firstIndex(where: { $0.id == id }) {
                templates[index].updatedAt = Date()
                saveTemplateFile(&templates[index])
                sortTemplates()
            }
        }

        currentPromptBuffer = promptText
        selection = [.current]
    }

    func applyTemplate(_ template: PromptTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index].updatedAt = Date()
            saveTemplateFile(&templates[index])
            currentPromptBuffer = templates[index].text
            promptText = templates[index].text
            sortTemplates()
        } else {
            currentPromptBuffer = template.text
            promptText = template.text
        }

        selection = [.current]
    }

    private func sortTemplates() {
        templates.sort { $0.updatedAt > $1.updatedAt }
    }

    func revealTemplateInFinder(_ template: PromptTemplate) {
        guard let filename = template.filename else { return }
        let fileURL = templatesDirectoryURL.appendingPathComponent(filename)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func revealReserveInFinder(_ reserve: PromptReserve) {
        guard let filename = reserve.filename else { return }
        let fileURL = reservesDirectoryURL.appendingPathComponent(filename)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func deleteTemplates(_ templatesToDelete: Set<PromptTemplate>) {
        let idsToDelete = Set(templatesToDelete.map { $0.id })
        
        for template in templatesToDelete {
            if let filename = template.filename {
                let fileURL = templatesDirectoryURL.appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        
        templates.removeAll { idsToDelete.contains($0.id) }
        
        // Update selection: remove deleted templates
        selection = selection.filter { sel in
            if case .template(let id) = sel {
                return !idsToDelete.contains(id)
            }
            return true
        }
        
        if selection.isEmpty {
            selection = [.current]
        }
    }

    func deleteReserves(_ reservesToDelete: Set<PromptReserve>) {
        let idsToDelete = Set(reservesToDelete.map { $0.id })
        
        for reserve in reservesToDelete {
            if let filename = reserve.filename {
                let fileURL = reservesDirectoryURL.appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        
        reserves.removeAll { idsToDelete.contains($0.id) }
        
        // Update selection: remove deleted reserves
        selection = selection.filter { sel in
            if case .reserve(let id) = sel {
                return !idsToDelete.contains(id)
            }
            return true
        }
        
        if selection.isEmpty {
            selection = [.current]
        }
    }

    func deleteTemplates(at offsets: IndexSet) {
        let templatesToDelete = Set(offsets.map { templates[$0] })
        deleteTemplates(templatesToDelete)
    }

    func deleteReserves(at offsets: IndexSet) {
        let reservesToDelete = Set(offsets.map { reserves[$0] })
        deleteReserves(reservesToDelete)
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

        settings.$storagePath
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.loadTemplates()
                    self?.loadReserves()
                }
            }
            .store(in: &cancellables)
    }

    func noteActivatedApplication(_ application: NSRunningApplication?) {
        guard let application, application.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }

        updateTargetHistory(application)
    }

    func setTarget(_ application: NSRunningApplication) {
        previousApplication = application
        previousApplicationName = application.localizedName
        previousApplicationIcon = application.icon
        updateTargetHistory(application)
    }

    private func updateTargetHistory(_ application: NSRunningApplication) {
        if application.localizedName == nil || application.localizedName == "Unknown App" {
            return
        }

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
            let mainWindows = NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix("main") == true }
            let isMainWindowFrontmost = mainWindows.contains { $0.isKeyWindow }
            if isMainWindowFrontmost {
                returnToTarget()
                return
            }
        }

        let frontmost = NSWorkspace.shared.frontmostApplication
        if isHotkey {
            if !currentPromptBuffer.isEmpty && !history.contains(where: { $0.text == currentPromptBuffer }) {
                addToHistory(currentPromptBuffer)
                currentPromptBuffer = ""
            }
            
            selection = [.current]
            promptText = currentPromptBuffer

            if let frontmost {
                setTarget(frontmost)
            }
        }

        noteActivatedApplication(frontmost)
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

    func requestTemplateSearch() {
        templateSearchRequestID += 1
    }

    func requestReserveSearch() {
        reserveSearchRequestID += 1
    }

    func reservePrompt() {
        let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let firstWord = text.components(separatedBy: .whitespacesAndNewlines).first ?? "Untitled"
        var finalName = String(firstWord.prefix(10))
        if finalName.isEmpty {
            finalName = "Untitled"
        }

        var newReserve = PromptReserve(name: finalName, text: text)
        saveReserveFile(&newReserve)
        reserves.insert(newReserve, at: 0)
        sortReserves()
        selection = [.reserve(newReserve.id)]
    }

    func applyReserve(_ reserve: PromptReserve) {
        if let index = reserves.firstIndex(where: { $0.id == reserve.id }) {
            let text = reserves[index].text
            reserves[index].updatedAt = Date()
            saveReserveFile(&reserves[index])
            
            currentPromptBuffer = text
            promptText = text
            
            sortReserves()
            selection = [.current]
        }
    }

    private func sortReserves() {
        reserves.sort { $0.updatedAt > $1.updatedAt }
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

    private var templatesDirectoryURL: URL {
        let url = storageDirectoryURL.appendingPathComponent("templates")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var reservesDirectoryURL: URL {
        let url = storageDirectoryURL.appendingPathComponent("reserves")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var storageDirectoryURL: URL {
        if let customPath = settings?.storagePath, !customPath.isEmpty {
            return URL(fileURLWithPath: customPath)
        }
        return defaultStorageDirectoryURL
    }

    var defaultStorageDirectoryURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "PromptFlow")
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }

    var defaultTemplatesDirectoryURL: URL {
        templatesDirectoryURL
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

    private func saveTemplateFile(_ template: inout PromptTemplate) {
        let name = template.name
        let sanitizedName = name.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
        
        let newFilename: String
        if let existingFilename = template.filename {
            let components = existingFilename.components(separatedBy: "_")
            if components.count >= 2, components.dropLast().joined(separator: "_") == sanitizedName {
                newFilename = existingFilename
            } else {
                // If name changed, we need to create a new filename and delete the old one
                let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                newFilename = "\(sanitizedName)_\(timestamp).txt"
                
                let oldFileURL = templatesDirectoryURL.appendingPathComponent(existingFilename)
                try? FileManager.default.removeItem(at: oldFileURL)
                template.filename = newFilename
            }
        } else {
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            newFilename = "\(sanitizedName)_\(timestamp).txt"
            template.filename = newFilename
        }

        let fileURL = templatesDirectoryURL.appendingPathComponent(newFilename)
        do {
            try template.text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save template file: \(error)")
        }
    }

    private func loadTemplates() {
        let dirURL = templatesDirectoryURL
        guard let files = try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }

        var loadedTemplates: [PromptTemplate] = []
        for fileURL in files where fileURL.pathExtension == "txt" {
            do {
                let text = try String(contentsOf: fileURL, encoding: .utf8)
                let filename = fileURL.lastPathComponent
                let nameWithoutExtension = fileURL.deletingPathExtension().lastPathComponent
                let name: String
                let components = nameWithoutExtension.components(separatedBy: "_")
                if components.count >= 2 {
                    name = components.dropLast().joined(separator: "_")
                } else {
                    name = nameWithoutExtension
                }

                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                let modificationDate = attributes[.modificationDate] as? Date ?? Date()

                let template = PromptTemplate(
                    name: name,
                    text: text,
                    updatedAt: modificationDate,
                    filename: filename
                )
                loadedTemplates.append(template)
            } catch {
                print("Failed to load template file \(fileURL): \(error)")
            }
        }
        templates = loadedTemplates.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func saveReserveFile(_ reserve: inout PromptReserve) {
        let name = reserve.name
        let sanitizedName = name.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
        
        let newFilename: String
        if let existingFilename = reserve.filename {
            let components = existingFilename.components(separatedBy: "_")
            if components.count >= 2, components.dropLast().joined(separator: "_") == sanitizedName {
                newFilename = existingFilename
            } else {
                let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                newFilename = "\(sanitizedName)_\(timestamp).txt"
                
                let oldFileURL = reservesDirectoryURL.appendingPathComponent(existingFilename)
                try? FileManager.default.removeItem(at: oldFileURL)
                reserve.filename = newFilename
            }
        } else {
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            newFilename = "\(sanitizedName)_\(timestamp).txt"
            reserve.filename = newFilename
        }

        let fileURL = reservesDirectoryURL.appendingPathComponent(newFilename)
        do {
            try reserve.text.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save reserve file: \(error)")
        }
    }

    private func loadReserves() {
        let dirURL = reservesDirectoryURL
        guard let files = try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }

        var loadedReserves: [PromptReserve] = []
        for fileURL in files where fileURL.pathExtension == "txt" {
            do {
                let text = try String(contentsOf: fileURL, encoding: .utf8)
                let filename = fileURL.lastPathComponent
                let nameWithoutExtension = fileURL.deletingPathExtension().lastPathComponent
                let name: String
                let components = nameWithoutExtension.components(separatedBy: "_")
                if components.count >= 2 {
                    name = components.dropLast().joined(separator: "_")
                } else {
                    name = nameWithoutExtension
                }

                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                let modificationDate = attributes[.modificationDate] as? Date ?? Date()

                let reserve = PromptReserve(
                    name: name,
                    text: text,
                    updatedAt: modificationDate,
                    filename: filename
                )
                loadedReserves.append(reserve)
            } catch {
                print("Failed to load reserve file \(fileURL): \(error)")
            }
        }
        reserves = loadedReserves.sorted { $0.updatedAt > $1.updatedAt }
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
