//
//  MarpSlides.swift
//  HelloNotes
//
//  Created by Chris Tham on 12/7/2026.
//
//  Marp-style Markdown slides: a note with `marp: true` in its front matter,
//  whose body is split into slides on `---` separators. Each slide is rendered
//  to HTML for a deck preview; editing happens in the normal Markdown editor.
//

import Foundation
import Markdown

nonisolated enum MarpSlides {

    /// Whether the note opts into slides via `marp: true` front matter.
    static func isMarp(_ text: String) -> Bool {
        guard text.hasPrefix("---") else { return false }
        let rest = text.dropFirst(3)
        guard let end = rest.range(of: "\n---") else { return false }
        let front = rest[rest.startIndex..<end.lowerBound]
        return front.range(of: #"(?m)^\s*marp\s*:\s*true\s*$"#, options: .regularExpression) != nil
    }

    /// The body split into slides on lines that are exactly `---`.
    static func slides(_ text: String) -> [String] {
        let body = FrontMatter.body(of: text)
        var slides: [String] = []
        var current: [String] = []
        for line in body.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                slides.append(current.joined(separator: "\n"))
                current = []
            } else {
                current.append(line)
            }
        }
        slides.append(current.joined(separator: "\n"))
        return slides
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// A single slide rendered as a self-contained styled HTML page.
    static func slideHTML(_ markdown: String, dark: Bool) -> String {
        let body = HTMLFormatter.format(markdown)
        let bg = dark ? "#1c1c1f" : "#ffffff"
        let fg = dark ? "#ececf0" : "#16161a"
        let muted = dark ? "#9a9aa5" : "#6b6b76"
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
        html, body { margin: 0; height: 100%; }
        body {
          font: 27px/1.5 -apple-system, system-ui, "Segoe UI", sans-serif;
          padding: 6% 7%; box-sizing: border-box;
          background: \(bg); color: \(fg);
        }
        h1 { font-size: 2.1em; margin: 0 0 .35em; line-height: 1.15; }
        h2 { font-size: 1.5em; margin: .2em 0 .3em; }
        h3 { font-size: 1.2em; }
        ul, ol { padding-left: 1.15em; } li { margin: .22em 0; }
        p { margin: .35em 0; }
        a { color: #c026d3; }
        strong { color: inherit; }
        pre { background: rgba(127,127,127,.16); padding: .6em .8em; border-radius: 10px; overflow: auto; font-size: .78em; }
        code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
        blockquote { border-left: 4px solid #c026d3; margin: 0; padding-left: .8em; color: \(muted); }
        img { max-width: 100%; max-height: 62vh; }
        table { border-collapse: collapse; } th, td { border: 1px solid rgba(127,127,127,.5); padding: .3em .6em; }
        hr { display: none; }
        </style></head><body>\(body)</body></html>
        """
    }
}
