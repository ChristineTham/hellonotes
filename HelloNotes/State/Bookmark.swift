//
//  Bookmark.swift
//  HelloNotes
//
//  Created by Chris Tham on 12/7/2026.
//
//  Security-scoped bookmark helpers, so sandboxed access to user-picked folders
//  (local, iCloud Drive, Obsidian vaults) survives relaunches. Shared by the
//  library, recents, and saved-libraries stores.
//

import Foundation

enum Bookmark {
    /// Bookmark data for `url`, security-scoped on macOS.
    static func data(for url: URL) -> Data? {
        #if os(macOS)
        return try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    /// Resolve bookmark `data` back to a URL (does not start the security scope).
    static func resolve(_ data: Data) -> URL? {
        var isStale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        return try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &isStale)
    }
}
