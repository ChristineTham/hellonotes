//
//  OutlineView.swift
//  HelloNotes
//
//  Created by Chris Tham on 11/7/2026.
//

#if os(macOS)
import SwiftUI

/// A popover showing the note's statistics and an outline (table of contents)
/// for orientation. The outline is a read-only map of the document's headings.
struct OutlineView: View {
    let text: String

    private var stats: DocumentStatistics { DocumentAnalyzer.analyze(text) }
    private var headings: [DocumentHeading] { MarkdownParsing.headings(in: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("STATISTICS")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                statRow("Words", stats.words.formatted())
                statRow("Characters", stats.characters.formatted())
                statRow("Paragraphs", stats.paragraphs.formatted())
                statRow("Reading time", stats.readingMinutes <= 0 ? "—" : "\(stats.readingMinutes) min")
            }
            .padding(12)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("OUTLINE")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if headings.isEmpty {
                    Text("No headings")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(headings.enumerated()), id: \.offset) { _, heading in
                                Text(heading.title)
                                    .font(heading.level == 1 ? .callout.weight(.semibold) : .callout)
                                    .lineLimit(1)
                                    .padding(.leading, CGFloat(heading.level - 1) * 14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }
            }
            .padding(12)
        }
        .frame(width: 260)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.callout)
    }
}
#endif
