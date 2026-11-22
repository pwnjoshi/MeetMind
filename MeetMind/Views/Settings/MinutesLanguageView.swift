import SwiftUI

/// H11 Minutes language.
struct MinutesLanguageView: View {
    @AppStorage(MinutesLanguagePreference.key) private var raw = MinutesLanguage.english.rawValue

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
        }
        .navigationTitle("Minutes Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}
