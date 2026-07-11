# HelloNotes — Product Requirements Document

> Working product name: **NoteLens** · Status: **Draft v1 (MVP definition)** · Last updated: 2026-07-11 · Owner: Chris Tham

---

## 1. Overview

HelloNotes is a **native, local-first Markdown knowledge base for the Apple ecosystem** — a fast, tactile alternative to Electron apps like Obsidian and cross-platform editors like Typora. Notes are plain `.md` files in a folder on disk ("the vault"); that folder is the single source of truth. There is no proprietary database and no cloud lock-in. Synchronisation happens invisibly through Git.

The product bet: a knowledge tool built on **AppKit + TextKit 2 + SwiftUI** can deliver editing latency, scroll performance, and OS integration that web-tech competitors structurally cannot, while keeping the user's data in an open, portable, greppable format they fully own.

This document defines the product vision, the users, and a scoped **MVP (v0.1)**, plus the roadmap beyond it. Technical design lives in [architecture.md](architecture.md); the build sequence lives in [implementation-plan.md](implementation-plan.md).

## 2. Problem statement

Knowledge workers who write in Markdown face a trade-off today:

- **Obsidian** is powerful and local-first, but Electron-based: heavy memory use, non-native text handling, and a plugin ecosystem that trends toward complexity.
- **Typora / Vellum** offer a beautiful focused writing experience, but are single-document-centric and weaker as a linked *knowledge base*.
- **Bear / Apple Notes** are native and fast, but store notes in opaque databases — the user does not own portable files, and Git-based versioning is impossible.
- **VS Code + Markdown** is developer-friendly but is a code editor, not a writing environment.

No tool today combines: **(a)** genuinely native macOS performance and feel, **(b)** plain-files-on-disk ownership, **(c)** first-class Git sync, and **(d)** a linked knowledge graph (`[[wiki-links]]` + backlinks).

## 3. Target users & personas

| Persona | Description | Primary need |
|---|---|---|
| **The Developer-Writer** (primary) | Engineers who keep technical notes, design docs, and daily logs in Markdown and already live in Git. | Native speed, code-block fidelity, Git sync they trust, files they can `grep`. |
| **The Researcher / PKM enthusiast** | Academics and note-takers building a "second brain" of interlinked notes. | Wiki-links, backlinks, math, fast search across a large vault. |
| **The Obsidian refugee** | Users who value local-first but want native performance and OS integration. | Import an existing vault of `.md` files and have it "just work". |

**Anti-persona:** users who want a hosted, collaborative, real-time multiplayer doc (Notion/Google Docs). HelloNotes is single-user, local-first, async-sync.

## 4. Goals & non-goals

### Product goals
1. **Own your data** — every note is a human-readable `.md` file; the vault is a normal folder that works with Finder, Git, and any other tool.
2. **Native performance** — sub-frame typing latency; smooth scrolling on large documents; low memory footprint.
3. **Frictionless capture & edit** — open the app, land in a note, type. Auto-save; never lose work.
4. **Linked thinking** — `[[wiki-links]]` and backlinks make the vault a graph, not a pile of files.
5. **Invisible sync** — Git commits/pulls happen in the background without the user thinking about Git.

### Non-goals (explicitly out of scope)
- No proprietary storage: **no CoreData, no SwiftData, no iCloud document store.**
- No WebViews / Electron / embedded browser for rendering (Mermaid, math, and code all render natively).
- No real-time collaboration or hosted backend.
- No plugin runtime in the MVP (extensibility is a deliberate later question, à la Vellum's "pure editor" stance).
- No proprietary sync service — sync is the user's own Git remote.

## 5. Product principles
1. **The file system is the truth.** UI state is a projection of disk; disk is never a projection of a hidden DB.
2. **Native or nothing.** If a feature would require a WebView, we find the native path or defer it.
3. **Fast is a feature.** Latency and jank are bugs.
4. **Portable by default.** A user must be able to walk away with their folder and lose nothing.
5. **Progressive disclosure.** Simple by default; power features stay out of the way until summoned.

## 6. Competitive reference — Vellum
[Vellum](https://github.com/wzzc-dev/vellum) (a Rust/gpui Typora-style editor) is a strong reference for the *editing experience* we want to match natively. Features we draw from it:

- Live WYSIWYG Markdown with a source ⇄ preview toggle.
- File-tree sidebar with sort options (name, natural, modified time).
- Multi-tab editing in one window.
- Workspace-wide search (incl. hashtags) and "Open Quickly" for files/headings.
- Native Mermaid, math, code highlighting, tables, task lists, footnotes.
- Auto-save, command palette, find/replace, front-matter panel, external-change detection.

Where we **diverge**: HelloNotes adds the *knowledge-graph* layer (wiki-links + backlinks) and *Git sync* that Vellum intentionally omits, and targets the Apple-native stack rather than Rust/gpui.

## 7. Feature requirements

Priority: **P0 = MVP (v0.1)**, **P1 = fast-follow (v0.2–0.3)**, **P2 = roadmap**.

### 7.1 Vault & file management
- **P0** Select a vault folder; remember it across launches (security-scoped bookmark).
- **P0** List/browse `.md`, `.markdown`, `.mdown` files in the vault.
- **P0** Create a new note; rename; delete (to Trash, not hard-delete).
- **P1** Nested folder tree with expand/collapse and sort (name / modified).
- **P1** Detect external file changes and reconcile (reload / conflict prompt).
- **P2** Drag-and-drop and paste images into a configurable asset folder.

### 7.2 Editor (the core)
- **P0** Open a note into a live TextKit 2 Markdown editor (MarkdownEngine `NativeTextViewWrapper`).
- **P0** Live inline formatting (bold/italic/code), headings, lists, task lists, quotes.
- **P0** Auto-save edits back to the file (debounced), with an unsaved/saved indicator.
- **P0** Syntax-highlighted fenced code blocks (via the HighlighterSwift bridge).
- **P1** Inline and block **LaTeX** math (via the SwiftMath bridge).
- **P1** Source ⇄ live-preview toggle; find/replace within a note.
- **P2** Tables editing UX, footnotes, front-matter panel.

### 7.3 Knowledge graph
- **P1** Parse `[[wiki-links]]`; click to navigate (create-on-miss).
- **P1** Backlinks panel: "notes that link here", computed asynchronously.
- **P2** Tags (`#tag`) index and filtering.
- **P2** Local graph view.

### 7.4 Search & navigation
- **P0** Filter the note list by title.
- **P1** Full-text workspace search.
- **P1** "Open Quickly" fuzzy finder for files and headings (⌘O / ⌘P).
- **P2** Multi-tab editing.

### 7.5 Git sync
- **P1** Detect that the vault is (or can be) a Git repo; show status.
- **P1** Background auto-commit on a debounce; manual "Sync now".
- **P2** Push/pull to a remote; surface and resolve merge conflicts.

### 7.6 Rendering (native, no WebView)
- **P1** Mermaid diagrams rendered natively (beautiful-mermaid-swift).
- **P1** Math (SwiftMath). **P0** Code highlighting (HighlighterSwift).

### 7.7 Platform
- **P0** macOS 14+ 3-column shell (`NavigationSplitView`).
- **P2** iOS/iPadOS shell (`NavigationStack`), sharing the Core/State layers.

## 8. Key user stories (MVP)
1. *As a new user,* I pick a folder of Markdown files and immediately see them listed, so I can start working with my existing notes.
2. *As a writer,* I click a note and type; formatting renders live and my changes save automatically, so I never think about saving or lose work.
3. *As a developer,* I paste a code block and it's syntax-highlighted natively, so my technical notes are readable.
4. *As a returning user,* I reopen the app and my vault and last note are still there, so I resume instantly.
5. *As a note-keeper,* I create and delete notes from within the app, and the changes are reflected as real files in Finder.

## 9. UX overview (MVP)
Three-column macOS layout:
- **Sidebar (col 1):** vault name + note count, "Select Vault", "New Note", search field.
- **List (col 2):** notes (title + modified date), selectable; sort by modified desc by default.
- **Editor (col 3):** the live Markdown editor for the selected note, with a saved/unsaved indicator; empty-state when nothing is selected.

## 10. Success metrics
- **Performance:** typing latency < 16 ms (60fps) on a 5k-word note; vault scan of 1,000 notes < 300 ms.
- **Reliability:** zero data-loss incidents in auto-save across a test corpus (crash/kill during edit → file intact).
- **Fidelity:** a round-trip open → edit → save produces a byte-diff limited to the user's actual change (no reformatting of untouched content).
- **Adoption proxy:** an existing Obsidian vault opens and is fully browsable/editable with no migration step.

## 11. Constraints (from project rules)
- Target: **macOS 14+ / Swift 5.10+ / Xcode 26**; multiplatform-ready.
- State via the **`@Observable` macro only** (no `ObservableObject`/`StateObject`).
- **No CoreData/SwiftData** — the file system is the source of truth.
- Git via **SwiftGitX** (async/await).
- Every code change must compile clean (0 errors) before it's considered done.

## 12. Open questions
1. **Preview model:** full source⇄preview toggle, or always-live inline styling (MarkdownEngine leans live)? *Leaning live-inline for MVP.*
2. **Auto-commit cadence:** time-based, on-close, or on explicit action? *Leaning debounced + manual for v0.2.*
3. **Wiki-link create-on-miss:** which folder do new linked notes land in?
4. **Extensibility:** do we ever want a plugin surface, or hold Vellum's "pure editor" line?
5. **iOS timing:** how much Core/State can we keep truly platform-agnostic to make the iOS shell cheap later?
