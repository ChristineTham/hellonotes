//
//  HelloNotesTests.swift
//  HelloNotesTests
//
//  Created by Chris Tham on 11/7/2026.
//

import Testing
import Foundation
@testable import HelloNotes

struct HelloNotesTests {

    // MARK: - Helpers

    /// Create a unique temporary directory to act as a throwaway vault.
    private func makeTempVault() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HelloNotesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    // MARK: - EditorModel

    @Test @MainActor
    func openLoadsFileContents() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let fileURL = vault.appendingPathComponent("Hello.md")
        try write("# Hello\n\nWorld.", to: fileURL)
        let note = Note(title: "Hello", fileURL: fileURL, lastModified: .now)

        let editor = EditorModel()
        await editor.open(note)

        #expect(editor.text == "# Hello\n\nWorld.")
        #expect(editor.isDirty == false)
    }

    @Test @MainActor
    func editThenFlushPersistsToDisk() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let fileURL = vault.appendingPathComponent("Note.md")
        try write("original", to: fileURL)
        let note = Note(title: "Note", fileURL: fileURL, lastModified: .now)

        let editor = EditorModel()
        await editor.open(note)

        editor.text = "edited content"
        #expect(editor.isDirty == true)

        await editor.flush()

        let onDisk = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(onDisk == "edited content")
        #expect(editor.isDirty == false)
    }

    @Test @MainActor
    func switchingNotesFlushesPreviousEdits() async throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let firstURL = vault.appendingPathComponent("First.md")
        let secondURL = vault.appendingPathComponent("Second.md")
        try write("first", to: firstURL)
        try write("second", to: secondURL)

        let first = Note(title: "First", fileURL: firstURL, lastModified: .now)
        let second = Note(title: "Second", fileURL: secondURL, lastModified: .now)

        let editor = EditorModel()
        await editor.open(first)
        editor.text = "first edited"

        // Opening another note must flush the previous buffer first.
        await editor.open(second)

        let firstOnDisk = try String(contentsOf: firstURL, encoding: .utf8)
        #expect(firstOnDisk == "first edited")
        #expect(editor.text == "second")
    }

    // MARK: - WorkspaceIndexer

    @Test
    func scanFindsMarkdownFilesOnly() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        try write("# A", to: vault.appendingPathComponent("A.md"))
        try write("# B", to: vault.appendingPathComponent("B.markdown"))
        try write("not markdown", to: vault.appendingPathComponent("C.txt"))

        let indexer = WorkspaceIndexer()
        indexer.selectedVaultURL = vault
        indexer.scanVault()

        let titles = Set(indexer.notes.map(\.title))
        #expect(indexer.notes.count == 2)
        #expect(titles == ["A", "B"])
    }

    @Test
    func createAndDeleteNote() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let indexer = WorkspaceIndexer()
        indexer.selectedVaultURL = vault

        let created = try #require(indexer.createNote(title: "Fresh"))
        #expect(created.title == "Fresh")
        #expect(FileManager.default.fileExists(atPath: created.fileURL.path))
        #expect(indexer.notes.contains(created))

        indexer.deleteNote(created)
        #expect(FileManager.default.fileExists(atPath: created.fileURL.path) == false)
        #expect(indexer.notes.contains(created) == false)
    }

    @Test
    func createNoteDisambiguatesDuplicateNames() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let indexer = WorkspaceIndexer()
        indexer.selectedVaultURL = vault

        let first = try #require(indexer.createNote(title: "Untitled"))
        let second = try #require(indexer.createNote(title: "Untitled"))

        #expect(first.fileURL != second.fileURL)
        #expect(first.fileURL.lastPathComponent == "Untitled.md")
        #expect(second.fileURL.lastPathComponent == "Untitled 2.md")
    }
}
