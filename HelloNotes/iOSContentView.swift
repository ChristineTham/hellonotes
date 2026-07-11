//
//  iOSContentView.swift
//  HelloNotes
//
//  Created by Chris Tham on 11/7/2026.
//

#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// The iOS navigation shell: a push-based `NavigationStack` sharing the Core
/// and State layers with macOS. MarkdownEngine is macOS-only (AppKit/TextKit 2),
/// so the mobile editor is a plain-text `TextEditor` — still backed by the same
/// `EditorModel` load/dirty/debounced-autosave logic.
struct iOSContentView: View {
    @Environment(WorkspaceIndexer.self) private var indexer
    @Environment(\.scenePhase) private var scenePhase

    @State private var editor = EditorModel()
    @State private var showImporter = false
    @State private var searchText = ""

    private var filteredNotes: [Note] {
        guard !searchText.isEmpty else { return indexer.notes }
        return indexer.notes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if indexer.selectedVaultURL == nil {
                    ContentUnavailableView {
                        Label("No Vault", systemImage: "folder")
                    } description: {
                        Text("Choose a folder of Markdown files to begin.")
                    } actions: {
                        Button("Select Vault Folder") { showImporter = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    noteList
                }
            }
            .navigationTitle(indexer.selectedVaultURL?.lastPathComponent ?? "HelloNotes")
            .navigationDestination(for: Note.self) { note in
                NoteTextEditor(editor: editor, note: note)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if indexer.selectedVaultURL != nil {
                            Button {
                                indexer.createNote()
                            } label: {
                                Label("New Note", systemImage: "square.and.pencil")
                            }
                        }
                        Button {
                            showImporter = true
                        } label: {
                            Label("Select Vault Folder", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                indexer.setVault(url)
            }
        }
        .task {
            if indexer.selectedVaultURL == nil {
                indexer.restoreVault()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                Task { await editor.flush() }
            }
        }
    }

    private var noteList: some View {
        List(filteredNotes) { note in
            NavigationLink(value: note) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title)
                        .font(.headline)
                    Text(note.lastModified, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search notes")
        .overlay {
            if indexer.notes.isEmpty {
                ContentUnavailableView("No Notes", systemImage: "doc.text")
            }
        }
    }
}

/// Plain-text Markdown editor for iOS, backed by the shared `EditorModel`.
private struct NoteTextEditor: View {
    @Bindable var editor: EditorModel
    let note: Note

    var body: some View {
        TextEditor(text: $editor.text)
            .font(.body.monospaced())
            .padding(.horizontal, 4)
            .navigationTitle(note.title)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: note.id) {
                await editor.open(note)
            }
            .onDisappear {
                Task { await editor.flush() }
            }
    }
}
#endif
