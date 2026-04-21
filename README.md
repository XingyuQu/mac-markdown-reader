# Markdown Reader

Native macOS Markdown reader built with SwiftUI and WebKit.

This project was vibe-coded with OpenAI Codex, then iterated locally to make it runnable as a standalone macOS app bundle.

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

- Split-view scroll sync is incomplete. `Preview -> Source` currently works more reliably than `Source -> Preview`.
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
