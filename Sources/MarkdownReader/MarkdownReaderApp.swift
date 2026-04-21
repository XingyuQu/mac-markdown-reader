import SwiftUI

@main
struct MarkdownReaderApp: App {
    @StateObject private var settings: ReaderSettings
    @StateObject private var model: ReaderViewModel

    init() {
        let settings = ReaderSettings()
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: ReaderViewModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup("Markdown Reader") {
            ContentView(model: model)
                .environmentObject(settings)
                .preferredColorScheme(settings.preferredColorScheme)
                .frame(minWidth: 980, minHeight: 680)
                .onAppear {
                    model.restoreLastSessionIfPossible()
                }
        }
        .commands {
            ReaderCommands(model: model, settings: settings)
        }

        Settings {
            SettingsView(settings: model.settings)
                .frame(width: 520)
                .padding(20)
        }
    }
}
