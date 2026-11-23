import SwiftUI

/// H11 Minutes language.
struct MinutesLanguageView: View {
    @AppStorage(MinutesLanguagePreference.key) private var raw = MinutesLanguage.english.rawValue
    @AppStorage(HindiScriptPreference.key) private var hindiScript = HindiScriptStyle.devanagari.rawValue

    var body: some View {
        List {
            Section {
                ForEach(MinutesLanguage.allCases) { language in
                    Button {
                        raw = language.rawValue
                    } label: {
                        HStack {
                            Text(language.title).foregroundStyle(.primary)
                            Spacer()
                            if raw == language.rawValue {
                                Image(systemName: "checkmark").foregroundStyle(Theme.Colors.manentAccent)
                            }
                        }
                    }
                    .accessibilityAddTraits(raw == language.rawValue ? .isSelected : [])
                }
            } footer: {
                Text("Applies to minutes written on this iPhone. Review Hindi output before sharing.")
            }
            Section {
                ForEach(HindiScriptStyle.allCases) { style in
                    Button {
                        hindiScript = style.rawValue
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.title).foregroundStyle(.primary)
                                Text(style.example).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if hindiScript == style.rawValue {
                                Image(systemName: "checkmark").foregroundStyle(Theme.Colors.manentAccent)
                            }
                        }
                    }
                    .accessibilityAddTraits(hindiScript == style.rawValue ? .isSelected : [])
                }
            } header: {
                Text("Hindi script on screen")
            } footer: {
                Text("Changes how Hindi words look in the transcript and live captions. Saved transcripts and minutes are not changed.")
            }
        }
        .navigationTitle("Minutes Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}
