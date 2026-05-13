//
//  ContentView.swift
//  PromptTap
//
//  Created by Yuta Tokoro on 2026/05/06.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: PromptTapModel
    @EnvironmentObject private var settings: AppSettings

    @State private var entriesToDelete: Set<PromptHistory> = []
    @State private var showingDeleteConfirmation = false
    @State private var templatesToDelete: Set<PromptTemplate> = []
    @State private var showingTemplateDeleteConfirmation = false
    @State private var reservesToDelete: Set<PromptReserve> = []
    @State private var showingReserveDeleteConfirmation = false
    @State private var showingTemplateSearch = false
    @State private var templateSearchQuery = ""
    @State private var templateSearchSelectedIndex = 0
    @State private var showingReserveSearch = false
    @State private var reserveSearchQuery = ""
    @State private var reserveSearchSelectedIndex = 0
    @FocusState private var isListFocused: Bool
    @State private var showingGlobalSearch = false
    @State private var globalSearchQuery = ""
    @State private var globalSearchSelectedIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
            } detail: {
                editorPane
            }

            Divider()

            bottomToolbar
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear {
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
                window.collectionBehavior.insert(.moveToActiveSpace)
            }
        }
        .confirmationDialog(
            entriesToDelete.count > 1
                ? "Are you sure you want to delete \(entriesToDelete.count) history items?"
                : "Are you sure you want to delete this history item?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                model.deleteHistoryItems(entriesToDelete)
                entriesToDelete = []
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                entriesToDelete = []
            }
        } message: {
            if entriesToDelete.count == 1, let entry = entriesToDelete.first {
                Text(entry.text)
                    .lineLimit(2)
            }
        }
        .confirmationDialog(
            templatesToDelete.count > 1
                ? "Are you sure you want to delete \(templatesToDelete.count) templates?"
                : "Are you sure you want to delete this template?",
            isPresented: $showingTemplateDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                model.deleteTemplates(templatesToDelete)
                templatesToDelete = []
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                templatesToDelete = []
            }
        }
        .confirmationDialog(
            reservesToDelete.count > 1
                ? "Are you sure you want to delete \(reservesToDelete.count) reserves?"
                : "Are you sure you want to delete this reserve?",
            isPresented: $showingReserveDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                model.deleteReserves(reservesToDelete)
                reservesToDelete = []
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                reservesToDelete = []
            }
        } message: {
            if templatesToDelete.count == 1, let template = templatesToDelete.first {
                Text(template.name)
            }
        }
        .onChange(of: model.focusListRequestID) {
            isListFocused = true
        }
        .onChange(of: model.globalSearchRequestID) {
            globalSearchQuery = ""
            globalSearchSelectedIndex = 0
            showingGlobalSearch = true
        }
        .onChange(of: model.templateSearchRequestID) {
            templateSearchQuery = ""
            templateSearchSelectedIndex = 0
            showingTemplateSearch = true
        }
        .onChange(of: model.reserveSearchRequestID) {
            reserveSearchQuery = ""
            reserveSearchSelectedIndex = 0
            showingReserveSearch = true
        }
        .sheet(isPresented: $showingGlobalSearch) {
            GlobalSearchPanel(
                templates: model.templates,
                reserves: model.reserves,
                history: model.history,
                query: $globalSearchQuery,
                selectedIndex: $globalSearchSelectedIndex,
                onSelect: { result in
                    switch result {
                    case .template(let template):
                        model.applyTemplate(template)
                    case .reserve(let reserve):
                        model.applyReserve(reserve)
                    case .history(let entry):
                        model.selection = [.history(entry.id)]
                    }
                    showingGlobalSearch = false
                },
                onCancel: {
                    showingGlobalSearch = false
                }
            )
            .frame(width: 540, height: 420)
        }
        .sheet(isPresented: $showingTemplateSearch) {
            TemplateSearchPanel(
                templates: model.templates,
                query: $templateSearchQuery,
                selectedIndex: $templateSearchSelectedIndex,
                onSelect: { template in
                    model.applyTemplate(template)
                    showingTemplateSearch = false
                },
                onCancel: {
                    showingTemplateSearch = false
                }
            )
            .frame(width: 540, height: 420)
        }
        .sheet(isPresented: $showingReserveSearch) {
            ReserveSearchPanel(
                reserves: model.reserves,
                query: $reserveSearchQuery,
                selectedIndex: $reserveSearchSelectedIndex,
                onSelect: { reserve in
                    model.applyReserve(reserve)
                    showingReserveSearch = false
                },
                onCancel: {
                    showingReserveSearch = false
                }
            )
            .frame(width: 540, height: 420)
        }
        .background {
            Button("") {
                model.requestGlobalSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)

            Button("") {
                model.focusList()
            }
            .keyboardShortcut("l", modifiers: .command)
            .opacity(0)

            Button("") {
                model.focusEditor()
            }
            .keyboardShortcut("e", modifiers: .command)
            .opacity(0)

            Button("") {
                model.selectNextSidebarItem()
            }
            .keyboardShortcut("n", modifiers: .command)
            .opacity(0)

            Button("") {
                model.selectPreviousSidebarItem()
            }
            .keyboardShortcut("p", modifiers: .command)
            .opacity(0)

            Button("") {
                model.selectLatestHistory()
            }
            .keyboardShortcut("h", modifiers: .command)
            .opacity(0)

            if !settings.usesVimKeyBindings {
                Button("") {
                    model.returnToTarget()
                }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
            }
        }
    }

    private var sidebar: some View {
        List(selection: $model.selection) {
            Section("Current") {
                Label("Current Prompt", systemImage: "text.alignleft")
                    .tag(SidebarSelection.current)
            }

            Section {
                ForEach(model.templates) { template in
                    TemplateRow(template: template)
                        .tag(SidebarSelection.template(template.id))
                        .contextMenu {
                            Button {
                                model.selection = [.template(template.id)]
                                model.applyTemplate()
                            } label: {
                                Label("Prompt", systemImage: "arrow.right.square")
                            }

                            Divider()

                            Button {
                                model.revealTemplateInFinder(template)
                            } label: {
                                Label("Show in Finder", systemImage: "folder")
                            }

                            Divider()

                            Button(role: .destructive) {
                                templatesToDelete = [template]
                                showingTemplateDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onDelete { offsets in
                    templatesToDelete = Set(offsets.map { model.templates[$0] })
                    showingTemplateDeleteConfirmation = true
                }
            } header: {
                HStack(spacing: 8) {
                    Text("Templates")
                    Spacer()
                    Button {
                        model.requestTemplateSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .shortcutHelp("Search Templates", shortcut: "⌘T", placement: .below)
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.selection = [.newTemplate]
                        model.focusEditor()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("Add Template")
                }
            }

            Section {
                ForEach(model.reserves) { reserve in
                    Text(reserve.name)
                        .tag(SidebarSelection.reserve(reserve.id))
                        .contextMenu {
                            Button {
                                model.revealReserveInFinder(reserve)
                            } label: {
                                Label("Show in Finder", systemImage: "folder")
                            }

                            Divider()

                            Button(role: .destructive) {
                                reservesToDelete = [reserve]
                                showingReserveDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onDelete { offsets in
                    reservesToDelete = Set(offsets.map { model.reserves[$0] })
                    showingReserveDeleteConfirmation = true
                }
            } header: {
                HStack(spacing: 8) {
                    Text("Reserves")
                    Spacer()
                    Button {
                        model.requestReserveSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .shortcutHelp("Search Reserves", shortcut: "⌘R", placement: .below)
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.selection = [.newReserve]
                        model.focusEditor()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("Add Reserve")
                }
            }

            Section {
                ForEach(model.history) { entry in
                    HistoryRow(
                        entry: entry,
                        isEditing: settings.historyEditingMode,
                        onDelete: {
                            entriesToDelete = [entry]
                            showingDeleteConfirmation = true
                        }
                    )
                    .tag(SidebarSelection.history(entry.id))
                    .contextMenu {
                        let selectedHistory = model.selection.compactMap { sel -> PromptHistory? in
                            if case .history(let id) = sel {
                                return model.history.first(where: { $0.id == id })
                            }
                            return nil
                        }

                        if selectedHistory.count > 1 && selectedHistory.contains(where: { $0.id == entry.id }) {
                            Button {
                                model.mergeHistoryItems(selectedHistory)
                            } label: {
                                Label("Merge", systemImage: "plus.square.fill.on.square.fill")
                            }

                            Divider()
                        }

                        Button(role: .destructive) {
                            if !selectedHistory.isEmpty && selectedHistory.contains(where: { $0.id == entry.id }) {
                                entriesToDelete = Set(selectedHistory)
                            } else {
                                entriesToDelete = [entry]
                            }
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in
                    entriesToDelete = Set(offsets.map { model.history[$0] })
                    showingDeleteConfirmation = true
                }
            } header: {
                HStack {
                    Text("History")
                    Spacer()
                }
            }
        }
        .focused($isListFocused)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if NSEvent.modifierFlags.contains(.command) {
                        model.shouldSuppressEditorFocusOnNextSelection = true
                    }
                }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    model.shouldSuppressEditorFocusOnNextSelection = true
                }
        )
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .onDeleteCommand {
            let selectedHistory = model.selection.compactMap { sel -> PromptHistory? in
                if case .history(let id) = sel {
                    return model.history.first(where: { $0.id == id })
                }
                return nil
            }
            if !selectedHistory.isEmpty {
                entriesToDelete = Set(selectedHistory)
                showingDeleteConfirmation = true
            }

            let selectedTemplates = model.selection.compactMap { sel -> PromptTemplate? in
                if case .template(let id) = sel {
                    return model.templates.first(where: { $0.id == id })
                }
                return nil
            }
            if !selectedTemplates.isEmpty {
                templatesToDelete = Set(selectedTemplates)
                showingTemplateDeleteConfirmation = true
            }

            let selectedReserves = model.selection.compactMap { sel -> PromptReserve? in
                if case .reserve(let id) = sel {
                    return model.reserves.first(where: { $0.id == id })
                }
                return nil
            }
            if !selectedReserves.isEmpty {
                reservesToDelete = Set(selectedReserves)
                showingReserveDeleteConfirmation = true
            }
        }
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            HStack {
                if model.isTemplateSelected {
                    TextField("Template Name", text: $model.templateNameBuffer)
                        .textFieldStyle(.plain)
                        .font(.headline)
                } else if model.isReserveSelected {
                    TextField("Reserve Name", text: $model.templateNameBuffer)
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .disabled(true)
                } else if let lastSelection = model.selection.first,
                   case .history(let id) = lastSelection,
                   let entry = model.history.first(where: { $0.id == id }) {
                    Text(entry.date.formatted(date: .numeric, time: .shortened))
                        .font(.headline)
                } else {
                    Text("Current Prompt")
                        .font(.headline)
                }
                Spacer()
                if model.isTemplateSelected {
                    HStack(spacing: 8) {
                        let currentTemplate = model.templates.first { template in
                            if case .template(let id) = model.selection.first {
                                return template.id == id
                            }
                            return false
                        }

                        Button {
                            if let currentTemplate {
                                model.revealTemplateInFinder(currentTemplate)
                            }
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.bordered)
                        .disabled(currentTemplate == nil)
                        .help("Show in Finder")

                        Button {
                            if let currentTemplate {
                                templatesToDelete = [currentTemplate]
                                showingTemplateDeleteConfirmation = true
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                        .disabled(currentTemplate == nil)
                        .help("Delete Template")

                        Divider()
                            .frame(height: 16)

                        Button {
                            model.applyTemplate()
                        } label: {
                            Label("Prompt", systemImage: "arrow.right.square")
                                .shortcutHelp("Prompt with this template", shortcut: "⌘⇧P")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("p", modifiers: [.command, .shift])
                        .disabled(model.promptText.isEmpty || (model.selection.first != .newTemplate && currentTemplate == nil))
                        .fixedSize()

                        Button {
                            model.saveTemplate()
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                                .shortcutHelp("Save this template", shortcut: "⌘⇧S")
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                        .disabled(model.promptText.isEmpty)
                        .fixedSize()
                    }
                    .padding(.trailing, 8)
                } else if model.isReserveSelected {
                    HStack(spacing: 8) {
                        let currentReserve = model.reserves.first { reserve in
                            if case .reserve(let id) = model.selection.first {
                                return reserve.id == id
                            }
                            return false
                        }

                        Button {
                            if let currentReserve {
                                model.revealReserveInFinder(currentReserve)
                            }
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.bordered)
                        .disabled(currentReserve == nil)
                        .help("Show in Finder")

                        Button {
                            if let currentReserve {
                                reservesToDelete = [currentReserve]
                                showingReserveDeleteConfirmation = true
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                        .disabled(currentReserve == nil)
                        .help("Delete Reserve")

                        Divider()
                            .frame(height: 16)

                        Button {
                            if let currentReserve {
                                model.applyReserve(currentReserve)
                            }
                        } label: {
                            Label("Prompt", systemImage: "arrow.right.square")
                                .shortcutHelp("Prompt with this reserve", shortcut: "⌘⇧P")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("p", modifiers: [.command, .shift])
                        .disabled(model.promptText.isEmpty || currentReserve == nil)
                        .fixedSize()

                        Button {
                            model.saveReserve()
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                                .shortcutHelp("Save this reserve", shortcut: "⌘⇧S")
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                        .disabled(model.promptText.isEmpty)
                        .fixedSize()
                    }
                    .padding(.trailing, 8)
                }
                if settings.usesVimKeyBindings {
                    Label("Vim", systemImage: "keyboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)

            WebPromptEditor(
                text: Binding(
                    get: { model.promptText },
                    set: { model.updateTextFromEditor($0) }
                ),
                isSelectionEmpty: $model.isEditorSelectionEmpty,
                usesVimKeyBindings: settings.usesVimKeyBindings,
                lineWrapping: settings.lineWrapping,
                focusRequestID: model.focusRequestID,
                onSubmit: model.isTemplateSelected ? model.saveTemplate : model.submitPrompt,
                onCopyAll: model.copyPrompt,
                onSearchTemplates: model.requestTemplateSearch
            )
        }
    }

    private var bottomToolbar: some View {
        HStack(spacing: 10) {
            Button {
                model.submitPrompt()
            } label: {
                HStack(spacing: 6) {
                    if model.isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "paperplane")
                    }
                    Text("Submit")
                }
                .shortcutHelp(
                    model.canSubmit ? "Return to the previous app and paste" : "No previous app is known yet",
                    shortcut: "⌘S"
                )
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!model.canSubmit || model.isSubmitting)

            Button {
                model.copyPrompt()
            } label: {
                HStack(spacing: 6) {
                    if model.isCopying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "doc.on.doc")
                    }
                    Text("Copy")
                }
                .shortcutHelp(
                    model.isEditorSelectionEmpty ? "Copy the full prompt" : "Use the editor selection copy",
                    shortcut: "⌘C"
                )
            }
            .disabled(!model.isEditorSelectionEmpty || model.isCopying || model.promptText.isEmpty)

            Button {
                model.templatePrompt()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                    Text("Template")
                }
                .shortcutHelp("Save the current prompt as a template", shortcut: "⌘⇧T")
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(model.promptText.isEmpty || model.isTemplateSelected)

            Button {
                model.reservePrompt()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "archivebox")
                    Text("Reserve")
                }
                .shortcutHelp("Save the current prompt as a reserve", shortcut: "⌘⇧R")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model.promptText.isEmpty || model.isReserveSelected)

            Spacer()

            if !model.targetHistory.filter({ $0.localizedName != nil && $0.localizedName != "Unknown App" }).isEmpty {
                Menu {
                    ForEach(model.targetHistory.filter({ $0.localizedName != nil && $0.localizedName != "Unknown App" }), id: \.bundleIdentifier) { app in
                        Button {
                            model.setTarget(app)
                        } label: {
                            HStack {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                }
                                Text(app.localizedName ?? "Unknown App")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if let icon = model.previousApplicationIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        Text(model.statusText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Text(model.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bar)
    }
}

private struct ReserveSearchPanel: View {
    let reserves: [PromptReserve]
    @Binding var query: String
    @Binding var selectedIndex: Int
    let onSelect: (PromptReserve) -> Void
    let onCancel: () -> Void

    @FocusState private var isSearchFocused: Bool

    private var candidates: [ReserveSearchCandidate] {
        ReserveSearchCandidate.search(query: query, in: reserves)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search reserves", text: $query)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    Text(candidateCountText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(14)

            Divider()

            if candidates.isEmpty {
                ContentUnavailableView("No Reserves", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                                ReserveSearchRow(
                                    candidate: candidate,
                                    isSelected: index == selectedIndex
                                )
                                .id(candidate.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedIndex = index
                                    onSelect(candidate.reserve)
                                }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selectedIndex) {
                        guard candidates.indices.contains(selectedIndex) else { return }
                        proxy.scrollTo(candidates[selectedIndex].id, anchor: .center)
                    }
                }
            }
        }
        .background(.regularMaterial)
        .onAppear {
            selectedIndex = clampedSelectedIndex
            isSearchFocused = true
        }
        .onChange(of: query) {
            selectedIndex = 0
        }
        .onChange(of: reserves) {
            selectedIndex = clampedSelectedIndex
        }
        .background(
            ReserveSearchKeyMonitor(
                onMoveUp: moveUp,
                onMoveDown: moveDown,
                onSelect: selectCurrentCandidate,
                onCancel: onCancel
            )
        )
    }

    private var clampedSelectedIndex: Int {
        guard !candidates.isEmpty else { return 0 }
        return min(max(selectedIndex, 0), candidates.count - 1)
    }

    private var candidateCountText: String {
        candidates.count == 1 ? "1 reserve" : "\(candidates.count) reserves"
    }

    private func moveUp() {
        guard !candidates.isEmpty else { return }
        selectedIndex = selectedIndex > 0 ? selectedIndex - 1 : candidates.count - 1
    }

    private func moveDown() {
        guard !candidates.isEmpty else { return }
        selectedIndex = selectedIndex < candidates.count - 1 ? selectedIndex + 1 : 0
    }

    private func selectCurrentCandidate() {
        guard candidates.indices.contains(selectedIndex) else { return }
        onSelect(candidates[selectedIndex].reserve)
    }
}

private struct ReserveSearchCandidate: Identifiable {
    let reserve: PromptReserve
    let matchRank: Int

    var id: UUID { reserve.id }

    static func search(query: String, in reserves: [PromptReserve]) -> [ReserveSearchCandidate] {
        let needle = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))

        return reserves.compactMap { reserve in
            let name = normalized(reserve.name)
            let text = normalized(reserve.text)
            let rank: Int?

            if needle.isEmpty {
                rank = 3
            } else if name.hasPrefix(needle) {
                rank = 0
            } else if name.contains(needle) {
                rank = 1
            } else if text.contains(needle) {
                rank = 2
            } else {
                rank = nil
            }

            return rank.map { ReserveSearchCandidate(reserve: reserve, matchRank: $0) }
        }
        .sorted { lhs, rhs in
            if lhs.matchRank != rhs.matchRank {
                return lhs.matchRank < rhs.matchRank
            }
            return lhs.reserve.updatedAt > rhs.reserve.updatedAt
        }
    }

    private static func normalized(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}

private struct ReserveSearchRow: View {
    let candidate: ReserveSearchCandidate
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(candidate.reserve.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(candidate.reserve.updatedAt.formatted(date: .numeric, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }

                Text(candidate.reserve.text)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .foregroundStyle(isSelected ? .white : .primary)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.blue)
            }
        }
    }

    private var iconName: String {
        switch candidate.matchRank {
        case 0: "textformat.abc"
        case 1: "text.magnifyingglass"
        case 2: "doc.text.magnifyingglass"
        default: "clock"
        }
    }
}

private struct ReserveSearchKeyMonitor: NSViewRepresentable {
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onSelect: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var parent: ReserveSearchKeyMonitor
        private var monitor: Any?

        init(_ parent: ReserveSearchKeyMonitor) {
            self.parent = parent
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let key = event.charactersIgnoringModifiers?.lowercased()

            if modifiers == [] {
                switch event.keyCode {
                case 36:
                    guard !isComposingText() else {
                        return event
                    }
                    parent.onSelect()
                    return nil
                case 53:
                    parent.onCancel()
                    return nil
                case 125:
                    parent.onMoveDown()
                    return nil
                case 126:
                    parent.onMoveUp()
                    return nil
                default:
                    break
                }
            }

            if modifiers == .command || modifiers == .control {
                switch key {
                case "n":
                    parent.onMoveDown()
                    return nil
                case "p":
                    parent.onMoveUp()
                    return nil
                default:
                    break
                }
            }

            return event
        }

        private func isComposingText() -> Bool {
            guard let firstResponder = NSApp.keyWindow?.firstResponder else {
                return false
            }

            if let textView = firstResponder as? NSTextView {
                return textView.hasMarkedText()
            }

            if let textInputClient = firstResponder as? NSTextInputClient {
                return textInputClient.hasMarkedText()
            }

            return false
        }
    }
}

private extension View {
    func shortcutHelp(
        _ message: String,
        shortcut: String,
        placement: ShortcutHelpPlacement = .above
    ) -> some View {
        modifier(ShortcutHelpModifier(message: message, shortcut: shortcut, placement: placement))
    }
}

private enum ShortcutHelpPlacement {
    case above
    case below
}

private struct ShortcutHelpModifier: ViewModifier {
    let message: String
    let shortcut: String
    let placement: ShortcutHelpPlacement

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering = $0 }
            .overlay(alignment: placement.alignment) {
                if isHovering {
                    ShortcutHelpTip(message: message, shortcut: shortcut)
                        .fixedSize()
                        .offset(y: placement.yOffset)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: placement.scaleAnchor)))
                        .allowsHitTesting(false)
                        .zIndex(1)
                }
            }
            .animation(.easeOut(duration: 0.08), value: isHovering)
    }
}

private extension ShortcutHelpPlacement {
    var alignment: Alignment {
        switch self {
        case .above:
            .top
        case .below:
            .bottom
        }
    }

    var yOffset: CGFloat {
        switch self {
        case .above:
            -38
        case .below:
            38
        }
    }

    var scaleAnchor: UnitPoint {
        switch self {
        case .above:
            .bottom
        case .below:
            .top
        }
    }
}

private struct ShortcutHelpTip: View {
    let message: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)

            Text(shortcut)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor, in: Capsule())
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}

private struct TemplateSearchPanel: View {
    let templates: [PromptTemplate]
    @Binding var query: String
    @Binding var selectedIndex: Int
    let onSelect: (PromptTemplate) -> Void
    let onCancel: () -> Void

    @FocusState private var isSearchFocused: Bool

    private var candidates: [TemplateSearchCandidate] {
        TemplateSearchCandidate.search(query: query, in: templates)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search templates", text: $query)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    Text(candidateCountText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(14)

            Divider()

            if candidates.isEmpty {
                ContentUnavailableView("No Templates", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                                TemplateSearchRow(
                                    candidate: candidate,
                                    isSelected: index == selectedIndex
                                )
                                .id(candidate.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedIndex = index
                                    onSelect(candidate.template)
                                }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selectedIndex) {
                        guard candidates.indices.contains(selectedIndex) else { return }
                        proxy.scrollTo(candidates[selectedIndex].id, anchor: .center)
                    }
                }
            }
        }
        .background(.regularMaterial)
        .onAppear {
            selectedIndex = clampedSelectedIndex
            isSearchFocused = true
        }
        .onChange(of: query) {
            selectedIndex = 0
        }
        .onChange(of: templates) {
            selectedIndex = clampedSelectedIndex
        }
        .background(
            TemplateSearchKeyMonitor(
                onMoveUp: moveUp,
                onMoveDown: moveDown,
                onSelect: selectCurrentCandidate,
                onCancel: onCancel
            )
        )
    }

    private var clampedSelectedIndex: Int {
        guard !candidates.isEmpty else { return 0 }
        return min(max(selectedIndex, 0), candidates.count - 1)
    }

    private var candidateCountText: String {
        candidates.count == 1 ? "1 template" : "\(candidates.count) templates"
    }

    private func moveUp() {
        guard !candidates.isEmpty else { return }
        selectedIndex = selectedIndex > 0 ? selectedIndex - 1 : candidates.count - 1
    }

    private func moveDown() {
        guard !candidates.isEmpty else { return }
        selectedIndex = selectedIndex < candidates.count - 1 ? selectedIndex + 1 : 0
    }

    private func selectCurrentCandidate() {
        guard candidates.indices.contains(selectedIndex) else { return }
        onSelect(candidates[selectedIndex].template)
    }
}

private struct TemplateSearchCandidate: Identifiable {
    let template: PromptTemplate
    let matchRank: Int

    var id: UUID { template.id }

    static func search(query: String, in templates: [PromptTemplate]) -> [TemplateSearchCandidate] {
        let needle = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))

        return templates.compactMap { template in
            let name = normalized(template.name)
            let text = normalized(template.text)
            let rank: Int?

            if needle.isEmpty {
                rank = 3
            } else if name.hasPrefix(needle) {
                rank = 0
            } else if name.contains(needle) {
                rank = 1
            } else if text.contains(needle) {
                rank = 2
            } else {
                rank = nil
            }

            return rank.map { TemplateSearchCandidate(template: template, matchRank: $0) }
        }
        .sorted { lhs, rhs in
            if lhs.matchRank != rhs.matchRank {
                return lhs.matchRank < rhs.matchRank
            }
            return lhs.template.updatedAt > rhs.template.updatedAt
        }
    }

    private static func normalized(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}

private struct TemplateSearchRow: View {
    let candidate: TemplateSearchCandidate
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(candidate.template.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(candidate.template.updatedAt.formatted(date: .numeric, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }

                Text(candidate.template.text)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .foregroundStyle(isSelected ? .white : .primary)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.blue)
            }
        }
    }

    private var iconName: String {
        switch candidate.matchRank {
        case 0: "textformat.abc"
        case 1: "text.magnifyingglass"
        case 2: "doc.text.magnifyingglass"
        default: "clock"
        }
    }
}

private struct TemplateSearchKeyMonitor: NSViewRepresentable {
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onSelect: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var parent: TemplateSearchKeyMonitor
        private var monitor: Any?

        init(_ parent: TemplateSearchKeyMonitor) {
            self.parent = parent
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let key = event.charactersIgnoringModifiers?.lowercased()

            if modifiers == [] {
                switch event.keyCode {
                case 36:
                    guard !isComposingText() else {
                        return event
                    }
                    parent.onSelect()
                    return nil
                case 53:
                    parent.onCancel()
                    return nil
                case 125:
                    parent.onMoveDown()
                    return nil
                case 126:
                    parent.onMoveUp()
                    return nil
                default:
                    break
                }
            }

            if modifiers == .command || modifiers == .control {
                switch key {
                case "n":
                    parent.onMoveDown()
                    return nil
                case "p":
                    parent.onMoveUp()
                    return nil
                default:
                    break
                }
            }

            return event
        }

        private func isComposingText() -> Bool {
            guard let firstResponder = NSApp.keyWindow?.firstResponder else {
                return false
            }

            if let textView = firstResponder as? NSTextView {
                return textView.hasMarkedText()
            }

            if let textInputClient = firstResponder as? NSTextInputClient {
                return textInputClient.hasMarkedText()
            }

            return false
        }
    }
}

struct TemplateRow: View {
    let template: PromptTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(template.name)
                .font(.subheadline)
            Text(template.text)
                .lineLimit(1)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct HistoryRow: View {
    let entry: PromptHistory
    let isEditing: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .lineLimit(2)
                    .font(.subheadline)
                Text(entry.date.formatted(date: .numeric, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if isEditing {
                Spacer()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Global Search

private enum GlobalSearchResult: Identifiable {
    case template(PromptTemplate)
    case reserve(PromptReserve)
    case history(PromptHistory)

    var id: UUID {
        switch self {
        case .template(let t): t.id
        case .reserve(let r): r.id
        case .history(let h): h.id
        }
    }

    var name: String {
        switch self {
        case .template(let t): t.name
        case .reserve(let r): r.name
        case .history(let h): h.date.formatted(date: .numeric, time: .shortened)
        }
    }

    var text: String {
        switch self {
        case .template(let t): t.text
        case .reserve(let r): r.text
        case .history(let h): h.text
        }
    }

    var date: Date {
        switch self {
        case .template(let t): t.updatedAt
        case .reserve(let r): r.updatedAt
        case .history(let h): h.date
        }
    }

    var sectionTitle: String {
        switch self {
        case .template: "Templates"
        case .reserve: "Reserves"
        case .history: "History"
        }
    }
}

private struct GlobalSearchPanel: View {
    let templates: [PromptTemplate]
    let reserves: [PromptReserve]
    let history: [PromptHistory]
    @Binding var query: String
    @Binding var selectedIndex: Int
    let onSelect: (GlobalSearchResult) -> Void
    let onCancel: () -> Void

    @FocusState private var isSearchFocused: Bool

    private var candidates: [GlobalSearchCandidate] {
        GlobalSearchCandidate.search(query: query, templates: templates, reserves: reserves, history: history)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search templates, reserves, and history", text: $query)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    Text(candidateCountText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(14)

            Divider()

            if candidates.isEmpty {
                ContentUnavailableView("No Results", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            let sections = Dictionary(grouping: candidates.enumerated()) { $0.element.result.sectionTitle }
                            let sortedSectionTitles = ["Templates", "Reserves", "History"].filter { sections.keys.contains($0) }

                            ForEach(sortedSectionTitles, id: \.self) { sectionTitle in
                                Section(header: sectionHeader(sectionTitle)) {
                                    ForEach(sections[sectionTitle]!, id: \.element.id) { index, candidate in
                                        GlobalSearchRow(
                                            candidate: candidate,
                                            isSelected: index == selectedIndex
                                        )
                                        .id(candidate.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedIndex = index
                                            onSelect(candidate.result)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selectedIndex) {
                        guard candidates.indices.contains(selectedIndex) else { return }
                        proxy.scrollTo(candidates[selectedIndex].id, anchor: .center)
                    }
                }
            }
        }
        .background(.regularMaterial)
        .onAppear {
            selectedIndex = clampedSelectedIndex
            isSearchFocused = true
        }
        .onChange(of: query) {
            selectedIndex = 0
        }
        .background(
            GlobalSearchKeyMonitor(
                onMoveUp: moveUp,
                onMoveDown: moveDown,
                onSelect: selectCurrentCandidate,
                onCancel: onCancel
            )
        )
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            Spacer()
        }
        .background(.regularMaterial)
    }

    private var clampedSelectedIndex: Int {
        guard !candidates.isEmpty else { return 0 }
        return min(max(selectedIndex, 0), candidates.count - 1)
    }

    private var candidateCountText: String {
        candidates.count == 1 ? "1 result" : "\(candidates.count) results"
    }

    private func moveUp() {
        guard !candidates.isEmpty else { return }
        selectedIndex = selectedIndex > 0 ? selectedIndex - 1 : candidates.count - 1
    }

    private func moveDown() {
        guard !candidates.isEmpty else { return }
        selectedIndex = selectedIndex < candidates.count - 1 ? selectedIndex + 1 : 0
    }

    private func selectCurrentCandidate() {
        guard candidates.indices.contains(selectedIndex) else { return }
        onSelect(candidates[selectedIndex].result)
    }
}

private struct GlobalSearchCandidate: Identifiable {
    let result: GlobalSearchResult
    let matchRank: Int

    var id: UUID { result.id }

    static func search(query: String, templates: [PromptTemplate], reserves: [PromptReserve], history: [PromptHistory]) -> [GlobalSearchCandidate] {
        let needle = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))

        var allCandidates: [GlobalSearchCandidate] = []

        allCandidates.append(contentsOf: templates.compactMap { template in
            rank(needle: needle, name: template.name, text: template.text).map { GlobalSearchCandidate(result: .template(template), matchRank: $0) }
        })

        allCandidates.append(contentsOf: reserves.compactMap { reserve in
            rank(needle: needle, name: reserve.name, text: reserve.text).map { GlobalSearchCandidate(result: .reserve(reserve), matchRank: $0) }
        })

        allCandidates.append(contentsOf: history.compactMap { entry in
            rank(needle: needle, name: "", text: entry.text).map { GlobalSearchCandidate(result: .history(entry), matchRank: $0) }
        })

        return allCandidates.sorted { lhs, rhs in
            let sectionOrder = ["Templates": 0, "Reserves": 1, "History": 2]
            let lhsSection = sectionOrder[lhs.result.sectionTitle] ?? 99
            let rhsSection = sectionOrder[rhs.result.sectionTitle] ?? 99

            if lhsSection != rhsSection {
                return lhsSection < rhsSection
            }

            if lhs.matchRank != rhs.matchRank {
                return lhs.matchRank < rhs.matchRank
            }
            return lhs.result.date > rhs.result.date
        }
    }

    private static func rank(needle: String, name: String, text: String) -> Int? {
        let nName = normalized(name)
        let nText = normalized(text)

        if needle.isEmpty {
            return 3
        } else if !name.isEmpty && nName.hasPrefix(needle) {
            return 0
        } else if !name.isEmpty && nName.contains(needle) {
            return 1
        } else if nText.contains(needle) {
            return 2
        } else {
            return nil
        }
    }

    private static func normalized(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}

private struct GlobalSearchRow: View {
    let candidate: GlobalSearchCandidate
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(candidate.result.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(candidate.result.date.formatted(date: .numeric, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }

                Text(candidate.result.text)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .foregroundStyle(isSelected ? .white : .primary)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.blue)
            }
        }
    }

    private var iconName: String {
        switch candidate.matchRank {
        case 0: "textformat.abc"
        case 1: "text.magnifyingglass"
        case 2: "doc.text.magnifyingglass"
        default: "clock"
        }
    }
}

private struct GlobalSearchKeyMonitor: NSViewRepresentable {
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onSelect: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var parent: GlobalSearchKeyMonitor
        private var monitor: Any?

        init(_ parent: GlobalSearchKeyMonitor) {
            self.parent = parent
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let key = event.charactersIgnoringModifiers?.lowercased()

            if modifiers == [] {
                switch event.keyCode {
                case 36:
                    guard !isComposingText() else {
                        return event
                    }
                    parent.onSelect()
                    return nil
                case 53:
                    parent.onCancel()
                    return nil
                case 125:
                    parent.onMoveDown()
                    return nil
                case 126:
                    parent.onMoveUp()
                    return nil
                default:
                    break
                }
            }

            if modifiers == .command || modifiers == .control {
                switch key {
                case "n":
                    parent.onMoveDown()
                    return nil
                case "p":
                    parent.onMoveUp()
                    return nil
                default:
                    break
                }
            }

            return event
        }

        private func isComposingText() -> Bool {
            guard let firstResponder = NSApp.keyWindow?.firstResponder else {
                return false
            }

            if let textView = firstResponder as? NSTextView {
                return textView.hasMarkedText()
            }

            if let textInputClient = firstResponder as? NSTextInputClient {
                return textInputClient.hasMarkedText()
            }

            return false
        }
    }
}
