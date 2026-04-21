import Foundation
import SwiftUI

enum ReaderLayout: String, CaseIterable, Identifiable {
    case preview
    case split
    case source

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preview:
            "Preview"
        case .split:
            "Split"
        case .source:
            "Source"
        }
    }

    var systemImage: String {
        switch self {
        case .preview:
            "doc.text.image"
        case .split:
            "square.split.2x1"
        case .source:
            "text.alignleft"
        }
    }
}

enum ReaderTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "Follow System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

struct MarkdownFileNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var children: [MarkdownFileNode] = []

    var id: String { url.path(percentEncoded: false) }
    var displayName: String { url.lastPathComponent }
    var childNodes: [MarkdownFileNode]? { isDirectory ? children : nil }
}

struct OutlineItem: Identifiable, Hashable {
    let id: String
    let level: Int
    let title: String
    let lineNumber: Int
    let anchorID: String
}

struct SearchResult: Identifiable, Hashable {
    let id = UUID()
    let lineNumber: Int
    let snippet: String
}

struct PreviewNavigationRequest: Identifiable, Equatable {
    let id = UUID()
    let targetID: String
}

struct DocumentStats {
    let wordCount: Int
    let characterCount: Int
    let estimatedReadMinutes: Int

    static let empty = DocumentStats(wordCount: 0, characterCount: 0, estimatedReadMinutes: 0)
}
