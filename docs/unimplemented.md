# Unimplemented & Deferred

> As of **v1.0**. A running register of everything scoped, approved, or attempted but
> **not** shipped, with the reason and what would unblock it. Revisit periodically.
> (Everything that *was* deferred and later shipped now lives in
> [implemented.md](implemented.md) — including the entire set of former "editor engine"
> limitations, which the [`Packages/NotesEditor`](../Packages/NotesEditor) rewrite resolved.)

Each item is tagged by what's blocking it:

- 🛠️ **Backlog** — buildable with what we have; just not done yet.
- 🍎 **iOS parity** — exists on macOS, not yet on iOS/iPadOS.
- ⬆️ **Upstream** — blocked by a missing capability in a dependency (e.g. `SwiftGitX`).
- 🔒 **By policy** — intentionally not done for safety/architecture reasons.

---

## Editor

The editor rewrite (`Packages/NotesEditor`) closed every editor limitation the old
markdown-engine fork had (scroll-to-heading, callouts, inline Mermaid, tag autocomplete,
front-matter hiding, in-editor create-on-miss link clicks, transclusion — all shipped;
see [implemented.md](implemented.md)). What remains:

- 🍎 **Rich iOS editor** — the live TextKit 2 editor is wired **macOS-only** (`NewEditorHost`); iOS/iPadOS still use a plain-text `TextEditor` (sharing the same `EditorModel`, autosave, and conflict logic). This is **no longer an engine wall** — the `MarkdownEditor` target already has a `UITextView(usingTextLayoutManager:)` path on the shared kernel. **Unblock:** wire that `UITextView` editor into the iOS shell (tracked as editor-M5).
- 🛠️ **Live transclusion** — `![[Note]]` / `![[Note#heading]]` embeds render as a **static image card**, refreshed on the source note's change. Nested callouts and live text selection *inside* a transclusion aren't supported. **Unblock:** a nested live-layout embed (a bigger fragment-composition effort).
- 🛠️ **Emoji shortcodes & raw HTML entities** — `:smile:` and `&amp;copy;` render as literal text (as they do in raw GitHub *source*), not as the glyphs GitHub.com substitutes at display time. Low value; a small table-driven pass would cover the common cases.

---

## iOS / iPadOS parity

The iOS/iPadOS build is a browse / **rendered-preview** / plain-text-edit companion (GFM
Preview via `WKWebView`, view modes, and a settings sheet for theme/accent/text size).
These exist on macOS but not yet on iOS:

- 🍎 **Live editor** (see above).
- 🍎 **macOS-only surfaces** — FSEvents external-change watching, "Open Quickly" (⇧⌘O), the tags sidebar tree, the Git UI, image paste → assets, Mermaid preview, document statistics, the outline, HTML/PDF export, multi-tab editing, version history, wiki-link autocomplete, open-in-new-window, the Graph/Mind Map/Slides views, the file viewer, and the whole AI stack (Assistant / Ask Library / Intelligence). The shared `Core`/`State` layers are cross-platform and can back iOS UIs later.

---

## Git / sync

- ⬆️ **Pull / merge** — SwiftGitX exposes `fetch` and `push` but no merge, so there is no true "pull." Fetch updates refs; the user merges externally. **Unblock:** a merge API in SwiftGitX (or a libgit2 merge implemented ourselves).
- 🛠️ **Merge-conflict resolution UI** — depends on merge existing first. No UI to resolve conflicting hunks.
- 🛠️ **Push smoke test** — HTTPS-token push against a real remote (`GitCredentials` + `GitHostAPI`) deserves one more manual smoke test on a fresh machine before it's advertised. SSH remotes still rely on libgit2's ambient credentials.

---

## Performance / architecture

- 🛠️ **Silent write failures in two batch paths** — `Collection.rewriteWikiLinks` and `MacContentView.linkMention` use `try?` writes (`Collection.swift:431`, `MacContentView.swift:1063`), so a failed write (permissions, disk full) silently skips a note. **Fix:** surface errors and report which notes weren't updated.
- 🛠️ **Timing-based scroll-to-heading hand-off** — the "open note → find heading → clear highlight" flow still sequences with fixed delays (350 ms switch settle + a 1.2 s highlight clear, `MacContentView.scrollToHeading`). The editor's *scroll itself* is now TextKit 2-safe (`ensureLayout` + segment frame), but the cross-view hand-off can still miss on a slow note load. **Fix:** replace the delays with an editor-ready signal.
- 🛠️ **English-only** — `Localizable.xcstrings` is empty; UI copy is inline literals. Run string extraction if localisation is ever wanted.

---

## Notes for revisiting

- 🛠️ **Backlog** items are the cheapest wins — they need no upstream changes.
- The largest single gap is the **iOS live editor**; the kernel already supports it, so it's shell-wiring, not new engine work.
