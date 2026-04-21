import SwiftUI

struct ReaderCommands: Commands {
    let model: ReaderViewModel
    let settings: ReaderSettings

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open File…") {
                model.openFilePanel()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open Folder…") {
                model.openFolderPanel()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Save") {
                model.saveDocument()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!model.canSaveDocument)
        }

        CommandMenu("Reader") {
            Button("Reload") {
                model.reload()
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button("Increase Font Size") {
                model.increaseReadingFont()
            }
            .keyboardShortcut("=", modifiers: .command)

            Button("Decrease Font Size") {
                model.decreaseReadingFont()
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Actual Size") {
                model.resetReadingFont()
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            Picker("Layout", selection: Binding(get: { model.layout }, set: { model.layout = $0 })) {
                ForEach(ReaderLayout.allCases) { layout in
                    Text(layout.title).tag(layout)
                }
            }

            Toggle("Show Outline", isOn: Binding(get: { settings.showOutline }, set: { settings.showOutline = $0 }))
            Toggle("Show Metadata Bar", isOn: Binding(get: { settings.showMetadataBar }, set: { settings.showMetadataBar = $0 }))
        }
    }
}
