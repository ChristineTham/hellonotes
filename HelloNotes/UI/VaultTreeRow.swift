//
//  VaultTreeRow.swift
//  HelloNotes
//
//  Created by Chris Tham on 11/7/2026.
//

#if os(macOS)
import SwiftUI

/// One row of the folder tree — recursively renders folders (as disclosure
/// groups) and notes (as selectable leaves tagged by their note id).
struct VaultTreeRow: View {
    let node: VaultTreeNode
    let onDelete: (Note) -> Void

    var body: some View {
        if let note = node.note {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.headline)
                Text(note.lastModified, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tag(note.id)
            .contextMenu {
                Button(role: .destructive) {
                    onDelete(note)
                } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
            }
        } else {
            DisclosureGroup {
                ForEach(node.children ?? []) { child in
                    VaultTreeRow(node: child, onDelete: onDelete)
                }
            } label: {
                Label(node.name, systemImage: "folder")
                    .font(.subheadline)
            }
        }
    }
}
#endif
