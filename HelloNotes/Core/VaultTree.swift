//
//  VaultTree.swift
//  HelloNotes
//
//  Created by Chris Tham on 11/7/2026.
//

import Foundation

/// How notes are ordered within a folder.
enum VaultSortOrder: String, CaseIterable, Identifiable, Hashable {
    case name = "Name"
    case modified = "Date Modified"
    var id: String { rawValue }
    var systemImage: String { self == .name ? "textformat" : "clock" }
}

/// A node in the vault's folder tree: either a folder (with `children`) or a
/// note (leaf). `id` is the item's path, stable across re-indexing.
struct VaultTreeNode: Identifiable, Hashable {
    let id: String
    let name: String
    let note: Note?
    var children: [VaultTreeNode]?

    var isFolder: Bool { note == nil }
}

/// Builds a folder tree from a flat note list by their paths relative to the
/// vault root. Folders come before notes; folders sort by name, notes by the
/// chosen order. `nonisolated` — pure and callable from any actor.
nonisolated enum VaultTree {

    static func build(from notes: [Note], vaultURL: URL, sort: VaultSortOrder) -> [VaultTreeNode] {
        let root = Folder()
        let vaultDepth = vaultURL.standardizedFileURL.pathComponents.count

        for note in notes {
            let components = note.fileURL.standardizedFileURL.pathComponents
            guard components.count > vaultDepth else { continue }
            let relative = components[vaultDepth...]
            let directories = relative.dropLast()

            var folder = root
            for dir in directories {
                folder = folder.child(named: String(dir))
            }
            folder.notes.append(note)
        }

        return nodes(from: root, path: "", sort: sort)
    }

    // MARK: - Private

    private final class Folder {
        var subfolders: [String: Folder] = [:]
        var notes: [Note] = []

        func child(named name: String) -> Folder {
            if let existing = subfolders[name] { return existing }
            let created = Folder()
            subfolders[name] = created
            return created
        }
    }

    private static func nodes(from folder: Folder, path: String, sort: VaultSortOrder) -> [VaultTreeNode] {
        var result: [VaultTreeNode] = []

        for name in folder.subfolders.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            let childPath = "\(path)/\(name)"
            result.append(VaultTreeNode(
                id: childPath,
                name: name,
                note: nil,
                children: nodes(from: folder.subfolders[name]!, path: childPath, sort: sort)
            ))
        }

        let sortedNotes: [Note]
        switch sort {
        case .name:
            sortedNotes = folder.notes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .modified:
            sortedNotes = folder.notes.sorted { $0.lastModified > $1.lastModified }
        }
        for note in sortedNotes {
            result.append(VaultTreeNode(id: note.fileURL.path, name: note.title, note: note, children: nil))
        }

        return result
    }
}
