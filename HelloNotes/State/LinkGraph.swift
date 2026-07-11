//
//  LinkGraph.swift
//  HelloNotes
//
//  Created by Chris Tham on 11/7/2026.
//

import Foundation
import Observation

/// Builds and holds the vault's `[[wiki-link]]` graph so the UI can show, for
/// any note, which other notes link *to* it (backlinks). The index is rebuilt
/// off the main actor whenever the note set or a note's contents change.
@MainActor
@Observable
final class LinkGraph {
    /// Backlink index: a normalised (lowercased) link target → the set of note
    /// file URLs whose text contains `[[target]]`.
    private(set) var backlinksByTitle: [String: Set<URL>] = [:]

    /// Rebuild the entire graph from the current notes. Reads every file off
    /// the main actor. (A future optimisation is incremental per-note updates.)
    func rebuild(from notes: [Note]) async {
        let urls = notes.map(\.fileURL)
        let index = await Task.detached(priority: .utility) {
            var result: [String: Set<URL>] = [:]
            for url in urls {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                for target in MarkdownParsing.wikiLinkTargets(in: text) {
                    result[target.lowercased(), default: []].insert(url)
                }
            }
            return result
        }.value
        backlinksByTitle = index
    }

    /// The notes that link to `note` via `[[\(note.title)]]`, excluding the
    /// note's own self-references.
    func backlinks(for note: Note, in notes: [Note]) -> [Note] {
        let linkingURLs = backlinksByTitle[note.title.lowercased()] ?? []
        guard !linkingURLs.isEmpty else { return [] }
        return notes.filter { $0.fileURL != note.fileURL && linkingURLs.contains($0.fileURL) }
    }
}
