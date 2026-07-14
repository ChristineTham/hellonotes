//
//  MentionScanner.swift
//  HelloNotes
//
//  Created by Chris Tham on 11/7/2026.
//

import Foundation

/// Finds "unlinked mentions" — a note's title/aliases appearing as plain text
/// in another note but **not** already wrapped in a `[[wiki-link]]` (Core layer).
nonisolated enum MentionScanner {

    /// Does `text` contain any of `names` as a word-boundaried plain-text
    /// mention that isn't already the start of a `[[wiki-link]]`?
    static func containsMention(of names: [String], in text: String) -> Bool {
        let ns = text as NSString
        for name in names where !name.trimmingCharacters(in: .whitespaces).isEmpty {
            // Fast reject: a word-boundary regex over the whole note is
            // expensive, so skip it entirely unless the substring is present
            // at all. Most notes don't mention most other notes, so this
            // avoids the vast majority of regex scans in a large collection.
            guard text.range(of: name, options: .caseInsensitive) != nil else { continue }
            guard let regex = wordRegex(for: name) else { continue }
            let found = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for match in found where !isInsideWikiLink(match.range, in: ns) {
                return true
            }
        }
        return false
    }

    /// Wrap the first bare mention of `name` in `text` as `[[name]]`, returning
    /// the rewritten text — or nil if there's no bare mention to link.
    static func linkingFirstMention(of name: String, in text: String) -> String? {
        let ns = text as NSString
        guard let regex = wordRegex(for: name) else { return nil }
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard !isInsideWikiLink(match.range, in: ns) else { continue }
            let matched = ns.substring(with: match.range)
            return ns.replacingCharacters(in: match.range, with: "[[\(matched)]]")
        }
        return nil
    }

    // MARK: - Private

    /// Compiled word-boundary matchers, cached by name — building an
    /// `NSRegularExpression` is costly and the same names are scanned against
    /// thousands of notes. `NSCache` is thread-safe, matching `nonisolated`.
    private static let regexCache = NSCache<NSString, NSRegularExpression>()

    /// A case-insensitive, word-boundaried matcher for a literal name (cached).
    private static func wordRegex(for name: String) -> NSRegularExpression? {
        if let cached = regexCache.object(forKey: name as NSString) { return cached }
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(
            pattern: "(?<![\\p{L}0-9_])\(escaped)(?![\\p{L}0-9_])",
            options: [.caseInsensitive]
        ) else { return nil }
        regexCache.setObject(regex, forKey: name as NSString)
        return regex
    }

    /// True when the match is immediately preceded by `[[` (i.e. it's already the
    /// display text of a wiki-link — `[[Name]]`, `[[Name|x]]`, `[[Name#h]]`).
    private static func isInsideWikiLink(_ range: NSRange, in ns: NSString) -> Bool {
        guard range.location >= 2 else { return false }
        return ns.substring(with: NSRange(location: range.location - 2, length: 2)) == "[["
    }
}
