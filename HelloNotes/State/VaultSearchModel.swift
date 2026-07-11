//
//  VaultSearchModel.swift
//  HelloNotes
//
//  Created by Chris Tham on 11/7/2026.
//

import Foundation
import Observation

/// A full-text search hit: the note plus a snippet around the first match.
struct SearchHit: Identifiable, Hashable {
    var id: URL { note.fileURL }
    let note: Note
    let snippet: String
}

/// An "Open Quickly" candidate — a note, or a heading within a note.
struct QuickOpenItem: Identifiable, Hashable {
    enum Kind: Hashable { case note, heading }
    let id: String
    let note: Note
    let kind: Kind
    let title: String
    let subtitle: String?
    var score: Int = 0
}

/// Caches note contents (and their headings) so the UI can run full-text
/// search and fuzzy "Open Quickly" lookups over the whole vault without
/// re-reading the disk on every keystroke. The cache is refreshed off the
/// main actor whenever the note set or a note's contents change.
@MainActor
@Observable
final class VaultSearchModel {
    private struct Entry {
        let note: Note
        let text: String
        let headings: [DocumentHeading]
    }

    private var entries: [Entry] = []

    /// Reload the content cache from the current notes (reads files off-main).
    func refresh(from notes: [Note]) async {
        let urls = notes.map(\.fileURL)
        let noteByURL = Dictionary(notes.map { ($0.fileURL, $0) }, uniquingKeysWith: { first, _ in first })

        let loaded = await Task.detached(priority: .utility) { () -> [(URL, String, [DocumentHeading])] in
            urls.compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return (url, text, MarkdownParsing.headings(in: text))
            }
        }.value

        entries = loaded.compactMap { url, text, headings in
            noteByURL[url].map { Entry(note: $0, text: text, headings: headings) }
        }
    }

    /// Notes whose title or body contains `query` (case-insensitive), each with
    /// a snippet around the first body match.
    func fullTextResults(query: String) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        return entries.compactMap { entry in
            if let snippet = Self.snippet(of: entry.text, matching: q) {
                return SearchHit(note: entry.note, snippet: snippet)
            }
            if entry.note.title.localizedCaseInsensitiveContains(q) {
                return SearchHit(note: entry.note, snippet: "")
            }
            return nil
        }
    }

    /// Fuzzy matches over note titles and their headings, best first.
    func quickOpenResults(query: String, limit: Int = 40) -> [QuickOpenItem] {
        let items = allItems()
        let q = query.trimmingCharacters(in: .whitespaces)

        guard !q.isEmpty else {
            return Array(items.filter { $0.kind == .note }.prefix(limit))
        }

        let scored = items.compactMap { item -> QuickOpenItem? in
            let haystack = item.subtitle.map { "\(item.title) \($0)" } ?? item.title
            guard let score = FuzzyMatch.score(query: q, candidate: haystack) else { return nil }
            var copy = item
            copy.score = score
            return copy
        }
        return Array(scored.sorted { $0.score > $1.score }.prefix(limit))
    }

    // MARK: - Private

    private func allItems() -> [QuickOpenItem] {
        entries.flatMap { entry -> [QuickOpenItem] in
            var items = [QuickOpenItem(
                id: entry.note.fileURL.path,
                note: entry.note,
                kind: .note,
                title: entry.note.title,
                subtitle: nil
            )]
            for heading in entry.headings {
                items.append(QuickOpenItem(
                    id: "\(entry.note.fileURL.path)#\(heading.title)",
                    note: entry.note,
                    kind: .heading,
                    title: entry.note.title,
                    subtitle: heading.title
                ))
            }
            return items
        }
    }

    private static func snippet(of text: String, matching query: String, context: Int = 40) -> String? {
        guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }
        let lower = text.index(range.lowerBound, offsetBy: -context, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: context, limitedBy: text.endIndex) ?? text.endIndex

        var snippet = String(text[lower..<upper])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if lower > text.startIndex { snippet = "…" + snippet }
        if upper < text.endIndex { snippet += "…" }
        return snippet
    }
}
