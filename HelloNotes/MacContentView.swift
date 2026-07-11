//
//  MacContentView.swift
//  HelloNotes
//
//  Created by Chris Tham on 11/7/2026.
//

#if os(macOS)
import SwiftUI

/// The macOS three-column navigation shell: sidebar, note list, and editor.
struct MacContentView: View {
    @Environment(WorkspaceIndexer.self) private var indexer
    @Environment(\.scenePhase) private var scenePhase

    /// Owns the open document and its debounced autosave.
    @State private var editor = EditorModel()

    /// Selected note identity (its file URL — stable across re-indexing).
    @State private var selectedNoteID: Note.ID?

    /// Title filter for the note list.
    @State private var searchText = ""

    private var filteredNotes: [Note] {
        guard !searchText.isEmpty else { return indexer.notes }
        return indexer.notes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            noteList
        } detail: {
            NoteEditorView(editor: editor)
        }
        .task {
            // Reopen the last vault on first launch.
            if indexer.selectedVaultURL == nil {
                indexer.restoreVault()
            }
        }
        .onChange(of: selectedNoteID) { _, newID in
            let note = indexer.notes.first { $0.id == newID }
            Task { await editor.open(note) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Safety net beyond the debounce: flush unsaved edits when the app
            // is no longer active (hidden, backgrounded, or quitting).
            if newPhase != .active {
                Task { await editor.flush() }
            }
        }
    }

    // MARK: - Column 1: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                indexer.requestVaultAccess()
            } label: {
                Label("Select Vault Folder", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let vaultURL = indexer.selectedVaultURL {
                Text(vaultURL.lastPathComponent)
                    .font(.headline)
                Text("\(indexer.notes.count) notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    newNote()
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
            }

            Spacer()
        }
        .padding()
        .navigationTitle("HelloNotes")
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
    }

    // MARK: - Column 2: Note list

    private var noteList: some View {
        List(filteredNotes, selection: $selectedNoteID) { note in
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.headline)
                Text(note.lastModified, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tag(note.id)
            .contextMenu {
                Button(role: .destructive) {
                    delete(note)
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search notes")
        .navigationTitle("Notes")
        .overlay {
            if indexer.notes.isEmpty {
                ContentUnavailableView(
                    "No Notes",
                    systemImage: "doc.text",
                    description: Text("Select a vault folder to index your Markdown files.")
                )
            }
        }
    }

    // MARK: - Actions

    private func newNote() {
        if let note = indexer.createNote() {
            selectedNoteID = note.id
        }
    }

    private func delete(_ note: Note) {
        let wasSelected = selectedNoteID == note.id
        indexer.deleteNote(note)
        if wasSelected {
            selectedNoteID = nil
        }
    }
}
#endif
