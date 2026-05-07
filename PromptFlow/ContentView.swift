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
            Button("Cancel", role: .cancel) {
                entriesToDelete = []
            }
        } message: {
            if entriesToDelete.count == 1, let entry = entriesToDelete.first {
                Text(entry.text)
                    .lineLimit(2)
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
        }
    }

    private var sidebar: some View {
        List(selection: $model.selection) {
            Section("Current") {
                Label("Current Prompt", systemImage: "text.alignleft")
                    .tag(SidebarSelection.current)
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
                        Button(role: .destructive) {
                            let selectedHistory = model.selection.compactMap { sel -> PromptHistory? in
                                if case .history(let id) = sel {
                                    return model.history.first(where: { $0.id == id })
                                }
                                return nil
                            }
                            
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
                    Button {
                        settings.historyEditingMode.toggle()
                    } label: {
                        Image(systemName: settings.historyEditingMode ? "checkmark" : "trash")
                            .foregroundStyle(settings.historyEditingMode ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(settings.historyEditingMode ? "Done" : "Edit History")
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
                if let lastSelection = model.selection.first,
                   case .history(let id) = lastSelection,
                   let entry = model.history.first(where: { $0.id == id }) {
                    Text(entry.date.formatted(date: .numeric, time: .shortened))
                        .font(.headline)
                } else {
                    Text("Current Prompt")
                        .font(.headline)
                }
                Spacer()
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
                focusRequestID: model.focusRequestID,
                onSubmit: model.submitPrompt,
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
            .keyboardShortcut("c", modifiers: .command)
            .disabled(!model.isEditorSelectionEmpty || model.isCopying)
            .help(model.isEditorSelectionEmpty ? "Copy the full prompt" : "Use the editor selection copy")

            Spacer()

            if !model.targetHistory.isEmpty {
                Menu {
                    ForEach(model.targetHistory, id: \.bundleIdentifier) { app in
                        Button {
                            model.setTarget(app)
                        } label: {
                            Text(app.localizedName ?? "Unknown App")
                        }
                    }
                } label: {
                    Text(model.statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
