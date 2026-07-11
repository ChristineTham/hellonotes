//
//  TagTree.swift
//  HelloNotes
//
//  Created by Chris Tham on 11/7/2026.
//

import Foundation

/// A node in the hierarchical tag tree. A tag like `project/hellonotes` becomes
/// a `project` node with a `hellonotes` child; intermediate nodes are created
/// even when only the leaf is used as an explicit tag.
struct TagNode: Identifiable, Hashable, Sendable {
    /// The last path component, e.g. `hellonotes`.
    let name: String
    /// The full slash-separated path, e.g. `project/hellonotes` — the value used
    /// when filtering. Also the stable identity.
    let fullPath: String
    var children: [TagNode]

    var id: String { fullPath }
}

/// Builds a hierarchical tree from flat `a/b/c` tag strings (Core layer).
nonisolated enum TagTree {
    /// Group slash-separated tags into a nested `TagNode` tree, each level
    /// sorted case-insensitively.
    static func build(from tags: [String]) -> [TagNode] {
        let components = tags.map { $0.split(separator: "/").map(String.init) }
        return nodes(from: components, prefix: [])
    }

    private static func nodes(from components: [[String]], prefix: [String]) -> [TagNode] {
        let groups = Dictionary(grouping: components.filter { !$0.isEmpty }) { $0[0] }
        return groups.keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { key in
                let full = prefix + [key]
                let childComponents = groups[key]!
                    .map { Array($0.dropFirst()) }
                    .filter { !$0.isEmpty }
                return TagNode(
                    name: key,
                    fullPath: full.joined(separator: "/"),
                    children: nodes(from: childComponents, prefix: full)
                )
            }
    }
}
