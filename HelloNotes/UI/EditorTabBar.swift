//
//  EditorTabBar.swift
//  HelloNotes
//
//  Created by Chris Tham on 11/7/2026.
//

#if os(macOS)
import SwiftUI

/// A horizontal bar of open-note tabs above the editor. Click a tab to switch,
/// or its ✕ to close it.
struct EditorTabBar: View {
    let notes: [Note]
    let activeID: Note.ID?
    let onSelect: (Note.ID) -> Void
    let onClose: (Note.ID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(notes) { note in
                    tab(note)
                    Divider()
                }
            }
        }
        .frame(height: 30)
        .background(.bar)
    }

    private func tab(_ note: Note) -> some View {
        let isActive = note.id == activeID
        return HStack(spacing: 6) {
            Text(note.title)
                .lineLimit(1)
                .font(.callout)
            Button {
                onClose(note.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(isActive ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.25) : Color.clear)
        .contentShape(.rect)
        .onTapGesture { onSelect(note.id) }
    }
}
#endif
