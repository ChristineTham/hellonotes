//
//  EditorModel.swift
//  HelloNotes
//
//  Created by Chris Tham on 11/7/2026.
//

import Foundation
import Observation

/// Owns the currently-open note's editing buffer and persists edits back to
/// disk. The file system is the source of truth: this model loads a note's
/// text, tracks whether the buffer diverges from what's on disk, and writes
/// changes atomically after a short debounce so no keystroke is ever lost.
@MainActor
@Observable
final class EditorModel {
    /// The note currently loaded in the editor, if any.
    private(set) var note: Note?

    /// Whether the buffer has unsaved changes relative to the last write.
    private(set) var isDirty = false

    /// The most recent save failure, surfaced to the UI (nil when healthy).
    private(set) var saveError: String?

    /// The live editing buffer bound to the text view. Mutations schedule a
    /// debounced save — except while we are programmatically replacing the
    /// text during a load, which must not mark the buffer dirty.
    var text: String = "" {
        didSet {
            guard !isReplacingText else { return }
            isDirty = (text != lastSavedText)
            scheduleSave()
        }
    }

    private var lastSavedText = ""
    private var isReplacingText = false
    private var saveTask: Task<Void, Never>?

    private static let debounce: Duration = .milliseconds(600)

    /// Load a note into the editor, flushing any pending save for the
    /// previous note first so switching notes never drops changes. Pass `nil`
    /// to clear the editor.
    func open(_ note: Note?) async {
        await flush()

        self.note = note
        saveError = nil

        let loaded: String
        if let url = note?.fileURL {
            loaded = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        } else {
            loaded = ""
        }

        replaceText(loaded)
        lastSavedText = loaded
        isDirty = false
    }

    /// Cancel the pending debounce and persist immediately. Call on note
    /// switch, window resignation, and app termination.
    func flush() async {
        saveTask?.cancel()
        saveTask = nil
        await save()
    }

    /// Persist the buffer if it diverges from disk. Safe to call repeatedly.
    func save() async {
        guard let url = note?.fileURL else { return }
        let snapshot = text
        guard snapshot != lastSavedText else { return }

        do {
            let data = Data(snapshot.utf8)
            // Atomic write (temp file + rename) so a crash mid-write can never
            // leave a truncated note on disk. Offloaded so large notes don't
            // stall the main actor.
            try await Task.detached(priority: .utility) {
                try data.write(to: url, options: .atomic)
            }.value
            lastSavedText = snapshot
            isDirty = (text != lastSavedText)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Private

    private func replaceText(_ newValue: String) {
        isReplacingText = true
        text = newValue
        isReplacingText = false
    }

    private func scheduleSave() {
        saveTask?.cancel()
        guard note != nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: EditorModel.debounce)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }
}
