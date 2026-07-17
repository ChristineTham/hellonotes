//
//  GFMSpecTests.swift
//  GFMRenderTests
//
//  Full conformance to the GitHub Flavored Markdown specification
//  (https://github.github.com/gfm/). Every example in the spec's own
//  machine-readable corpus (spec.txt, 648 cases) is rendered through
//  GFMRenderer and compared to the expected HTML — the exact corpus cmark-gfm,
//  and therefore GitHub, is tested against.
//

import Foundation
import Testing
@testable import GFMRender

struct GFMExample: Sendable {
    let number: Int
    let section: String
    let markdown: String
    let html: String
}

enum GFMSpec {
    /// Parse the spec corpus into (markdown, expected-HTML) examples. `→`
    /// stands for a tab in the corpus (matching cmark's spec_tests.py).
    static func examples() throws -> [GFMExample] {
        let url = try #require(Bundle.module.url(forResource: "spec.txt", withExtension: nil))
        let text = try String(contentsOf: url, encoding: .utf8)
        var out: [GFMExample] = []
        var section = ""
        var number = 0

        let lines = text.components(separatedBy: "\n")
        var i = 0
        func isFence(_ s: String) -> Bool { !s.isEmpty && s.allSatisfy { $0 == "`" } && s.count >= 20 }
        func isExampleStart(_ s: String) -> Bool {
            s.hasSuffix(" example") && String(s.dropLast(" example".count)).allSatisfy { $0 == "`" } && !s.isEmpty
        }
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("#") {
                section = line.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            }
            if isExampleStart(line) {
                var md: [String] = []
                var html: [String] = []
                i += 1
                while i < lines.count, lines[i] != "." { md.append(lines[i]); i += 1 }
                i += 1 // skip "."
                while i < lines.count, !isFence(lines[i]) { html.append(lines[i]); i += 1 }
                number += 1
                out.append(GFMExample(
                    number: number,
                    section: section,
                    markdown: (md.joined(separator: "\n") + "\n").replacingOccurrences(of: "→", with: "\t"),
                    html: (html.isEmpty ? "" : html.joined(separator: "\n") + "\n").replacingOccurrences(of: "→", with: "\t")
                ))
            }
            i += 1
        }
        return out
    }

    /// The exact CommonMark-core examples whose *expected* output the GFM
    /// `tagfilter` and extended-`autolink` extensions deliberately override.
    /// GitHub renders these the extension way (verified live against
    /// api.github.com/markdown, 2026-07-17) — not the pre-extension core text.
    /// Every divergence from the corpus must be one of these; a new one is a
    /// real regression.
    static let extensionOverrides: Set<String> = [
        // tagfilter — `<script>` / `<style>` escaped for safety
        "<script type=\"text/javascript\">\n// JavaScript example\n\ndocument.getElementById(\"demo\").innerHTML = \"Hello JavaScript!\";\n</script>\nokay\n",
        "<style\n  type=\"text/css\">\nh1 {color:red;}\n\np {color:blue;}\n</style>\nokay\n",
        "<style\n  type=\"text/css\">\n\nfoo\n",
        "<style>p{color:red;}</style>\n*foo*\n",
        "<script>\nfoo\n</script>1. *bar*\n",
        // extended autolink — bare / spaced URLs & emails become links
        "<http://foo.bar/baz bim>\n",
        "<foo\\+@bar.example.com>\n",
        "< http://foo.bar >\n",
        "http://example.com\n",
        "foo@bar.example.com\n",
    ]
}

@Suite struct GFMSpecTests {

    @Test func fullSpecConformance() throws {
        let examples = try GFMSpec.examples()
        #expect(examples.count > 600, "expected the full corpus, got \(examples.count)")

        var unexpected: [(GFMExample, String)] = []
        var overridesHit = Set<String>()
        for ex in examples {
            let got = GFMRenderer.html(ex.markdown)
            guard got != ex.html else { continue }
            if GFMSpec.extensionOverrides.contains(ex.markdown) {
                overridesHit.insert(ex.markdown)   // expected divergence
            } else {
                unexpected.append((ex, got))
            }
        }

        let exact = examples.count - overridesHit.count - unexpected.count
        print("GFM spec conformance: \(exact) exact + \(overridesHit.count) GitHub-extension overrides = \(exact + overridesHit.count)/\(examples.count)")

        if !unexpected.isEmpty {
            print("--- UNEXPECTED divergences (\(unexpected.count)) ---")
            for (ex, got) in unexpected.prefix(20) {
                print("EXAMPLE \(ex.number) [\(ex.section)]")
                print("  markdown:  \(ex.markdown.debugDescription)")
                print("  expected:  \(ex.html.debugDescription)")
                print("  got:       \(got.debugDescription)")
            }
        }
        // No divergence beyond the documented GitHub-extension overrides.
        #expect(unexpected.isEmpty, "\(unexpected.count) unexpected GFM divergences")
        // Every documented override is still actually exercised (keeps the
        // allow-list honest — no stale entries silently masking regressions).
        #expect(overridesHit == GFMSpec.extensionOverrides,
                "stale override entries: \(GFMSpec.extensionOverrides.subtracting(overridesHit))")
    }
}
