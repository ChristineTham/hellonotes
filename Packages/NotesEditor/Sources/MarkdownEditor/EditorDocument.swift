//
//  EditorDocument.swift
//  MarkdownEditor
//
//  The document object the app holds instead of a Binding<String>. It owns
//  the NSTextStorage (raw Markdown — the storage IS the document), the
//  incremental parse state, and the per-document undo manager. Text flows
//  out at save granularity via `text`; edits flow out as range-level
//  events via `onEdit` — no per-keystroke whole-string round-trips.
//
//  Styling is progressive: at open, only the first screens are styled
//  (synchronously — open is effectively instant at any size); the rest is
//  styled in idle-time batches and on demand as it scrolls into view. All
//  styling goes through one path, directly into the storage — measured to
//  matter: importing a pre-styled attributed string via
//  setAttributedString leaves NSTextStorage converting attribute-run
//  regions lazily on first touch, up to ~100 ms per region on multi-MB
//  notes, exactly on the user's first keystroke there.
//
//  Editing pipeline (all O(damage), enforced by MarkdownCore's tests):
//    storage mutates → didProcessEditing → incremental reparse → restyle
//    the damaged blocks (inside the same layout pass, so no flash).
//  Caret pipeline:
//    selection change → reveal-set diff → restyle ≤ a few blocks.
//

import Foundation
import Observation
import MarkdownCore
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Services the host app injects. All closures are Sendable (styling can
/// run from any context that owns the document).
public struct EditorServices: Sendable {
    /// Does a note with this title exist? Drives resolved vs. muted wiki links.
    public var wikiLinkExists: (@Sendable (String) -> Bool)?

    public init(wikiLinkExists: (@Sendable (String) -> Bool)? = nil) {
        self.wikiLinkExists = wikiLinkExists
    }
}

@Observable
public final class EditorDocument {

    // MARK: - Public surface

    /// The raw Markdown, snapshotted from storage. O(n) — call at save
    /// granularity, never per keystroke.
    public var text: String { storage.string }

    /// Bumps on every character edit (for observers that key async work).
    public private(set) var revision = 0

    /// Range-level edit notification, fired after reparse + restyle.
    @ObservationIgnored public var onEdit: ((TextEdit) -> Void)?

    /// The block structure (read-only; used for outline, caret context…).
    public var blocks: [Block] { parse.blocks }

    /// Per-phase timings of the last keystroke cycle — permanent, cheap
    /// introspection so perf regressions are measurable in place.
    public struct EditMetrics: Sendable {
        public var parseMS: Double = 0
        public var restyleMS: Double = 0
    }
    @ObservationIgnored public private(set) var lastEditMetrics = EditMetrics()

    public let theme: EditorTheme
    public let undoManager = UndoManager()

    // MARK: - Internals

    let storage = NSTextStorage()
    private(set) var parse: ParseResult
    private let services: EditorServices
    private var revealedBlocks: Set<Int> = []
    private var isApplyingStyles = false
    private let storageDelegate = StorageDelegate()

    /// Progressive styling state: which blocks carry current styling.
    /// (Bitset aligned with `parse.blocks`; rebuilt conservatively on edits
    /// that land before the initial pass finishes.)
    private var styledBlocks: [Bool] = []
    private var stylingTask: Task<Void, Never>?

    /// How many characters get styled synchronously at open — a few screens
    /// of any realistic font size.
    private static let initialStyledPrefix = 30_000

    // MARK: - Init

    public init(text: String, theme: EditorTheme = EditorTheme(), services: EditorServices = EditorServices()) {
        self.theme = theme
        self.services = services

        let ns = text as NSString
        self.parse = BlockParser.fullParse(ns)
        storage.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: theme.body,
            .foregroundColor: theme.text,
        ]))
        styledBlocks = Array(repeating: false, count: parse.blocks.count)

        // First screens styled before the view ever draws.
        ensureStyled(charactersIn: NSRange(location: 0, length: min(Self.initialStyledPrefix, storage.length)))
        scheduleBackgroundStyling()

        storageDelegate.document = self
        storage.delegate = storageDelegate
    }

    /// Async factory retained for API symmetry; open is cheap enough to be
    /// synchronous now (full parse of 3.8 MB ≈ 12 ms; styling is lazy).
    public static func make(
        text: String,
        theme: EditorTheme = EditorTheme(),
        services: EditorServices = EditorServices()
    ) async -> EditorDocument {
        EditorDocument(text: text, theme: theme, services: services)
    }

    // MARK: - Programmatic replacement (load, external reload)

    public func replaceText(_ newText: String) {
        stylingTask?.cancel()
        let ns = newText as NSString
        parse = BlockParser.fullParse(ns)
        isApplyingStyles = true
        storage.setAttributedString(NSAttributedString(string: newText, attributes: [
            .font: theme.body,
            .foregroundColor: theme.text,
        ]))
        isApplyingStyles = false
        styledBlocks = Array(repeating: false, count: parse.blocks.count)
        revealedBlocks = []
        ensureStyled(charactersIn: NSRange(location: 0, length: min(Self.initialStyledPrefix, storage.length)))
        scheduleBackgroundStyling()
        undoManager.removeAllActions()
        revision &+= 1
    }

    // MARK: - Progressive styling

    /// Style every not-yet-styled block intersecting `range`. The view
    /// calls this as content scrolls into view; the background pass calls
    /// it batch by batch. Idempotent and cheap on styled regions.
    public func ensureStyled(charactersIn range: NSRange) {
        guard !parse.blocks.isEmpty else { return }
        guard let lo = parse.blockIndex(at: max(0, min(range.location, storage.length))),
              let hi = parse.blockIndex(at: max(0, min(range.location + range.length, storage.length)))
        else { return }
        var pending: [Int] = []
        for i in lo...hi where !(styledBlocks.indices.contains(i) && styledBlocks[i]) {
            pending.append(i)
        }
        guard !pending.isEmpty else { return }
        restyle(blockIndices: Set(pending), revealed: revealedBlocks)
        for i in pending where styledBlocks.indices.contains(i) { styledBlocks[i] = true }
    }

    /// Walk the document once in idle-time batches until everything is
    /// styled. Restarted (debounced) if an edit lands mid-pass, because a
    /// splice shifts block indices out from under the bitset.
    private func scheduleBackgroundStyling(afterIdle: Bool = false) {
        stylingTask?.cancel()
        guard styledBlocks.contains(false) else { return }
        stylingTask = Task { @MainActor [weak self] in
            if afterIdle {
                try? await Task.sleep(for: .milliseconds(400))
            }
            guard !Task.isCancelled else { return }
            var cursor = 0
            while let self, !Task.isCancelled {
                guard cursor < self.styledBlocks.count else { break }
                guard let next = self.styledBlocks[cursor...].firstIndex(of: false) else { break }
                let batchEnd = min(next + 250, self.styledBlocks.count)
                let indices = Set((next..<batchEnd).filter { !self.styledBlocks[$0] })
                self.restyle(blockIndices: indices, revealed: self.revealedBlocks)
                for i in indices { self.styledBlocks[i] = true }
                cursor = batchEnd
                await Task.yield()
            }
            if let self, !Task.isCancelled { self.absorbFirstEditCost() }
        }
    }

    /// The first *character* edit deep into a large storage pays a one-time
    /// lazy-structure cost inside NSTextStorage (~90 ms at 3.8 MB, measured
    /// regardless of how styling was applied). Absorb it with a net-zero
    /// synthetic edit while idle so the user's first real keystroke doesn't.
    private func absorbFirstEditCost() {
        guard storage.length > 100_000 else { return }
        let mid = storage.length / 2
        isApplyingStyles = true          // net-zero: parse stays valid
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: mid, length: 0), with: " ")
        storage.replaceCharacters(in: NSRange(location: mid, length: 1), with: "")
        storage.endEditing()
        isApplyingStyles = false
    }

    /// Complete all pending styling synchronously (tests; pre-print/export).
    /// Applies in the same batch sizes as the background walker — separate
    /// processEditing passes are what settle NSTextStorage's lazy internal
    /// structures region by region (one mega-batch measurably does not).
    public func styleEverythingNow() {
        stylingTask?.cancel()
        var cursor = 0
        while cursor < styledBlocks.count {
            guard let next = styledBlocks[cursor...].firstIndex(of: false) else { break }
            let batchEnd = min(next + 250, styledBlocks.count)
            let indices = Set((next..<batchEnd).filter { !styledBlocks[$0] })
            restyle(blockIndices: indices, revealed: revealedBlocks)
            for i in indices { styledBlocks[i] = true }
            cursor = batchEnd
        }
        absorbFirstEditCost()
    }

    // MARK: - Editing pipeline

    /// Called by the storage delegate after characters change.
    fileprivate func storageDidEdit(editedRange: NSRange, changeInLength delta: Int) {
        guard !isApplyingStyles else { return }
        let oldRange = NSRange(location: editedRange.location, length: editedRange.length - delta)
        let edit = TextEdit(range: oldRange, replacementLength: editedRange.length)

        var t0 = DispatchTime.now()
        let hadPendingStyling = styledBlocks.contains(false)
        parse = BlockParser.incremental(storage.mutableString, edit: edit, previous: parse)
        lastEditMetrics.parseMS = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6
        t0 = DispatchTime.now()

        // Restyle the blocks covering the new text (plus one neighbor each
        // side — an edit can change how adjacent blocks read, and restyling
        // a block is cheap).
        var damaged = Set<Int>()
        if let lo = parse.blockIndex(at: edit.newRange.location) {
            let hi = parse.blockIndex(at: max(edit.newRange.location, edit.newRange.location + edit.newRange.length)) ?? lo
            for i in max(0, lo - 1)...min(parse.blocks.count - 1, hi + 1) { damaged.insert(i) }
        }

        // The splice shifted block indices; the styled bitset is only
        // trustworthy when the initial pass has already finished (then
        // everything is styled and stays styled — edits restyle in place).
        if hadPendingStyling {
            styledBlocks = Array(repeating: false, count: parse.blocks.count)
            // Don't leave the visible area unstyled while the pass restarts.
            ensureStyled(charactersIn: NSRange(
                location: max(0, edit.newRange.location - Self.initialStyledPrefix / 2),
                length: Self.initialStyledPrefix))
            scheduleBackgroundStyling(afterIdle: true)
        } else if styledBlocks.count != parse.blocks.count {
            styledBlocks = Array(repeating: true, count: parse.blocks.count)
        }

        let stillRevealed = damaged.union(revealedBlocks)
        restyle(blockIndices: damaged, revealed: stillRevealed)
        if !hadPendingStyling {
            for i in damaged where styledBlocks.indices.contains(i) { styledBlocks[i] = true }
        }
        lastEditMetrics.restyleMS = Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6

        revision &+= 1
        onEdit?(edit)
    }

    // MARK: - Caret-driven syntax reveal

    /// The view reports every selection change here; blocks whose reveal
    /// state flips get restyled (usually 0–2 blocks — O(paragraph), the
    /// property the old engine never had).
    public func selectionDidChange(_ selection: NSRange) {
        var newRevealed = Set<Int>()
        if let lo = parse.blockIndex(at: selection.location) {
            newRevealed.insert(lo)
            if selection.length > 0,
               let hi = parse.blockIndex(at: selection.location + selection.length) {
                // Reveal at most the boundary blocks of a selection — a
                // select-all must not restyle the world.
                newRevealed.insert(hi)
            }
        }
        guard newRevealed != revealedBlocks else { return }
        let changed = newRevealed.symmetricDifference(revealedBlocks)
        revealedBlocks = newRevealed
        restyle(blockIndices: changed, revealed: newRevealed)
    }

    // MARK: - Queries

    /// Document headings (outline, scroll targets).
    public func headings() -> [(level: Int, title: String, range: NSRange)] {
        let ns: NSString = storage.mutableString
        return parse.blocks.compactMap { block in
            guard case .heading(let level, let setext) = block.kind else { return nil }
            var r = block.range
            if setext, block.lineCount >= 2 {
                r = parse.lines.contentRange(block.firstLine, in: ns)
            }
            var title = ns.substring(with: r)
                .trimmingCharacters(in: CharacterSet(charactersIn: "# \n"))
            if let newline = title.firstIndex(of: "\n") { title = String(title[..<newline]) }
            return (level, title, block.range)
        }
    }

    // MARK: - Restyle

    private func restyle(blockIndices: Set<Int>, revealed: Set<Int>) {
        guard !blockIndices.isEmpty else { return }
        isApplyingStyles = true
        StyleApplier.apply(
            blockIndices: blockIndices.sorted(),
            parse: parse,
            text: storage.mutableString,
            to: storage,
            theme: theme,
            revealed: revealed,
            resolveWiki: services.wikiLinkExists
        )
        isApplyingStyles = false
    }
}

// MARK: - Storage delegate bridge

#if canImport(AppKit)
private typealias StorageEditActions = NSTextStorageEditActions
#else
private typealias StorageEditActions = NSTextStorage.EditActions
#endif

/// Small NSObject bridge (EditorDocument itself stays a pure @Observable).
private final class StorageDelegate: NSObject, NSTextStorageDelegate {
    weak var document: EditorDocument?

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: StorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated {
            document?.storageDidEdit(editedRange: editedRange, changeInLength: delta)
        }
    }
}
