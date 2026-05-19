//
//  PromptTapModel.swift
//  PromptTap
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
final class PromptTapModel: ObservableObject {
    @Published private(set) var promptText = ""
    @Published private(set) var currentPromptBuffer = ""
    @Published var templateNameBuffer = ""
    @Published var isEditorSelectionEmpty = true
    @Published private(set) var focusRequestID = 0
    @Published private(set) var focusListRequestID = 0
    @Published private(set) var saveRequestID = 0
    @Published var selection: Set<SidebarSelection> = [.current] {
        willSet {
            if !isDiscardingChanges {
                handleUnsavedChangesBeforeSelectionChange(to: newValue)
            }
            isDiscardingChanges = false
        }
        didSet {
            updatePromptTextFromSelection()
        }
    }

    private var isDiscardingChanges = false

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
    var hasUnsavedChanges: Bool {
        guard let first = selection.first else { return false }
        switch first {
        case .template(let id):
            if let template = templates.first(where: { $0.id == id }) {
                return template.text != promptText || template.name != templateNameBuffer
            }
        case .newTemplate:
            return !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !templateNameBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .reserve(let id):
            if let reserve = reserves.first(where: { $0.id == id }) {
                return reserve.text != promptText
            }
        case .history(let id):
            if let entry = history.first(where: { $0.id == id }) {
                return entry.text != promptText
            }
        case .newReserve:
            return !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
        return false
    }

    @Published var showingUnsavedChangesConfirmation = false
    private(set) var pendingSelection: Set<SidebarSelection>?
    private var pendingAction: (() -> Void)?

    func requestSelection(_ newSelection: Set<SidebarSelection>, action: (() -> Void)? = nil) {
        guard newSelection != selection || action != nil else { return }

        if hasUnsavedChanges {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingSelection = newSelection
                self.pendingAction = action
                self.showingUnsavedChangesConfirmation = true
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let action = action {
                    action()
                }
                self.selection = newSelection
            }
        }
    }

    func confirmSaveAndMove() {
        if isTemplateSelected {
            saveTemplate(shouldUpdateSelection: false)
        } else if isReserveSelected {
            saveReserve(shouldUpdateSelection: false)
        } else if isHistorySelected {
            saveHistoryItem()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if let action = self.pendingAction {
                action()
                self.pendingAction = nil
            }

            if let pending = self.pendingSelection {
                self.selection = pending
                self.pendingSelection = nil
            }
            self.showingUnsavedChangesConfirmation = false
        }
    }

    func confirmDiscardAndMove() {
        isDiscardingChanges = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if let action = self.pendingAction {
                action()
                self.pendingAction = nil
            }

            if let pending = self.pendingSelection {
                self.selection = pending
                self.pendingSelection = nil
            }
            self.showingUnsavedChangesConfirmation = false
        }
    }

    func cancelMove() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingSelection = nil
            self.pendingAction = nil
            self.showingUnsavedChangesConfirmation = false
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
    @Published private(set) var globalSearchRequestID = 0
    @Published private(set) var templateSearchRequestID = 0
    @Published private(set) var reserveSearchRequestID = 0
    @Published private(set) var activeExternalEditSession: ExternalEditSession?

    var isTargetSet: Bool {
        previousApplication != nil
    }

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

    var isHistorySelected: Bool {
        if let first = selection.first {
            switch first {
            case .history: return true
            default: return false
            }
        }
        return false
    }

    var canSubmit: Bool {
        activeExternalEditSession != nil || (previousApplication != nil && !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var statusText: String {
        if let activeExternalEditSession {
            return "Editing: \(URL(fileURLWithPath: activeExternalEditSession.filePath).lastPathComponent)"
        }
        if let previousApplicationName {
            return "Submit target: \(previousApplicationName)"
        } else {
            return "Open PromptTap from another app to enable Submit"
        }
    }

    init() {
        loadHistory()
        loadTemplates()
        loadReserves()
    }

    @Published var shouldSuppressEditorFocusOnNextSelection = false
    @Published var shouldOpenKeyboardShortcutsWindow = false

    func openKeyboardShortcutsWindow() {
        DispatchQueue.main.async { [weak self] in
            self?.shouldOpenKeyboardShortcutsWindow = true
        }
    }

    private func updatePromptTextFromSelection() {
        guard let lastSelection = selection.first else { return }

        let suppressFocus = shouldSuppressEditorFocusOnNextSelection

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.shouldSuppressEditorFocusOnNextSelection = false

            switch lastSelection {
            case .current:
                self.promptText = self.currentPromptBuffer
            case .history(let id):
                if let entry = self.history.first(where: { $0.id == id }) {
                    self.promptText = entry.text
                }
            case .template(let id):
                if let index = self.templates.firstIndex(where: { $0.id == id }) {
                    self.templateNameBuffer = self.templates[index].name
                    self.promptText = self.templates[index].text
                }
            case .reserve(let id):
                if let index = self.reserves.firstIndex(where: { $0.id == id }) {
                    self.templateNameBuffer = self.reserves[index].name
                    self.promptText = self.reserves[index].text
                }
            case .newTemplate, .newReserve:
                self.templateNameBuffer = ""
                self.promptText = ""
            }

            if !suppressFocus {
                self.focusEditor()
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

    func saveHistoryItem() {
        guard selection.count == 1, case .history(let id) = selection.first else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if let index = self.history.firstIndex(where: { $0.id == id }) {
                if self.history[index].text != self.promptText {
                    self.history[index] = PromptHistory(id: id, text: self.promptText, date: Date())
                    self.saveHistory()
                }
            }
            self.saveRequestID += 1
        }
    }

    func saveTemplate(shouldUpdateSelection: Bool = true) {
        guard selection.count == 1, let first = selection.first else { return }

        let finalName = templateNameBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? generateName(from: promptText)
            : templateNameBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            switch first {
            case .template(let id):
                if let index = self.templates.firstIndex(where: { $0.id == id }) {
                    self.templates[index].name = finalName
                    self.templates[index].text = self.promptText
                    self.templates[index].updatedAt = Date()
                    var template = self.templates[index]
                    self.saveTemplateFile(&template)
                    self.templates[index] = template
                    self.sortTemplates()
                }
            case .newTemplate:
                var newTemplate = PromptTemplate(name: finalName, text: self.promptText)
                self.saveTemplateFile(&newTemplate)
                self.templates.insert(newTemplate, at: 0)
                self.sortTemplates()
                if shouldUpdateSelection {
                    self.selection = [.template(newTemplate.id)]
                }
            default:
                break
            }

            self.templateNameBuffer = finalName
            self.saveRequestID += 1
        }
    }

    func saveReserve(shouldUpdateSelection: Bool = true) {
        guard selection.count == 1, let first = selection.first else { return }

        let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let finalName = generateName(from: text)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            switch first {
            case .reserve(let id):
                if let index = self.reserves.firstIndex(where: { $0.id == id }) {
                    self.reserves[index].name = finalName
                    self.reserves[index].text = self.promptText
                    self.reserves[index].updatedAt = Date()
                    var reserve = self.reserves[index]
                    self.saveReserveFile(&reserve)
                    self.reserves[index] = reserve
                    self.sortReserves()
                }
            case .newReserve:
                var newReserve = PromptReserve(name: finalName, text: text)
                self.saveReserveFile(&newReserve)
                self.reserves.insert(newReserve, at: 0)
                self.sortReserves()
                if shouldUpdateSelection {
                    self.selection = [.reserve(newReserve.id)]
                }
            default:
                break
            }

            self.templateNameBuffer = finalName
            self.saveRequestID += 1
        }
    }

    private func generateName(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled" }

        // Take the first 40 characters, replacing newlines with spaces for the title
        let singleLine = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(singleLine.prefix(40)).trimmingCharacters(in: .whitespaces)
    }

    private var allSidebarItems: [SidebarSelection] {
        var items: [SidebarSelection] = [.current]
        items.append(contentsOf: templates.map { .template($0.id) })
        items.append(contentsOf: reserves.map { .reserve($0.id) })
        items.append(contentsOf: history.map { .history($0.id) })
        return items
    }

    func selectNextSidebarItem() {
        let items = allSidebarItems
        guard !items.isEmpty else { return }

        let currentIndex = items.firstIndex { selection.contains($0) } ?? -1
        let nextIndex = (currentIndex + 1) % items.count
        DispatchQueue.main.async { [weak self] in
            self?.requestSelection([items[nextIndex]])
            self?.focusEditor()
        }
    }

    func selectPreviousSidebarItem() {
        let items = allSidebarItems
        guard !items.isEmpty else { return }

        let currentIndex = items.firstIndex { selection.contains($0) } ?? 0
        let prevIndex = (currentIndex - 1 + items.count) % items.count
        DispatchQueue.main.async { [weak self] in
            self?.requestSelection([items[prevIndex]])
            self?.focusEditor()
        }
    }

    func selectLatestHistory() {
        guard !history.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.requestSelection([.current])
                self?.focusEditor()
            }
            return
        }

        let latestHistoryId = history[0].id
        let nextSelection: Set<SidebarSelection>
        if selection.contains(.history(latestHistoryId)) {
            nextSelection = [.current]
        } else {
            nextSelection = [.history(latestHistoryId)]
        }

        DispatchQueue.main.async { [weak self] in
            self?.requestSelection(nextSelection)
            self?.focusEditor()
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

        requestSelection([.current]) { [weak self] in
            guard let self else { return }
            self.currentPromptBuffer = self.promptText
        }
    }

    func applyTemplate(_ template: PromptTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index].updatedAt = Date()
            saveTemplateFile(&templates[index])
            requestSelection([.current]) { [weak self] in
                guard let self else { return }
                self.currentPromptBuffer = self.templates[index].text
                self.sortTemplates()
            }
        } else {
            requestSelection([.current]) { [weak self] in
                guard let self else { return }
                self.currentPromptBuffer = template.text
            }
        }
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

    func revealHistoryInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([historyURL])
    }

    func applyHistory() {
        requestSelection([.current]) { [weak self] in
            guard let self else { return }
            self.currentPromptBuffer = self.promptText
        }
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

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Update selection: remove deleted templates
            self.selection = self.selection.filter { sel in
                if case .template(let id) = sel {
                    return !idsToDelete.contains(id)
                }
                return true
            }

            if self.selection.isEmpty {
                self.selection = [.current]
            }
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

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Update selection: remove deleted reserves
            self.selection = self.selection.filter { sel in
                if case .reserve(let id) = sel {
                    return !idsToDelete.contains(id)
                }
                return true
            }

            if self.selection.isEmpty {
                self.selection = [.current]
            }
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
        guard application.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }

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

    @Published var shouldOpenMainWindow = false
    @Published var shouldCloseMainWindow = false

    func openFromShortcut(isHotkey: Bool = true) {
        if isHotkey && NSApp.isActive {
            let mainWindows = NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix("main") == true }
            if let window = mainWindows.first(where: { $0.isKeyWindow }) {
                if window.isOnActiveSpace {
                    if previousApplication != nil {
                        returnToTarget()
                    } else {
                        shouldCloseMainWindow = true
                    }
                    return
                }
            }
        }

        let frontmost = NSWorkspace.shared.frontmostApplication
        let targetApp: NSRunningApplication? = {
            if let frontmost, frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
                return frontmost
            }
            return targetHistory.first
        }()

        if isHotkey {
            let buffer = currentPromptBuffer
            let needsClear = !buffer.isEmpty && !history.contains(where: { $0.text == buffer })

            requestSelection([.current]) { [weak self] in
                guard let self else { return }
                if needsClear {
                    self.addToHistory(buffer)
                    self.currentPromptBuffer = ""
                }
            }

            if let targetApp {
                setTarget(targetApp)
            }
        } else if previousApplication == nil {
            if let targetApp {
                setTarget(targetApp)
            }
        }

        if isHotkey {
            AppAnalytics.track(event: .hotkeyTriggered())
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
                window.collectionBehavior.insert(.moveToActiveSpace)
                window.makeKeyAndOrderFront(nil)
            }
        }

        // Use a slight delay to ensure SwiftUI finished updating the view hierarchy
        // before requesting focus on the WebView.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.focusEditor(enterVimInsertMode: isHotkey)
        }
    }

    func newCurrentPrompt() {
        let trimmed = currentPromptBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !history.contains(where: { $0.text == currentPromptBuffer }) {
            addToHistory(currentPromptBuffer)
        }

        requestSelection([.current]) { [weak self] in
            self?.currentPromptBuffer = ""
        }
    }

    func returnToTarget() {
        previousApplication?.activate(options: [.activateAllWindows])
    }

    func openExternalEditSession(_ request: ExternalEditOpenRequest, waitingClient: PromptTapIPCWaitingClient?) {
        let fileURL = URL(fileURLWithPath: request.filePath)
        let parentURL = fileURL.deletingLastPathComponent()

        guard FileManager.default.fileExists(atPath: parentURL.path) else {
            completeExternalEditSession(
                sessionId: request.sessionId,
                waitingClient: waitingClient,
                result: .error,
                exitCode: 1,
                message: "Parent directory does not exist"
            )
            return
        }

        do {
            let exists = FileManager.default.fileExists(atPath: fileURL.path)
            let attributes = exists ? try FileManager.default.attributesOfItem(atPath: fileURL.path) : [:]
            let originalMtime = attributes[.modificationDate] as? Date
            let originalData = exists ? try Data(contentsOf: fileURL) : Data()
            let newline = Self.detectNewline(in: originalData) ?? "\n"
            let originalText: String

            if originalData.isEmpty {
                originalText = ""
            } else if let text = String(data: originalData, encoding: .utf8) {
                originalText = text
            } else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }

            let session = ExternalEditSession(
                sessionId: request.sessionId,
                filePath: fileURL.path,
                originalMtime: originalMtime,
                originalExists: exists,
                originalText: originalText,
                newline: newline,
                completionState: .pending,
                waitingClient: waitingClient
            )

            activeExternalEditSession = session

            let buffer = currentPromptBuffer
            let needsClear = !buffer.isEmpty && !history.contains(where: { $0.text == buffer })

            requestSelection([.current]) { [weak self] in
                guard let self else { return }
                if needsClear {
                    self.addToHistory(buffer)
                }
                self.currentPromptBuffer = originalText
            }
            openFromExternalEdit()
        } catch {
            completeExternalEditSession(
                sessionId: request.sessionId,
                waitingClient: waitingClient,
                result: .error,
                exitCode: 1,
                message: error.localizedDescription
            )
        }
    }

    func completeActiveExternalEditSessionBySaving() {
        guard var session = activeExternalEditSession else {
            return
        }

        do {
            let output = Self.textForWriting(promptText, preserving: session.newline)
            try output.write(to: URL(fileURLWithPath: session.filePath), atomically: true, encoding: .utf8)

            let result: ExternalEditCompletionState = output == session.originalText ? .unchanged : .saved
            session.completionState = result
            activeExternalEditSession = nil
            session.waitingClient?.complete(
                ExternalEditSessionCompleteResponse(sessionId: session.sessionId, result: result, exitCode: 0)
            )
            saveRequestID += 1
            shouldCloseMainWindow = true
        } catch {
            session.completionState = .error
            activeExternalEditSession = nil
            session.waitingClient?.complete(
                ExternalEditSessionCompleteResponse(
                    sessionId: session.sessionId,
                    result: .error,
                    exitCode: 1,
                    message: error.localizedDescription
                )
            )
        }
    }

    func cancelActiveExternalEditSession() {
        guard var session = activeExternalEditSession else {
            return
        }
        session.completionState = .cancelled
        activeExternalEditSession = nil
        session.waitingClient?.complete(
            ExternalEditSessionCompleteResponse(sessionId: session.sessionId, result: .cancelled, exitCode: 1)
        )
    }

    private func completeExternalEditSession(
        sessionId: String,
        waitingClient: PromptTapIPCWaitingClient?,
        result: ExternalEditCompletionState,
        exitCode: Int,
        message: String?
    ) {
        waitingClient?.complete(
            ExternalEditSessionCompleteResponse(sessionId: sessionId, result: result, exitCode: exitCode, message: message)
        )
    }

    private func openFromExternalEdit() {
        NSApp.activate(ignoringOtherApps: true)

        let mainWindows = NSApp.windows.filter { window in
            window.identifier?.rawValue.hasPrefix("main") == true
        }
        if mainWindows.isEmpty {
            shouldOpenMainWindow = true
        } else {
            for window in mainWindows {
                window.collectionBehavior.insert(.moveToActiveSpace)
                window.makeKeyAndOrderFront(nil)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.focusEditor(enterVimInsertMode: false)
        }
    }

    func focusEditor(enterVimInsertMode: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if enterVimInsertMode {
                self.focusRequestID = (self.focusRequestID % 1000) + 1001 // Use 1001+ for insert mode
            } else {
                self.focusRequestID = (self.focusRequestID % 1000) + 1
            }
        }
    }

    func focusList() {
        DispatchQueue.main.async { [weak self] in
            self?.focusListRequestID += 1
        }
    }

    func requestGlobalSearch() {
        DispatchQueue.main.async { [weak self] in
            self?.globalSearchRequestID += 1
        }
    }

    func requestTemplateSearch() {
        DispatchQueue.main.async { [weak self] in
            self?.templateSearchRequestID += 1
        }
    }

    func requestReserveSearch() {
        DispatchQueue.main.async { [weak self] in
            self?.reserveSearchRequestID += 1
        }
    }

    func reservePrompt() {
        let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let finalName = generateName(from: text)

        var newReserve = PromptReserve(name: finalName, text: text)
        saveReserveFile(&newReserve)
        reserves.insert(newReserve, at: 0)
        sortReserves()

        requestSelection([.reserve(newReserve.id)]) { [weak self] in
            self?.currentPromptBuffer = ""
        }
    }

    func historyPrompt() {
        let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let newEntry = PromptHistory(text: promptText)
        history.removeAll { $0.text == promptText }
        history.insert(newEntry, at: 0)
        shrinkHistory(to: settings?.historyLimit ?? 100)
        saveHistory()

        requestSelection([.history(newEntry.id)]) { [weak self] in
            self?.currentPromptBuffer = ""
        }
    }

    func templatePrompt() {
        let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let finalName = generateName(from: text)

        var newTemplate = PromptTemplate(name: finalName, text: text)
        saveTemplateFile(&newTemplate)
        templates.insert(newTemplate, at: 0)
        sortTemplates()

        requestSelection([.template(newTemplate.id)]) { [weak self] in
            self?.currentPromptBuffer = ""
        }
    }

    func applyReserve(_ reserve: PromptReserve) {
        if let index = reserves.firstIndex(where: { $0.id == reserve.id }) {
            let text = reserves[index].text
            reserves[index].updatedAt = Date()
            saveReserveFile(&reserves[index])

            requestSelection([.current]) { [weak self] in
                guard let self else { return }
                self.currentPromptBuffer = text
                self.sortReserves()
            }
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
            DispatchQueue.main.async { [weak self] in
                self?.currentPromptBuffer = ""
                self?.promptText = ""
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isCopying = false
        }
    }

    func submitPrompt() {
        if activeExternalEditSession != nil {
            completeActiveExternalEditSessionBySaving()
            return
        }

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

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if let id = id {
                self.history.removeAll { $0.id == id }
            }
            if let existingIndex = self.history.firstIndex(where: { $0.text == text }) {
                self.history.remove(at: existingIndex)
            }
            let entry = PromptHistory(id: id ?? UUID(), text: text)
            self.history.insert(entry, at: 0)
            self.shrinkHistory(to: self.settings?.historyLimit ?? 100)
            self.saveHistory()

            if id != nil {
                self.selection = [.history(entry.id)]
            }
        }
    }

    private static func detectNewline(in data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        if text.contains("\r\n") {
            return "\r\n"
        }
        if text.contains("\r") {
            return "\r"
        }
        if text.contains("\n") {
            return "\n"
        }
        return nil
    }

    private static func textForWriting(_ text: String, preserving newline: String) -> String {
        guard newline != "\n" else {
            return text
        }

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.replacingOccurrences(of: "\n", with: newline)
    }

    func deleteHistory(at offsets: IndexSet) {
        history.remove(atOffsets: offsets)
        saveHistory()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Clear selection if the deleted item was selected
            self.selection = self.selection.filter { sel in
                if case .history(let id) = sel {
                    return self.history.contains(where: { $0.id == id })
                }
                return true
            }
            if self.selection.isEmpty {
                self.selection = [.current]
            }
        }
    }

    func deleteHistoryItems(_ entries: Set<PromptHistory>) {
        let ids = Set(entries.map { $0.id })
        history.removeAll { ids.contains($0.id) }
        saveHistory()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Clear selection if the deleted item was selected
            self.selection = self.selection.filter { sel in
                if case .history(let id) = sel {
                    return !ids.contains(id)
                }
                return true
            }
            if self.selection.isEmpty {
                self.selection = [.current]
            }
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

        DispatchQueue.main.async { [weak self] in
            self?.selection = [.history(newEntry.id)]
        }
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
        let appSupport = paths[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "PromptTap")
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
        let appSupport = paths[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "PromptTap")
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
        let sanitizedName = encodeTitleForFilename(name)

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
                    let encodedName = components.dropLast().joined(separator: "_")
                    name = decodeTitleFromFilename(encodedName)
                } else {
                    name = decodeTitleFromFilename(nameWithoutExtension)
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
        let sanitizedName = encodeTitleForFilename(name)

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
                    let encodedName = components.dropLast().joined(separator: "_")
                    name = decodeTitleFromFilename(encodedName)
                } else {
                    name = decodeTitleFromFilename(nameWithoutExtension)
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

        // Explicitly clear flags to ensure any pressed modifier is not included.
        keyDown?.flags = []
        keyUp?.flags = []

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func encodeTitleForFilename(_ title: String) -> String {
        // Encode only characters that are illegal or problematic in filenames.
        // On macOS, "/" is the primary illegal character. ":" is also avoided for compatibility.
        let allowed = CharacterSet(charactersIn: "/:").inverted
        return title.addingPercentEncoding(withAllowedCharacters: allowed) ?? title
    }

    private func decodeTitleFromFilename(_ filename: String) -> String {
        return filename.removingPercentEncoding ?? filename
    }
}
