//
//  VaultWikiLinkResolver.swift
//  HelloNotes
//
//  Created by Chris Tham on 11/7/2026.
//

#if os(macOS)
import Foundation
import MarkdownEngine

/// Tells MarkdownEngine which `[[wiki-link]]` targets exist so links to real
/// notes render as clickable links (and broken ones appear muted).
///
/// It only ever reports `exists` — it never returns a non-empty `id`. That
/// matters: the editor writes a resolver's id back into the file as
/// `[[Name|id]]`. By resolving purely on title existence we keep the user's
/// `[[Name]]` text byte-for-byte intact.
///
/// The known-title set is updated from the main actor as the vault changes;
/// `resolve`/`fingerprint` may be called off the main actor during styling, so
/// access is lock-guarded.
final class VaultWikiLinkResolver: WikiLinkResolver, @unchecked Sendable {
    private let lock = NSLock()
    private var titles: Set<String> = []
    private var revision = 0

    /// Replace the set of existing note titles (case-insensitive). Bumping the
    /// revision changes `fingerprint()`, which makes the editor restyle links —
    /// so a newly-created target becomes clickable immediately.
    func update(titles newTitles: some Sequence<String>) {
        lock.lock(); defer { lock.unlock() }
        titles = Set(newTitles.map { $0.lowercased() })
        revision += 1
    }

    func resolve(displayName: String, range: NSRange) -> WikiLinkResolution? {
        lock.lock(); defer { lock.unlock() }
        let exists = titles.contains(displayName.lowercased())
        return WikiLinkResolution(id: "", exists: exists)
    }

    func fingerprint() -> AnyHashable {
        lock.lock(); defer { lock.unlock() }
        return AnyHashable(revision)
    }
}
#endif
