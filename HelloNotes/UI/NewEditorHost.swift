//
//  NewEditorHost.swift
//  HelloNotes
//
//  Created by Chris Tham on 17/7/2026.
//
//  Hosts the new in-repo editor (Packages/NotesEditor) behind the
//  "New editor (beta)" toggle while it works toward parity with the old
//  engine — rollout plan in docs/editor-rewrite.md. Bridges the
//  EditorDocument world (the editor owns the text) to EditorModel's
//  String world (autosave, conflicts) at save granularity: the document
//  syncs its text back after a short idle, never per keystroke.
//

#if os(macOS)
import SwiftUI
import MarkdownEditor

struct NewEditorHost: View {
    let editor: EditorModel
    /// Note titles + aliases, for wiki-link existence styling.
    let linkCandidates: [String]
    var fontSize: CGFloat
    var accent: NSColor
    var isEditable: Bool = true
    var onOpenWikiLink: (String) -> Void

    @State private var document: EditorDocument?
    @State private var syncTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let document {
                MarkdownEditorView(document: document)
                    .editable(isEditable)
                    .onLinkTap { tap in
                        switch tap {
                        case .wiki(let target): onOpenWikiLink(target)
                        case .url(let url): NSWorkspace.shared.open(url)
                        }
                    }
            } else {
                // Off-main parse+style of a large note; near-instant for
                // typical ones.
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: taskKey) {
            syncTask?.cancel()
            // Case-insensitive title set, matching CollectionWikiLinkResolver.
            let titles = Set(linkCandidates.map { $0.lowercased() })
            let services = EditorServices(wikiLinkExists: { title in
                titles.contains(title.lowercased())
            })
            let built = await EditorDocument.make(
                text: editor.text,
                theme: EditorTheme(fontSize: fontSize, accent: accent),
                services: services
            )
            guard !Task.isCancelled else { return }
            built.onEdit = { _ in scheduleSync(from: built) }
            document = built
            // A flush (note switch, window resign, quit) must save the
            // document's *current* text, not a snapshot trailing by the
            // sync debounce.
            editor.willFlush = { [weak built] in
                guard let built else { return }
                if built.text != editor.text { editor.text = built.text }
            }
        }
        .onDisappear {
            syncTask?.cancel()
            if let document, document.text != editor.text {
                editor.text = document.text
            }
            editor.willFlush = nil
        }
    }

    /// Rebuild the document when the note or its loaded-from-disk state
    /// changes (open, external reload, conflict resolution — never our own
    /// saves), or when the theme changes.
    private var taskKey: String {
        "\(editor.note?.fileURL.path ?? "")|\(editor.loadRevision)|\(Int(fontSize))"
    }

    private func scheduleSync(from document: EditorDocument) {
        syncTask?.cancel()
        syncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            // One O(n) snapshot at save cadence — EditorModel's didSet then
            // runs its own debounce + atomic write.
            editor.text = document.text
        }
    }
}
#endif
