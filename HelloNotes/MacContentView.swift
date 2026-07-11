//
//  MacContentView.swift
//  HelloNotes
//
//  Created by Chris Tham on 11/7/2026.
//

#if os(macOS)
import SwiftUI
import AppKit

/// The macOS three-column navigation shell: sidebar, note list, and editor.
struct MacContentView: View {
    @Environment(WorkspaceIndexer.self) private var indexer
    @Environment(\.scenePhase) private var scenePhase

    /// Owns the open document and its debounced autosave.
    @State private var editor = EditorModel()

    /// The vault's `[[wiki-link]]` / backlink index.
    @State private var linkGraph = LinkGraph()

    /// Tells the editor which wiki-link targets exist (drives clickability).
    @State private var wikiResolver = VaultWikiLinkResolver()

    /// Selected note identity (its file URL — stable across re-indexing).
    @State private var selectedNoteID: Note.ID?

    /// Title filter for the note list.
    @State private var searchText = ""

    private var filteredNotes: [Note] {
        guard !searchText.isEmpty else { return indexer.notes }
        return indexer.notes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var selectedNote: Note? {
        indexer.notes.first { $0.id == selectedNoteID }
    }

    private var backlinks: [Note] {
        guard let selectedNote else { return [] }
        return linkGraph.backlinks(for: selectedNote, in: indexer.notes)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            noteList
        } detail: {
            NoteEditorView(
                editor: editor,
                backlinks: backlinks,
                wikiResolver: wikiResolver,
                onOpenWikiLink: openWikiLink,
                onOpenNote: { selectedNoteID = $0.id }
            )
        }
        .task {
            // Reopen the last vault on first launch.
            if indexer.selectedVaultURL == nil {
                indexer.restoreVault()
            }
            refreshGraph(with: indexer.notes)
        }
        .onChange(of: selectedNoteID) { _, newID in
            let note = indexer.notes.first { $0.id == newID }
            Task { await editor.open(note) }
        }
        .onChange(of: indexer.notes) { _, notes in
            // Note set changed (scan / create / delete): refresh links & backlinks.
            refreshGraph(with: notes)
        }
        .onChange(of: editor.savedRevision) { _, _ in
            // A note's contents changed on disk: its links may have too.
            Task { await linkGraph.rebuild(from: indexer.notes) }
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

    /// Keep the wiki-link resolver's known titles and the backlink graph in
    /// sync with the current note set.
    private func refreshGraph(with notes: [Note]) {
        wikiResolver.update(titles: notes.map(\.title))
        Task { await linkGraph.rebuild(from: notes) }
    }

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

    /// Handle a clicked link. External URLs open in the default app; otherwise
    /// the target is treated as a note title — navigate to the matching note,
    /// or create it if it doesn't exist yet (create-on-miss).
    private func openWikiLink(_ target: String) {
        let webSchemes: Set<String> = ["http", "https", "mailto", "file"]
        if let url = URL(string: target),
           let scheme = url.scheme?.lowercased(),
           webSchemes.contains(scheme) {
            NSWorkspace.shared.open(url)
            return
        }

        if let match = indexer.notes.first(where: { $0.title.localizedCaseInsensitiveCompare(target) == .orderedSame }) {
            selectedNoteID = match.id
        } else if let created = indexer.createNote(title: target) {
            selectedNoteID = created.id
        }
    }
}
#endif
