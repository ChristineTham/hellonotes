# HelloNotes — Implementation Plan

> Status: **Draft v1** · Last updated: 2026-07-11 · Companion to [PRD.md](PRD.md) and [architecture.md](architecture.md)

Milestone-based build sequence. Each milestone ends with a **green build** (`xcodebuild … build` → 0 errors) and, where noted, tests. Priorities map to the PRD (P0 = MVP).

---

## Milestone 0 — Foundation ✅ (done)
- `Note` model; `WorkspaceIndexer` (`@Observable`) with vault scan + `NSOpenPanel`.
- 3-column `MacContentView`; `WindowGroup` app entry with env injection.
- Project builds clean on macOS.

## Milestone 1 — Editing MVP (v0.1)  ← **this pass**
Goal: **select a vault → open a note → edit with live Markdown → auto-save to disk → create/delete notes.**

| # | Task | File(s) | Acceptance |
|---|---|---|---|
| 1.1 | Link `MarkdownEngine` + `MarkdownEngineCodeBlocks` products to the `HelloNotes` target | `project.pbxproj` | Target compiles with `import MarkdownEngine`. |
| 1.2 | `EditorModel` (`@Observable`): load file text, dirty tracking, **debounced autosave** (atomic write), flush on note-switch/termination | `State/EditorModel.swift` | Edits hit disk ≤1s after typing stops; kill-mid-edit leaves file intact. |
| 1.3 | `NoteEditorView` hosting `NativeTextViewWrapper` with the code-highlight bridge; saved/unsaved indicator | `UI/NoteEditorView.swift` | Typing renders live; code blocks highlight. |
| 1.4 | Wire selection: selecting a note in col 2 loads it into the editor in col 3 | `MacContentView.swift` | Clicking a note shows its content, editable. |
| 1.5 | File ops on `WorkspaceIndexer`: `createNote(title:)`, `deleteNote(_:)` (to Trash), rescan | `WorkspaceIndexer.swift` | New note appears in list & Finder; delete moves to Trash. |
| 1.6 | Sidebar actions: "New Note", title filter field | `MacContentView.swift` | New note button works; filter narrows the list. |
| 1.7 | Persist vault via **security-scoped bookmark**; restore on launch | `WorkspaceIndexer.swift` | Relaunch reopens the last vault automatically. |
| 1.8 | Build gate + smoke test of autosave round-trip | tests | 0 errors/0 warnings; round-trip test passes. |

**MVP done-when:** open an existing folder of `.md` files, edit any note with live formatting and code highlighting, changes auto-persist, and new/deleted notes reflect on disk — all reopening cleanly on relaunch.

## Milestone 2 — Knowledge graph & math (v0.2)  ✅ (done)  [P1]
- ✅ Added `MarkdownEngineLatex` + `Markdown` (swift-markdown) to the target.
- ✅ `Core/MarkdownParsing` extracts `[[wiki-links]]` (regex), headings (swift-markdown AST), `#tags` (regex).
- ✅ `LinkGraph` (`@Observable`): async backlink index, rebuilt off-main on note-set / save changes.
- ✅ Backlinks panel in the editor column; navigation between linked notes.
- ✅ LaTeX rendering (SwiftMath bridge).
- ✅ Wiki-link click → navigate. **Required a `VaultWikiLinkResolver`**: MarkdownEngine only makes a `[[Name]]` clickable when a `WikiLinkResolver` reports the target `exists`. The resolver reports existence only (empty `id`) so the editor never rewrites `[[Name]]` → `[[Name|id]]` — files stay byte-for-byte intact. Existing targets are underlined/clickable; unknown targets render muted.
- Follow-ups: create-on-miss by clicking a muted link (the package doesn't fire the callback for non-existent targets); incremental (per-note) graph updates instead of full rebuilds; `#tags` index UI.

## Milestone 3 — Search & navigation (v0.2–0.3)  [P1]
- Full-text workspace search; results list.
- "Open Quickly" fuzzy finder (⌘O) over files + headings.
- Folder tree with sort options; external-change detection via `FileWatcher` (FSEvents).

## Milestone 4 — Git sync (v0.3)  [P1]
- `Core/GitEngine` + `GitService` actor over SwiftGitX.
- Repo status in the sidebar; background auto-commit (debounced) + "Sync now".
- Push/pull to remote; surface conflicts (P2 resolution UI).

## Milestone 5 — Native rendering polish (v0.3+)  [P1/P2]
- Mermaid code blocks → native diagrams (beautiful-mermaid-swift).
- Tables UX, footnotes, front-matter panel, image paste → asset folder.

## Milestone 6 — iOS shell (v0.4)  [P2]
- Extract Core/State into platform-agnostic form.
- `iOSContentView` with `NavigationStack`; verify shared models compile for iOS.

---

## Sequencing notes
- **1.1 is the gate** for everything else in Milestone 1 — without linking the MarkdownEngine products, the editor can't build.
- Keep new Core/State/UI types in subfolders (`Core/`, `State/`, `UI/`) inside the synchronized `HelloNotes/` group so Xcode picks them up automatically.
- Each task is small enough to build-verify independently; never batch two risky changes without a build in between.

## Definition of done (every milestone)
1. `xcodebuild -scheme HelloNotes -destination 'platform=macOS' build` → **BUILD SUCCEEDED**, 0 warnings in app sources.
2. New logic has at least a smoke test where it's testable off-UI.
3. Docs updated if the design changed.
