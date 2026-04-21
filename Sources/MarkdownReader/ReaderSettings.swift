import Foundation
import SwiftUI
import Combine

final class ReaderSettings: ObservableObject {
    @Published var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Keys.fontSize) }
    }

    @Published var sourceFontSize: Double {
        didSet { defaults.set(sourceFontSize, forKey: Keys.sourceFontSize) }
    }

    @Published var lineWidth: Double {
        didSet { defaults.set(lineWidth, forKey: Keys.lineWidth) }
    }

    @Published var theme: ReaderTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    @Published var showOutline: Bool {
        didSet { defaults.set(showOutline, forKey: Keys.showOutline) }
    }

    @Published var showMetadataBar: Bool {
        didSet { defaults.set(showMetadataBar, forKey: Keys.showMetadataBar) }
    }

    @Published var reopenLastLocation: Bool {
        didSet { defaults.set(reopenLastLocation, forKey: Keys.reopenLastLocation) }
    }

    var preferredColorScheme: ColorScheme? {
        theme.preferredColorScheme
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 17
        self.sourceFontSize = defaults.object(forKey: Keys.sourceFontSize) as? Double ?? 14
        self.lineWidth = defaults.object(forKey: Keys.lineWidth) as? Double ?? 860
        self.theme = ReaderTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
        self.showOutline = defaults.object(forKey: Keys.showOutline) as? Bool ?? true
        self.showMetadataBar = defaults.object(forKey: Keys.showMetadataBar) as? Bool ?? true
        self.reopenLastLocation = defaults.object(forKey: Keys.reopenLastLocation) as? Bool ?? true
    }

    private enum Keys {
        static let fontSize = "reader.fontSize"
        static let sourceFontSize = "reader.sourceFontSize"
        static let lineWidth = "reader.lineWidth"
        static let theme = "reader.theme"
        static let showOutline = "reader.showOutline"
        static let showMetadataBar = "reader.showMetadataBar"
        static let reopenLastLocation = "reader.reopenLastLocation"
    }
}
