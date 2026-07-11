# HelloNotes — Architecture & Technology Evaluation

> Status: **Draft v1** · Last updated: 2026-07-11 · Companion to [PRD.md](PRD.md) and [implementation-plan.md](implementation-plan.md)

This document describes the software architecture of HelloNotes and evaluates the third-party Swift packages the app depends on. For each capability we consider the realistic alternatives, then give a recommendation. The project **already has** a set of packages resolved (see §5); this document justifies keeping them and identifies the wiring still required.

---

## 1. Architectural overview

HelloNotes uses a strict **4-layer architecture** so that the macOS app today and the iOS app later can share everything except the platform shell. Data flows in one direction: the file system is the source of truth, the Core layer reads/writes it, State projects it as observable values, and the UI renders State.

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 4 — Platform Shells                                   │
│    macOS: NavigationSplitView (3 columns)                    │
│    iOS:   NavigationStack (push)          [#if os(...)]       │
├─────────────────────────────────────────────────────────────┤
│  Layer 3 — Shared UI Components                              │
│    Editor host (MarkdownEngine), note list rows, backlinks   │
│    panel, search field, status/sync indicators               │
├─────────────────────────────────────────────────────────────┤
│  Layer 2 — State Management  (@Observable)                   │
│    WorkspaceIndexer (vault + notes), EditorModel (open doc,  │
│    autosave), LinkGraph (wiki-links/backlinks), GitService   │
├─────────────────────────────────────────────────────────────┤
│  Layer 1 — Core / Domain  (pure Swift, UI-agnostic)         │
│    VaultStore (FileManager + security-scoped bookmarks),     │
│    MarkdownParsing (swift-markdown AST), GitEngine           │
│    (SwiftGitX), FileWatcher (DispatchSource/FSEvents)        │
└─────────────────────────────────────────────────────────────┘
             ▲                                   │
             │  reads/writes                     │ observes
             └──────────  File System (the vault, .md files)
```

**Rules that keep the layers honest**
- Layer 1 imports **no SwiftUI/AppKit** (except where a package forces it) — it is unit-testable in isolation.
- Layer 2 is the only place that holds mutable app state, and it uses the **`@Observable` macro exclusively** (no `ObservableObject`).
- Layers 3–4 never touch `FileManager` or Git directly; they call into State.
- Long-running work (scan, parse, Git, file-watch) runs off the main actor and hands results back via `@MainActor`.

## 2. Concurrency model
- The app adopts Swift structured concurrency (`async/await`, `Task`).
- **@Observable models are `@MainActor`.** They spawn detached work for scanning, parsing, and Git, then mutate observable state back on the main actor.
- Autosave is **debounced** (write coalesced ~500 ms after the last keystroke, plus a flush on note-switch / app-resign / termination) to avoid write amplification and data loss.
- Git operations are serialized through a single actor (`GitService`) so commits/pulls never overlap.

## 3. Data model (Core)
- `Note` — value type: `id`, `title`, `fileURL`, `lastModified` (already implemented).
- `Vault` — the selected root URL plus its security-scoped bookmark for persistence.
- `NoteDocument` — in-memory editing buffer: `fileURL`, `text`, `isDirty`, `lastSavedText`.
- `LinkGraph` — `[noteID: Set<targetTitle>]` forward links and the inverted backlink index, rebuilt asynchronously on save.

## 4. Persistence strategy
- **No database.** Note content lives in `.md` files.
- **Security-scoped bookmarks** persist vault access across launches (sandbox-friendly), stored in `UserDefaults`. On launch we resolve the bookmark, call `startAccessingSecurityScopedResource()`, and re-scan.
- Lightweight UI preferences (last-opened note, sort order, sidebar width) live in `UserDefaults` / `@AppStorage` — these are *caches*, never the source of truth.

## 5. Package evaluation

The guiding principle from the project rules: **native Apple frameworks first, zero WebViews, async/await.** Below, each capability is evaluated against alternatives.

### 5.1 Markdown editor / live renderer  ⟶ **MarkdownEngine** ✅ (installed)
The heart of the app: a live TextKit 2 editor that styles Markdown as you type.

| Option | Notes | Verdict |
|---|---|---|
| **`swift-markdown-engine` (MarkdownEngine)** | Native **TextKit 2** `NSTextView` bridged to SwiftUI via `NativeTextViewWrapper`; live inline styling, tables, task lists, code-block buttons, **wiki-link** hooks (`isWikiLinkActive`, `onLinkClick`), image-paste hook, scroll-away header, per-document undo. Ships optional bridges for code highlighting and LaTeX. | **Recommended.** Purpose-built for exactly this app; matches the "native, live, TextKit 2" mandate. |
| MarkdownUI | Excellent **read-only** renderer (SwiftUI). No editing. | Rejected — preview-only. |
| Down / Ink / cmark wrappers | Parse/convert to HTML or attributed string; no live editor. | Rejected — not an editor. |
| Hand-rolled TextKit 2 editor | Full control, but months of work to reach parity (inline styling, undo, tables, code blocks). | Rejected for MVP; MarkdownEngine already solves it. |

**Wiring required:** the app target currently does **not** link the MarkdownEngine products. We must add `MarkdownEngine` (+ optional `MarkdownEngineCodeBlocks`, `MarkdownEngineLatex`) to the target's package product dependencies.

### 5.2 Markdown AST parsing (links, headings, tags)  ⟶ **swift-markdown** ✅ (installed)
Used by the Core layer for structural parsing that the editor doesn't give us — extracting `[[wiki-links]]`, headings (for "Open Quickly"), and `#tags`.

| Option | Notes | Verdict |
|---|---|---|
| **`swift-markdown`** (Apple / swiftlang) | Official GFM parser over `cmark-gfm`; stable `Markup` AST; maintained by Apple. | **Recommended.** Authoritative, already a transitive/declared dependency. |
| Ink (JohnSundell) | Fast, pure-Swift, but Markdown→HTML, no rich AST. | Rejected — no AST for link/heading extraction. |
| Direct cmark-gfm C API | Maximum control, C ergonomics. | Rejected — swift-markdown wraps it cleanly. |

### 5.3 Git engine  ⟶ **SwiftGitX** ✅ (installed)
| Option | Notes | Verdict |
|---|---|---|
| **`SwiftGitX`** | Modern **async/await** wrapper over `libgit2`; Swift-native types; actively maintained. | **Recommended** — mandated by project rules and fits the concurrency model. |
| SwiftGit2 / ObjectiveGit | Older, callback/blocking or Obj-C; libgit2 too. | Rejected — dated ergonomics. |
| Shell out to `/usr/bin/git` | Zero deps, trivial. But brittle (parsing porcelain), needs Git installed, sandbox-hostile. | Rejected for the core; may be a debugging fallback. |

### 5.4 Code-block syntax highlighting  ⟶ **HighlighterSwift** ✅ (installed, via bridge)
| Option | Notes | Verdict |
|---|---|---|
| **HighlighterSwift** (highlight.js core, native rendering) | Plugs into MarkdownEngine via `MarkdownEngineCodeBlocks` → `HighlighterSwiftBridge`; auto light/dark themes; broad language coverage. | **Recommended** — first-party bridge already exists. |
| Splash | Beautiful, but **Swift-only** highlighting. | Rejected — need many languages. |
| Custom tree-sitter | Best-in-class, heavy integration cost. | Deferred (P2). |

### 5.5 Math rendering  ⟶ **SwiftMath** ✅ (installed, via bridge)
| Option | Notes | Verdict |
|---|---|---|
| **SwiftMath** | Native LaTeX math typesetting (no WebView); plugs in via `MarkdownEngineLatex` → `SwiftMathBridge`. | **Recommended** — native, first-party bridge. |
| iosMath | Obj-C predecessor of SwiftMath. | Rejected — SwiftMath supersedes it. |
| KaTeX in WebView | Violates the no-WebView rule. | Rejected. |

### 5.6 Mermaid diagrams  ⟶ **beautiful-mermaid-swift** ✅ (installed)
| Option | Notes | Verdict |
|---|---|---|
| **beautiful-mermaid-swift** | Parses Mermaid → native rendering (uses `elk-swift` for graph layout); **no browser engine**. | **Recommended** — only native option; satisfies the no-WebView rule. |
| mermaid.js in WKWebView | Full Mermaid support but a WebView. | Rejected (rule). Kept in mind only as an emergency fallback for unsupported diagram types. |

### 5.7 File-change watching  ⟶ **native (no package)** ✅
| Option | Notes | Verdict |
|---|---|---|
| **`DispatchSource` (vnode) / `FSEvents`** | OS-level; zero deps; battle-tested. | **Recommended** — Core `FileWatcher` wraps FSEvents for the vault directory. |
| Third-party watchers | Unnecessary dependency. | Rejected. |

### 5.8 Fuzzy search / "Open Quickly"  ⟶ **native for MVP** ✅
| Option | Notes | Verdict |
|---|---|---|
| **Hand-rolled subsequence/fuzzy match** | A few hundred lines; fine for a personal vault. | **Recommended** for MVP. |
| Full-text index (SQLite FTS / custom) | Needed only at very large scale. | Deferred (P2) — and even then, an *index cache*, never the source of truth. |

## 6. Dependency summary

| Package | Capability | Status | Linked to app target? |
|---|---|---|---|
| swift-markdown-engine (`MarkdownEngine`) | Live TextKit 2 editor | Resolved | **No — must add** |
| ↳ `MarkdownEngineCodeBlocks` | Code highlighting bridge | Resolved | **No — must add (P0)** |
| ↳ `MarkdownEngineLatex` | Math bridge | Resolved | **No — must add (P1)** |
| swift-markdown | GFM AST parsing | Resolved | Add when Core parsing lands (P1) |
| SwiftGitX | Git async engine | Resolved | **Yes** |
| beautiful-mermaid-swift (`BeautifulMermaid`, `MermaidPlayground`) | Native Mermaid | Resolved | **Yes** |
| HighlighterSwift | Highlighting (via bridge) | Resolved (transitive) | Via bridge |
| SwiftMath | Math (via bridge) | Resolved (transitive) | Via bridge |
| elk-swift, swift-cmark, libgit2, swift-collections | Transitive deps | Resolved | Transitive |

> **Key finding:** the single most important wiring gap for the MVP is that **`MarkdownEngine` and `MarkdownEngineCodeBlocks` are resolved but not yet linked to the `HelloNotes` target.** The editor cannot be built until they are added to the target's `packageProductDependencies` and Frameworks build phase.

## 7. Module map (target code)

| Layer | Type | File | Responsibility |
|---|---|---|---|
| 1 Core | `VaultStore` | `Core/VaultStore.swift` | Scan vault, CRUD `.md` files, bookmark persistence |
| 1 Core | `FileWatcher` | `Core/FileWatcher.swift` | FSEvents wrapper (P1) |
| 1 Core | `MarkdownParsing` | `Core/MarkdownParsing.swift` | swift-markdown AST → links/headings/tags (P1) |
| 1 Core | `GitEngine` | `Core/GitEngine.swift` | SwiftGitX operations (P1) |
| 2 State | `WorkspaceIndexer` | `WorkspaceIndexer.swift` | Vault + notes (exists; refactor onto VaultStore) |
| 2 State | `EditorModel` | `State/EditorModel.swift` | Open document, dirty tracking, debounced autosave |
| 2 State | `LinkGraph` | `State/LinkGraph.swift` | Forward links + backlinks (P1) |
| 3 UI | `NoteEditorView` | `UI/NoteEditorView.swift` | Hosts `NativeTextViewWrapper` |
| 3 UI | `NoteListView` | `UI/NoteListView.swift` | Note rows, sort, filter |
| 4 Shell | `MacContentView` | `MacContentView.swift` | 3-column macOS shell (exists) |
| 4 Shell | `iOSContentView` | `iOSContentView.swift` | `NavigationStack` (P2) |

## 8. Testing strategy
- **Core is unit-tested** without UI: vault scan on a temp directory, CRUD, parser link extraction, autosave round-trip (write → read → byte-compare).
- **Data-loss tests:** simulate app-resign / termination mid-edit → assert file matches buffer.
- **Build gate:** every increment compiles with 0 errors/0 warnings via `xcodebuild` (or the Xcode MCP build check) on the macOS destination before merge.

## 9. Risks & mitigations
| Risk | Mitigation |
|---|---|
| MarkdownEngine API churn (early-stage package) | Pin the resolved version; isolate usage behind `NoteEditorView`. |
| Autosave data loss | Debounce + flush-on-transition; write to temp then atomic replace; unit tests. |
| App Sandbox blocks arbitrary vault access | Security-scoped bookmarks; user-selected folder grants scope. |
| Large vault scan jank | Off-main enumeration; incremental updates via FileWatcher. |
| Mermaid coverage gaps in native renderer | Render supported diagram types; degrade gracefully to source for unsupported ones. |
