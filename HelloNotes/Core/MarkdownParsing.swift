//
//  MarkdownParsing.swift
//  HelloNotes
//
//  Created by Chris Tham on 11/7/2026.
//

import Foundation
import Markdown

/// A heading discovered in a note, used for outline / "Open Quickly" features.
struct DocumentHeading: Hashable {
    let level: Int
    let title: String
}

/// Pure, UI-agnostic Markdown parsing helpers (Core layer).
///
/// Wiki-links and hashtags are not part of GitHub-Flavored Markdown, so they
/// are extracted with regular expressions that mirror MarkdownEngine's own
/// wiki-link storage pattern. Headings come from Apple's `swift-markdown` AST.
///
/// `nonisolated` so these pure functions can run off the main actor (the app
/// target defaults to main-actor isolation); the link graph parses files on a
/// background task.
nonisolated enum MarkdownParsing {

    /// Matches `[[Target]]` and `[[Target|Alias]]`, capturing the target in
    /// group 1. Mirrors MarkdownEngine's `WikiLinkService.storagePattern`
    /// (an unescaped `!` prefix — an image — is excluded).
    private static let wikiLinkRegex = try! NSRegularExpression(
        pattern: #"(?<!!)\[\[([^\|\]\r\n]*)(?:\|[^\]\r\n]+)?\]\]"#
    )

    /// Matches `#tag` (letters, digits, `_`, `-`, `/`), not preceded by a word
    /// character (so it won't fire inside `foo#bar`).
    private static let tagRegex = try! NSRegularExpression(
        pattern: #"(?<![\w])#([\p{L}0-9_][\p{L}0-9_/-]*)"#
    )

    /// The distinct wiki-link targets referenced by `text`, normalised: any
    /// `#heading` suffix removed and surrounding whitespace trimmed. Empty
    /// targets (e.g. a bare `[[]]`) are dropped. Order-preserving, de-duplicated.
    static func wikiLinkTargets(in text: String) -> [String] {
        matches(of: wikiLinkRegex, in: text, group: 1)
            .map { target in
                let withoutHeading = target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? target
                return withoutHeading.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
            .uniqued()
    }

    /// The distinct hashtags in `text`, without the leading `#`.
    static func tags(in text: String) -> [String] {
        matches(of: tagRegex, in: text, group: 1).uniqued()
    }

    /// The headings in `text`, in document order, parsed from the GFM AST.
    static func headings(in text: String) -> [DocumentHeading] {
        var collector = HeadingCollector()
        collector.visit(Document(parsing: text))
        return collector.headings
    }

    // MARK: - Private

    private static func matches(of regex: NSRegularExpression, in text: String, group: Int) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > group,
                  let r = Range(match.range(at: group), in: text) else { return nil }
            return String(text[r])
        }
    }

    private struct HeadingCollector: MarkupWalker {
        var headings: [DocumentHeading] = []
        mutating func visitHeading(_ heading: Heading) {
            headings.append(DocumentHeading(level: heading.level, title: heading.plainText))
        }
    }
}

private extension Array where Element: Hashable {
    /// De-duplicate while preserving first-seen order.
    nonisolated func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
