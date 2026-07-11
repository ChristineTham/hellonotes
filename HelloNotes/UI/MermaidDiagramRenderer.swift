//
//  MermaidDiagramRenderer.swift
//  HelloNotes
//
//  Created by Chris Tham on 11/7/2026.
//

#if os(macOS)
import AppKit
import MarkdownEngine
import BeautifulMermaid

/// Renders ```` ```mermaid ```` fences to inline images for the editor, via
/// BeautifulMermaid (no WebView). Supplied to MarkdownEngine as its
/// `DiagramRenderer`; the engine collapses the fenced source and draws the
/// image in its place, revealing the source again when the caret enters.
///
/// MarkdownEngine restyles on every edit, so it calls `render` often. Results
/// are cached by source (misses included) so unchanged diagrams aren't
/// re-rendered. Called on the main thread during restyle, so the AppKit
/// `lockFocus` flip below is safe.
final class MermaidDiagramRenderer: MarkdownEngine.DiagramRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: MarkdownEngine.DiagramRenderResult?] = [:]

    func render(source: String, language: String, theme: MarkdownEditorTheme) -> MarkdownEngine.DiagramRenderResult? {
        guard language.lowercased() == "mermaid" else { return nil }

        lock.lock()
        if let cached = cache[source] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let result: MarkdownEngine.DiagramRenderResult?
        if let rendered = (try? MermaidRenderer.renderImage(source: source)) ?? nil,
           rendered.size.width > 0, rendered.size.height > 0 {
            let flipped = Self.flippedVertically(rendered)
            result = MarkdownEngine.DiagramRenderResult(image: flipped, size: flipped.size)
        } else {
            result = nil
        }

        lock.lock()
        cache[source] = result
        lock.unlock()
        return result
    }

    /// BeautifulMermaid renders into a Core Graphics context (bottom-left
    /// origin), so the resulting `NSImage` is upside down when shown top-left.
    /// Redraw it flipped so diagrams display right-way-up. (Mirrors the flip in
    /// `MermaidPreviewView`.)
    private static func flippedVertically(_ image: NSImage) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let flipped = NSImage(size: size)
        flipped.lockFocus()
        let transform = NSAffineTransform()
        transform.translateX(by: 0, yBy: size.height)
        transform.scaleX(by: 1, yBy: -1)
        transform.concat()
        image.draw(at: .zero, from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1)
        flipped.unlockFocus()
        return flipped
    }
}
#endif
