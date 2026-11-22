import SwiftUI
import UniformTypeIdentifiers

/// H14 Minutes Studio entry. Shows the templates and letterheads available when minutes are
/// formatted, and lets the user manage the saved ones. Per-meeting choices are made inside a meeting.
@MainActor
struct MinutesStudioSettingsView: View {
    @State private var studio = MinutesStudioStore.shared
    @State private var selectedBuiltIn: MinutesBuiltInTemplate = .projectReview
    @State private var showsPDFImporter = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Templates").font(.footnote).foregroundStyle(.secondary).textCase(.uppercase)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(MinutesBuiltInTemplate.allCases) { template in
                        Button { selectedBuiltIn = template } label: {
                            templateCard(title: template.title, subtitle: template.subtitle,
                                         isSelected: selectedBuiltIn == template)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedBuiltIn == template ? .isSelected : [])
                    }
                }
                if !studio.templates.isEmpty {
                    Text("Saved by You").font(.footnote).foregroundStyle(.secondary).textCase(.uppercase)
                    VStack(spacing: 0) {
                        ForEach(studio.templates) { template in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name).font(.subheadline)
                                    Text(template.subtitle).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    studio.deleteTemplate(id: template.id)
                                }
                                .labelStyle(.iconOnly)
                                .frame(minWidth: 44, minHeight: 44)
                            }
                            .padding(.horizontal, 16)
                            if template.id != studio.templates.last?.id { Divider().padding(.leading, 16) }
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                Text("Sections in \(selectedBuiltIn.title)").font(.footnote).foregroundStyle(.secondary).textCase(.uppercase)
                VStack(spacing: 0) {
                    let sections = selectedBuiltIn.defaultSections
                    ForEach(sections) { section in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(section.title).font(.subheadline)
                            Spacer()
                        }
                        .frame(minHeight: 44)
                        .padding(.horizontal, 16)
                        if section != sections.last { Divider().padding(.leading, 48) }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                Text("Choose a template, letterhead and sections for each meeting from its Minutes Studio. Letterheads are managed under Letterhead and Logo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Minutes Studio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Import PDF Template", systemImage: "plus") { showsPDFImporter = true }
            }
        }
        .fileImporter(isPresented: $showsPDFImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            switch result {
            case .failure(let error):
                errorMessage = error.localizedDescription
            case .success(let urls):
                guard let url = urls.first else { return }
                do { try studio.importTemplatePDF(from: url) } catch { errorMessage = error.localizedDescription }
            }
        }
        .alert("Could not add template", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func templateCard(title: String, subtitle: String, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "list.bullet")
                .font(.headline)
                .foregroundStyle(Theme.Colors.manentAccent)
                .frame(width: 36, height: 36)
                .background(Theme.Colors.manentAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading).lineLimit(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? Theme.Colors.manentAccent : Color.clear, lineWidth: 1.5)
        )
    }
}
