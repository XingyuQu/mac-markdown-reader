import SwiftUI

struct ContentView: View {
    @ObservedObject var model: ReaderViewModel
    @EnvironmentObject private var settings: ReaderSettings

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
        } detail: {
            VStack(spacing: 0) {
                if let errorMessage = model.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(errorMessage)
                            .font(.callout)
                            .lineLimit(2)
                        Spacer()
                        Button("Dismiss") {
                            model.clearError()
                        }
                    }
                    .padding(10)
                    .background(.yellow.opacity(0.15))
                }

                if model.selectedFileURL == nil {
                    EmptyStateView(model: model)
                } else {
                    ReaderPane(model: model)
                }

                if settings.showMetadataBar {
                    MetadataBar(
                        stats: model.stats,
                        selectedFileURL: model.selectedFileURL,
                        isDocumentEdited: model.isDocumentEdited
                    )
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        model.openFilePanel()
                    } label: {
                        Label("Open File", systemImage: "doc.badge.plus")
                    }

                    Button {
                        model.openFolderPanel()
                    } label: {
                        Label("Open Folder", systemImage: "folder.badge.plus")
                    }

                    Button {
                        model.reload()
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }

                    Button {
                        model.saveDocument()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .disabled(!model.canSaveDocument)
                }

                ToolbarItem {
                    Picker("Layout", selection: $model.layout) {
                        ForEach(ReaderLayout.allCases) { layout in
                            Label(layout.title, systemImage: layout.systemImage)
                                .tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                ToolbarItem {
                    SearchField(text: $model.searchQuery)
                        .frame(width: 220)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct ReaderPane: View {
    @ObservedObject var model: ReaderViewModel
    @EnvironmentObject private var settings: ReaderSettings
    @StateObject private var splitScrollBridge = SplitScrollBridge()

    var body: some View {
        HStack(spacing: 0) {
            Group {
                switch model.layout {
                case .preview:
                    PreviewPane(
                        html: model.renderedHTML,
                        baseURL: model.selectedFileURL?.deletingLastPathComponent(),
                        navigationRequest: model.previewNavigationRequest,
                        scrollBridge: splitScrollBridge
                    )
                case .split:
                    HSplitView {
                        SourcePane(model: model, text: model.markdownSource, scrollBridge: splitScrollBridge)
                        PreviewPane(
                            html: model.renderedHTML,
                            baseURL: model.selectedFileURL?.deletingLastPathComponent(),
                            navigationRequest: model.previewNavigationRequest,
                            scrollBridge: splitScrollBridge
                        )
                    }
                case .source:
                    SourcePane(model: model, text: model.markdownSource, scrollBridge: splitScrollBridge)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if settings.showOutline {
                Divider()
                OutlinePane(
                    outlineItems: model.outlineItems,
                    searchResults: model.searchResults,
                    onSelectOutlineItem: model.jumpToOutlineItem
                )
                    .frame(width: 260)
            }
        }
        .onChange(of: model.selectedFileURL?.path) { _, _ in
            splitScrollBridge.reset()
        }
    }
}

private struct SidebarView: View {
    @ObservedObject var model: ReaderViewModel

    var body: some View {
        List(selection: selectedPathBinding) {
            if !model.recentLocations.isEmpty {
                Section("Recent") {
                    ForEach(model.recentLocations, id: \.path) { url in
                        Button {
                            model.openLocation(url)
                        } label: {
                            Label(url.lastPathComponent, systemImage: url.hasDirectoryPath ? "folder" : "clock.arrow.circlepath")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let root = model.rootLocationURL {
                Section(root.lastPathComponent) {
                    OutlineGroup(model.fileTree, children: \.childNodes) { node in
                        HStack {
                            Image(systemName: node.isDirectory ? "folder" : "doc.text")
                                .foregroundStyle(node.isDirectory ? Color.secondary : Color.accentColor)
                            Text(node.displayName)
                        }
                        .tag(node.url.path)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !node.isDirectory {
                                model.loadDocument(at: node.url)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var selectedPathBinding: Binding<String?> {
        Binding(
            get: { model.selectedFileURL?.path },
            set: { newValue in
                guard let newValue else { return }
                model.loadDocument(at: URL(fileURLWithPath: newValue))
            }
        )
    }
}

private struct PreviewPane: View {
    let html: String
    let baseURL: URL?
    let navigationRequest: PreviewNavigationRequest?
    let scrollBridge: SplitScrollBridge

    var body: some View {
        MarkdownWebView(
            html: html,
            baseURL: baseURL,
            navigationRequest: navigationRequest,
            scrollBridge: scrollBridge
        )
    }
}

private struct SourcePane: View {
    @EnvironmentObject private var settings: ReaderSettings
    @ObservedObject var model: ReaderViewModel
    let text: String
    let scrollBridge: SplitScrollBridge

    var body: some View {
        SourceTextView(
            text: text,
            fontSize: settings.sourceFontSize,
            isEditable: true,
            scrollBridge: scrollBridge,
            onTextChange: model.updateMarkdownSource
        )
            .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct OutlinePane: View {
    let outlineItems: [OutlineItem]
    let searchResults: [SearchResult]
    let onSelectOutlineItem: (OutlineItem) -> Void

    var body: some View {
        List {
            if !outlineItems.isEmpty {
                Section("Outline") {
                    ForEach(outlineItems) { item in
                        Button {
                            onSelectOutlineItem(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .multilineTextAlignment(.leading)
                                Text("Line \(item.lineNumber)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, CGFloat(max(0, item.level - 1)) * 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !searchResults.isEmpty {
                Section("Search Results") {
                    ForEach(searchResults) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Line \(result.lineNumber)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(result.snippet.isEmpty ? "Blank line" : result.snippet)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct MetadataBar: View {
    let stats: DocumentStats
    let selectedFileURL: URL?
    let isDocumentEdited: Bool

    var body: some View {
        HStack(spacing: 18) {
            Label("\(stats.wordCount) words", systemImage: "text.word.spacing")
            Label("\(stats.characterCount) chars", systemImage: "character.cursor.ibeam")
            Label("\(stats.estimatedReadMinutes) min read", systemImage: "clock")
            if isDocumentEdited {
                Label("Edited", systemImage: "pencil.circle.fill")
                    .foregroundStyle(.orange)
            }
            Spacer()
            if let selectedFileURL {
                Text(selectedFileURL.path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct EmptyStateView: View {
    @ObservedObject var model: ReaderViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Open a Markdown file or folder to begin reading.")
                .font(.title3.weight(.semibold))
            Text("The app supports folder browsing, rendered preview, raw source view, outline navigation, search results, and persistent reading preferences.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            HStack {
                Button("Open File…") { model.openFilePanel() }
                Button("Open Folder…") { model.openFolderPanel() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search in document", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
        )
    }
}
