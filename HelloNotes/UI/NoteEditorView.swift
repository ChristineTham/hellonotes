//
//  NoteEditorView.swift
//  HelloNotes
//
//  Created by Chris Tham on 11/7/2026.
//

#if os(macOS)
import SwiftUI
import MarkdownEngine
import MarkdownEngineCodeBlocks
import MarkdownEngineLatex

/// The editor column: hosts MarkdownEngine's live TextKit 2 text view for the
/// open note (with code highlighting and LaTeX), routes wiki-link clicks, and
/// shows a backlinks panel beneath the editor.
struct NoteEditorView: View {
    @Bindable var editor: EditorModel

    /// Notes that link to the open note.
    var backlinks: [Note] = []

    /// Resolves which `[[wiki-link]]` targets exist (drives link clickability).
    var wikiResolver: VaultWikiLinkResolver

    /// Called when a `[[wiki-link]]` (or plain link) is clicked, with its target.
    var onOpenWikiLink: (String) -> Void = { _ in }

    /// Called to open a note from the backlinks panel.
    var onOpenNote: (Note) -> Void = { _ in }

    var body: some View {
        Group {
            if editor.note == nil {
                ContentUnavailableView(
                    "No Note Selected",
                    systemImage: "doc.text",
                    description: Text("Select a note from the list, or create a new one.")
                )
            } else {
                VStack(spacing: 0) {
                    if editor.hasConflict {
                        conflictBanner
                    }

                    NativeTextViewWrapper(
                        text: $editor.text,
                        configuration: configuration,
                        documentId: editor.note?.fileURL.path ?? "default",
                        onLinkClick: onOpenWikiLink
                    )

                    if !backlinks.isEmpty {
                        Divider()
                        backlinksPanel
                    }
                }
                .navigationTitle(editor.note?.title ?? "")
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        saveStatus
                    }
                }
            }
        }
    }

    // MARK: - Conflict banner

    private var conflictBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("This note changed on disk while you were editing.")
                .font(.callout)
            Spacer()
            Button("Reload") { editor.resolveConflictReloading() }
            Button("Keep Mine") { Task { await editor.resolveConflictKeepingMine() } }
                .keyboardShortcut(.defaultAction)
        }
        .padding(8)
        .background(.orange.opacity(0.15))
    }

    // MARK: - Backlinks

    private var backlinksPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(backlinks.count == 1 ? "1 Linked Reference" : "\(backlinks.count) Linked References")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(backlinks) { note in
                        Button {
                            onOpenNote(note)
                        } label: {
                            Label(note.title, systemImage: "link")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxHeight: 160)
        .background(.quaternary.opacity(0.4))
    }

    // MARK: - Save status

    @ViewBuilder
    private var saveStatus: some View {
        if let error = editor.saveError {
            Label("Save failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help(error)
        } else if editor.isDirty {
            Label("Saving…", systemImage: "pencil.circle")
                .foregroundStyle(.secondary)
        } else {
            Label("Saved", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    // Bridges are stateless and expensive-ish to build, so share one instance.
    private static let syntaxHighlighter = HighlighterSwiftBridge()
    private static let latexRenderer = SwiftMathBridge()

    /// Editor configuration wiring in the HighlighterSwift (code) and SwiftMath
    /// (LaTeX) bridges plus the vault wiki-link resolver, so fenced code blocks
    /// are syntax-highlighted, `$…$` / `$$…$$` math renders natively, and
    /// `[[wiki-links]]` to existing notes are clickable.
    private var configuration: MarkdownEditorConfiguration {
        var config = MarkdownEditorConfiguration.default
        config.services.syntaxHighlighter = Self.syntaxHighlighter
        config.services.latex = Self.latexRenderer
        config.services.wikiLinks = wikiResolver
        return config
    }
}
#endif
