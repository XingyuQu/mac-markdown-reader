# Markdown Reader

Native macOS Markdown reader built with SwiftUI and WebKit.

This project was vibe-coded with OpenAI Codex, then iterated locally to make it runnable as a standalone macOS app bundle.

## Vibe Coding Takeaways

- Codex was effective for scaffolding the app, wiring the main architecture, and getting a native macOS prototype running quickly.
- The process was not fully smooth for product-level details. Several UI behaviors and edge cases did not land correctly in one shot and needed multiple rounds of iteration.
- The `Build macOS Apps` plugin helped with build, packaging, and general macOS workflow structure, but it did not remove the need for careful manual debugging of interaction details.
- A major friction point was UI debugging. Without a tight real-time loop where Codex could continuously inspect and operate the app UI during debugging, some issues had to be manually verified and then reported back by the user (computer-use may help?).

## Implemented

- Open a single Markdown file or an entire folder
- Sidebar with recent locations and a hierarchical Markdown file tree
- Preview, source, and split reading modes
- Outline panel generated from Markdown headings
- In-document search results
- Editable source view with save support
- Reading stats bar with word count, character count, and estimated reading time
- Persistent preferences for theme, font size, line width, and relaunch behavior
- Standalone app packaging via `script/build_and_run.sh`

## Not Yet Implemented

- Click-to-jump behavior for search results
- Syntax highlighting for fenced code blocks
- `Save As`, export, and print workflows
- Semantic sync between source and preview panes
- Full Markdown heading coverage in the outline parser
- Tests, code signing, notarization, and release packaging

## Known Bugs

- Split-view scroll sync is incomplete. `Preview -> Source` works, but `Source -> Preview` is still not reliable in the current build.
- Long documents with large tables or long code blocks can still drift out of alignment between panes.
- Outline parsing intentionally skips fenced code blocks, but it is still not a full Markdown parser and may miss some edge cases.

## Run

### Open as an app

```bash
./script/build_and_run.sh
```

This builds and launches `dist/MarkdownReader.app`.

### Open in Xcode

1. Open `Package.swift` in Xcode.
2. Let Xcode resolve the Swift package.
3. Choose the `MarkdownReader` target and run it as a macOS app.

## Repository Notes

- The app source is under `Sources/MarkdownReader`.
- Generated files such as `dist/`, `.build/`, `.codex/`, and local runtime state are intentionally gitignored.
