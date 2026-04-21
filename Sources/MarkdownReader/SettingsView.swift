import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: ReaderSettings

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(ReaderTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }

                LabeledContent("Preview Font") {
                    HStack {
                        Slider(value: $settings.fontSize, in: 13 ... 26, step: 1)
                        Text("\(Int(settings.fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }

                LabeledContent("Source Font") {
                    HStack {
                        Slider(value: $settings.sourceFontSize, in: 11 ... 22, step: 1)
                        Text("\(Int(settings.sourceFontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }

                LabeledContent("Reading Width") {
                    HStack {
                        Slider(value: $settings.lineWidth, in: 600 ... 1100, step: 20)
                        Text("\(Int(settings.lineWidth)) px")
                            .monospacedDigit()
                            .frame(width: 70, alignment: .trailing)
                    }
                }
            }

            Section("Interface") {
                Toggle("Show outline sidebar", isOn: $settings.showOutline)
                Toggle("Show metadata bar", isOn: $settings.showMetadataBar)
                Toggle("Reopen last location on launch", isOn: $settings.reopenLastLocation)
            }
        }
        .formStyle(.grouped)
    }
}
