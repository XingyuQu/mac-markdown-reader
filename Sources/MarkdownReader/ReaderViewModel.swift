import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

final class ReaderViewModel: ObservableObject {
    static let previewFontRange: ClosedRange<Double> = 13 ... 26
    static let sourceFontRange: ClosedRange<Double> = 11 ... 22
    static let defaultPreviewFontSize: Double = 17
    static let defaultSourceFontSize: Double = 14

    @Published var fileTree: [MarkdownFileNode] = []
    @Published var selectedFileURL: URL?
    @Published var rootLocationURL: URL?
    @Published var markdownSource = ""
    @Published var renderedHTML = ""
    @Published var outlineItems: [OutlineItem] = []
    @Published var searchQuery = "" {
        didSet { refreshSearchResults() }
    }
    @Published var searchResults: [SearchResult] = []
    @Published var recentLocations: [URL] = []
    @Published var errorMessage: String?
    @Published var layout: ReaderLayout = .preview
    @Published var previewNavigationRequest: PreviewNavigationRequest?
    @Published var isBusy = false
    @Published var isDocumentEdited = false
    @Published var stats = DocumentStats.empty

    let settings: ReaderSettings

    private let fm = FileManager.default
    private let defaults = UserDefaults.standard
    private let supportedExtensions = Set(["md", "markdown", "mdown", "mkd"])
    private var cancellables = Set<AnyCancellable>()
    private var lastSavedMarkdownSource = ""
    private var pendingRenderRefresh: DispatchWorkItem?

    init(settings: ReaderSettings = ReaderSettings()) {
        self.settings = settings
        bindSettings()
    }

    @MainActor
    func restoreLastSessionIfPossible() {
        loadRecentLocations()
        guard settings.reopenLastLocation else { return }
        if let rootPath = defaults.string(forKey: Keys.rootLocation) {
            let url = URL(fileURLWithPath: rootPath)
            if fm.fileExists(atPath: url.path) {
                openLocation(url)
            }
        }
        if let selectedPath = defaults.string(forKey: Keys.selectedFile) {
            let url = URL(fileURLWithPath: selectedPath)
            if fm.fileExists(atPath: url.path) {
                loadDocument(at: url)
            }
        }
    }

    @MainActor
    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Markdown File"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openLocation(url)
    }

    @MainActor
    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openLocation(url)
    }

    @MainActor
    func openLocation(_ url: URL, allowDiscardCheck: Bool = true) {
        guard prepareForDocumentReplacement(targetName: url.lastPathComponent, allowDiscardCheck: allowDiscardCheck) else {
            return
        }

        errorMessage = nil
        rootLocationURL = url
        persistRecentLocation(url)
        defaults.set(url.path, forKey: Keys.rootLocation)
        rebuildFileTree()

        if url.hasDirectoryPath {
            if let firstFile = firstMarkdownFile(in: fileTree) {
                loadDocument(at: firstFile.url, allowDiscardCheck: false)
            } else {
                markdownSource = ""
                renderedHTML = MarkdownHTMLRenderer.emptyStateHTML("No Markdown files found in this folder.")
                outlineItems = []
                previewNavigationRequest = nil
                isDocumentEdited = false
                lastSavedMarkdownSource = ""
                stats = .empty
                searchResults = []
            }
        } else {
            loadDocument(at: url)
        }
    }

    @MainActor
    func reload() {
        if let rootLocationURL {
            openLocation(rootLocationURL)
        } else if let selectedFileURL {
            loadDocument(at: selectedFileURL)
        }
    }

    @MainActor
    func loadDocument(at url: URL, allowDiscardCheck: Bool = true) {
        guard prepareForDocumentReplacement(targetName: url.lastPathComponent, allowDiscardCheck: allowDiscardCheck) else {
            return
        }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            selectedFileURL = url
            defaults.set(url.path, forKey: Keys.selectedFile)
            markdownSource = text
            lastSavedMarkdownSource = text
            isDocumentEdited = false
            refreshDocumentDerivedState(for: text)
            previewNavigationRequest = nil
        } catch {
            errorMessage = "Failed to open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    @MainActor
    func revealInFinder() {
        guard let url = selectedFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func clearError() {
        errorMessage = nil
    }

    func increaseReadingFont() {
        adjustReadingFont(by: 1)
    }

    func decreaseReadingFont() {
        adjustReadingFont(by: -1)
    }

    func resetReadingFont() {
        settings.fontSize = Self.defaultPreviewFontSize
        settings.sourceFontSize = Self.defaultSourceFontSize
    }

    var canSaveDocument: Bool {
        selectedFileURL != nil && isDocumentEdited
    }

    func updateMarkdownSource(_ text: String) {
        guard text != markdownSource else { return }
        markdownSource = text
        isDocumentEdited = text != lastSavedMarkdownSource
        scheduleRefreshDocumentDerivedState()
    }

    func saveDocument() {
        guard let url = selectedFileURL else { return }

        do {
            try markdownSource.write(to: url, atomically: true, encoding: .utf8)
            lastSavedMarkdownSource = markdownSource
            isDocumentEdited = false
            refreshDocumentDerivedState(for: markdownSource)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to save \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func jumpToOutlineItem(_ item: OutlineItem) {
        if layout == .source {
            layout = .preview
        }
        previewNavigationRequest = PreviewNavigationRequest(targetID: item.anchorID)
    }

    private func rebuildFileTree() {
        guard let rootLocationURL else {
            fileTree = []
            return
        }

        if rootLocationURL.hasDirectoryPath {
            fileTree = buildTree(for: rootLocationURL)
        } else {
            fileTree = [MarkdownFileNode(url: rootLocationURL, isDirectory: false)]
        }
    }

    private func buildTree(for folder: URL) -> [MarkdownFileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        guard let enumerator = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else {
            return []
        }

        let children = enumerator.compactMap { child -> MarkdownFileNode? in
            guard
                let values = try? child.resourceValues(forKeys: Set(keys)),
                let isDirectory = values.isDirectory
            else {
                return nil
            }

            if isDirectory {
                let nested = buildTree(for: child)
                if nested.isEmpty {
                    return nil
                }
                return MarkdownFileNode(url: child, isDirectory: true, children: nested)
            }

            let ext = child.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { return nil }
            return MarkdownFileNode(url: child, isDirectory: false)
        }

        return children.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func firstMarkdownFile(in nodes: [MarkdownFileNode]) -> MarkdownFileNode? {
        for node in nodes {
            if node.isDirectory, let nested = firstMarkdownFile(in: node.children) {
                return nested
            }
            if !node.isDirectory {
                return node
            }
        }
        return nil
    }

    private func extractOutline(_ text: String) -> [OutlineItem] {
        let anchorPattern = #"<a\b[^>]*\bid\s*=\s*["']([^"']+)["'][^>]*>"#
        let anchorRegex = try? NSRegularExpression(pattern: anchorPattern, options: [.caseInsensitive])
        let headingPattern = #"^\s{0,3}(#{1,6})[ \t]+(.+?)\s*$"#
        let headingRegex = try? NSRegularExpression(pattern: headingPattern)
        var explicitAnchorForNextHeading: String?
        var generatedSlugCounts: [String: Int] = [:]
        var activeFence: MarkdownFence?
        var outlineItems: [OutlineItem] = []

        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineString = String(line)

            if let fence = activeFence {
                if matchesFenceCloser(lineString, fence: fence) {
                    activeFence = nil
                }
                continue
            }

            if let fence = parseFenceStart(from: lineString) {
                activeFence = fence
                explicitAnchorForNextHeading = nil
                continue
            }

            if let explicitAnchor = extractExplicitAnchor(from: lineString, regex: anchorRegex) {
                explicitAnchorForNextHeading = explicitAnchor
            }

            guard let headingMatch = matchHeading(in: lineString, regex: headingRegex) else { continue }

            let level = headingMatch.level
            let title = normalizeHeadingTitle(headingMatch.title)
            guard !title.isEmpty else { continue }

            let anchorID: String
            if let explicitAnchor = explicitAnchorForNextHeading {
                anchorID = explicitAnchor
                explicitAnchorForNextHeading = nil
            } else {
                anchorID = uniqueHeadingAnchor(for: title, counts: &generatedSlugCounts)
            }

            outlineItems.append(
                OutlineItem(
                    id: "\(anchorID)-\(index + 1)",
                    level: level,
                    title: title,
                    lineNumber: index + 1,
                    anchorID: anchorID
                )
            )
        }

        return outlineItems
    }

    private func refreshSearchResults() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        let lowercasedQuery = query.lowercased()
        let lines = markdownSource.split(separator: "\n", omittingEmptySubsequences: false)
        searchResults = lines.enumerated().compactMap { index, line in
            let stringLine = String(line)
            guard stringLine.lowercased().contains(lowercasedQuery) else { return nil }
            return SearchResult(lineNumber: index + 1, snippet: stringLine.trimmingCharacters(in: .whitespaces))
        }
    }

    private func calculateStats(_ text: String) -> DocumentStats {
        let words = text.split { $0.isWhitespace || $0.isNewline }
        let wordCount = words.count
        return DocumentStats(
            wordCount: wordCount,
            characterCount: text.count,
            estimatedReadMinutes: max(1, Int(ceil(Double(wordCount) / 220.0)))
        )
    }

    private func loadRecentLocations() {
        let paths = defaults.stringArray(forKey: Keys.recentLocations) ?? []
        recentLocations = paths.map { URL(fileURLWithPath: $0) }.filter { fm.fileExists(atPath: $0.path) }
    }

    private func persistRecentLocation(_ url: URL) {
        loadRecentLocations()
        recentLocations.removeAll { $0.path == url.path }
        recentLocations.insert(url, at: 0)
        recentLocations = Array(recentLocations.prefix(8))
        defaults.set(recentLocations.map(\.path), forKey: Keys.recentLocations)
    }

    private func bindSettings() {
        settings.$fontSize
            .combineLatest(settings.$lineWidth, settings.$theme)
            .sink { [weak self] _, _, _ in
                self?.refreshDocumentDerivedState(for: self?.markdownSource ?? "")
            }
            .store(in: &cancellables)
    }

    private func scheduleRefreshDocumentDerivedState() {
        pendingRenderRefresh?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.refreshDocumentDerivedState(for: self.markdownSource)
        }
        pendingRenderRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private func refreshDocumentDerivedState(for text: String) {
        pendingRenderRefresh?.cancel()
        pendingRenderRefresh = nil
        outlineItems = extractOutline(text)
        stats = calculateStats(text)
        refreshSearchResults()

        guard !text.isEmpty else {
            renderedHTML = MarkdownHTMLRenderer.emptyStateHTML("No document selected.")
            return
        }

        renderedHTML = MarkdownHTMLRenderer.fullDocumentHTML(
            markdownText: text,
            theme: settings.theme,
            fontSize: settings.fontSize,
            lineWidth: settings.lineWidth
        )
    }

    @MainActor
    private func prepareForDocumentReplacement(targetName: String, allowDiscardCheck: Bool) -> Bool {
        guard allowDiscardCheck, isDocumentEdited else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save changes before switching documents?"
        alert.informativeText = "Your edits in the current Markdown file are not saved. Switching to \(targetName) would discard them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveDocument()
            return !isDocumentEdited
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func adjustReadingFont(by delta: Double) {
        settings.fontSize = min(
            Self.previewFontRange.upperBound,
            max(Self.previewFontRange.lowerBound, settings.fontSize + delta)
        )
        settings.sourceFontSize = min(
            Self.sourceFontRange.upperBound,
            max(Self.sourceFontRange.lowerBound, settings.sourceFontSize + delta)
        )
    }

    private func extractExplicitAnchor(from line: String, regex: NSRegularExpression?) -> String? {
        guard let regex else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard
            let match = regex.firstMatch(in: line, options: [], range: range),
            let captureRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        return String(line[captureRange])
    }

    private func normalizeHeadingTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: #"\s+#*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchHeading(in line: String, regex: NSRegularExpression?) -> (level: Int, title: String)? {
        guard let regex else { return nil }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard
            let match = regex.firstMatch(in: line, options: [], range: range),
            let levelRange = Range(match.range(at: 1), in: line),
            let titleRange = Range(match.range(at: 2), in: line)
        else {
            return nil
        }

        let level = line[levelRange].count
        let title = String(line[titleRange])
        return (level, title)
    }

    private func parseFenceStart(from line: String) -> MarkdownFence? {
        let indent = leadingIndentCount(in: line)
        guard indent <= 3 else { return nil }

        let trimmedLine = String(line.dropFirst(indent))
        guard let marker = trimmedLine.first, marker == "`" || marker == "~" else { return nil }

        let length = trimmedLine.prefix { $0 == marker }.count
        guard length >= 3 else { return nil }

        return MarkdownFence(marker: marker, length: length)
    }

    private func matchesFenceCloser(_ line: String, fence: MarkdownFence) -> Bool {
        let indent = leadingIndentCount(in: line)
        guard indent <= 3 else { return false }

        let trimmedLine = String(line.dropFirst(indent))
        let repeatedCount = trimmedLine.prefix { $0 == fence.marker }.count
        guard repeatedCount >= fence.length else { return false }

        let trailing = trimmedLine.dropFirst(repeatedCount)
        return trailing.allSatisfy { $0 == " " || $0 == "\t" }
    }

    private func leadingIndentCount(in line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    private func uniqueHeadingAnchor(for title: String, counts: inout [String: Int]) -> String {
        let base = slugifyHeading(title)
        let count = counts[base, default: 0]
        counts[base] = count + 1
        return count == 0 ? base : "\(base)-\(count)"
    }

    private func slugifyHeading(_ title: String) -> String {
        let lowercased = title.lowercased().replacingOccurrences(of: "`", with: "")
        var scalars: [UnicodeScalar] = []
        scalars.reserveCapacity(lowercased.unicodeScalars.count)

        for scalar in lowercased.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                scalars.append(scalar)
                continue
            }

            if scalar == "-" || scalar == "_" {
                scalars.append(scalar)
                continue
            }

            if (0x4E00 ... 0x9FFF).contains(scalar.value) {
                scalars.append(scalar)
            }
        }

        let filtered = String(String.UnicodeScalarView(scalars))
        let collapsedWhitespace = filtered.replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
        let collapsedHyphen = collapsedWhitespace.replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
        let trimmed = collapsedHyphen.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "section" : trimmed
    }

    private enum Keys {
        static let rootLocation = "reader.rootLocation"
        static let selectedFile = "reader.selectedFile"
        static let recentLocations = "reader.recentLocations"
    }
}

private struct MarkdownFence {
    let marker: Character
    let length: Int
}
