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

/// The editor column: hosts MarkdownEngine's live TextKit 2 text view for the
/// open note, with fenced-code syntax highlighting and a save-status indicator.
struct NoteEditorView: View {
    @Bindable var editor: EditorModel

    var body: some View {
        Group {
            if editor.note == nil {
                ContentUnavailableView(
                    "No Note Selected",
                    systemImage: "doc.text",
                    description: Text("Select a note from the list, or create a new one.")
                )
            } else {
                NativeTextViewWrapper(
                    text: $editor.text,
                    configuration: Self.configuration,
                    documentId: editor.note?.fileURL.path ?? "default"
                )
                .navigationTitle(editor.note?.title ?? "")
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        saveStatus
                    }
                }
            }
        }
    }

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

    /// Editor configuration with the HighlighterSwift bridge wired in so fenced
    /// code blocks render with native syntax highlighting.
    private static let configuration: MarkdownEditorConfiguration = {
        var config = MarkdownEditorConfiguration.default
        config.services.syntaxHighlighter = HighlighterSwiftBridge()
        return config
    }()
}
#endif
