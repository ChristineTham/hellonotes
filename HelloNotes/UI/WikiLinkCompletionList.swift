//
//  WikiLinkCompletionList.swift
//  HelloNotes
//
//  Created by Chris Tham on 11/7/2026.
//

#if os(macOS)
import SwiftUI

/// A small floating list of note-title suggestions shown next to the caret
/// while typing inside a `[[wiki-link]]`. Click a row to insert it. (Keyboard
/// navigation isn't available because the text view keeps first-responder
/// focus while the list is open.)
struct WikiLinkCompletionList: View {
    let matches: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(matches, id: \.self) { title in
                Button {
                    onSelect(title)
                } label: {
                    Label(title, systemImage: "doc.text")
                        .lineLimit(1)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 240, alignment: .leading)
        .padding(4)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        .shadow(radius: 8, y: 2)
    }
}
#endif
