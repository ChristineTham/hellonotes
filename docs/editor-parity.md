# New editor — parity tracker

*Old engine (`swift-markdown-engine` fork) vs the in-repo engine
(`Packages/NotesEditor`), toggled in Settings → General → Editor. The fork
is removed when every ⚠/✗ that matters is ✓ (M4 in docs/editor-rewrite.md).*

Updated 2026-07-17 (M1).

| Area | Status | Notes |
|---|---|---|
| Live block styling (headings, lists, tasks, quotes, callout tint, fences, tables-as-text, HR, front matter) | ✓ | via MarkdownCore StyleSpec |
| Inline styling (bold/italic/strike/highlight/code/math-source/comments/tags/footnotes) | ✓ | |
| Syntax concealment + caret reveal | ✓ | block-granularity reveal |
| Wiki links: resolved/broken tint, click-to-navigate, aliases, `#heading` targets | ✓ | existence via linkCandidates |
| URLs: live links, click to open | ✓ | |
| Autosave / conflicts / external reload | ✓ | via EditorModel bridge (`loadRevision`, `willFlush`) |
| Undo/redo per document | ✓ | stock NSUndoManager against raw storage |
| Caret autoscroll while typing | ✓ | standard NSTextView behavior, nothing fights it |
| Large-note performance | ✓✓ | the rewrite's reason to exist; see numbers in editor-rewrite.md |
| Find (⌘F) | ⚠ | native NSTextView find bar works *inside the editor*, but the app's FindReplaceBar (and its bus) isn't wired to the new engine yet |
| `[[wiki]]` / `#tag` autocomplete popup | ✗ | M2 — needs inline-context reporting + caret rect |
| Format menu commands (bold/italic/…, headings, lists) | ✗ | M2 — document command API |
| Image paste → attachment, smart paste (HTML→md) | ✗ | M2 — paste intents |
| Code-block syntax highlighting (async upgrade) | ✗ | M2 |
| Scroll-to-heading (outline, `[[Note#h]]`, search hits) | ✗ | M2 — `reliablyScroll(to:)` exists, needs app wiring |
| Rendered embeds: `![[image]]`, block LaTeX, Mermaid, transclusion cards | ✗ | M3 — fragment drawing |
| Inline LaTeX rendered as image | ✗ | M3+; styled source meanwhile |
| Callout collapse, front-matter fold | ✗ | M3 |
| Task checkbox click-toggle | ✗ | M3 |
| Table grid chrome / wide-table scrolling | ✗ | M3; aligned text + dimmed pipes meanwhile |
| Writing Tools config, Continuity Camera routing | ✗ | arrives with native-roadmap Phase A, on the new engine |
| Preview mode on new engine | ✗ | M4 — same view, `editable(false)`; old engine renders Preview until then |
| iOS editor | ✗ | M5 — UITextView(usingTextLayoutManager:) on the same kernel |
