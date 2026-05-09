//
//  ContentView.swift
//  PromptFlow
//
//  Created by Yuta Tokoro on 2026/05/06.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: PromptFlowModel
    @EnvironmentObject private var settings: AppSettings

    @State private var entriesToDelete: Set<PromptHistory> = []
    @State private var showingDeleteConfirmation = false
    @State private var templatesToDelete: Set<PromptTemplate> = []
    @State private var showingTemplateDeleteConfirmation = false
    @FocusState private var isListFocused: Bool

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
                for template in templatesToDelete {
                    model.deleteTemplate(template)
                }
                templatesToDelete = []
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                templatesToDelete = []
            }
        } message: {
            if templatesToDelete.count == 1, let template = templatesToDelete.first {
                Text(template.name)
            }
        }
        .onChange(of: model.focusListRequestID) {
            isListFocused = true
        }
        .background {
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
                HStack {
                    Text("Templates")
                    Spacer()
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
        }
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            HStack {
                if model.isTemplateSelected {
                    TextField("Template Name", text: $model.templateNameBuffer)
                        .textFieldStyle(.plain)
                        .font(.headline)
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
                        }
                        .keyboardShortcut("p", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(model.promptText.isEmpty || (model.selection.first != .newTemplate && currentTemplate == nil))
                        .fixedSize()

                        Button {
                            model.saveTemplate()
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
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
                onCopyAll: model.copyPrompt
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
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!model.canSubmit || model.isSubmitting)
            .help(model.canSubmit ? "Return to the previous app and paste" : "No previous app is known yet")

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
            }
            .disabled(!model.isEditorSelectionEmpty || model.isCopying || model.promptText.isEmpty)
            .help(model.isEditorSelectionEmpty ? "Copy the full prompt" : "Use the editor selection copy")

            Spacer()

            if !model.targetHistory.isEmpty {
                Menu {
                    ForEach(model.targetHistory, id: \.bundleIdentifier) { app in
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
