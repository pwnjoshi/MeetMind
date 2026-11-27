import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// H3 Letterhead and Logo. Organization details plus the letterhead files kept in the
/// Minutes Studio library. Everything stays on this iPhone.
@MainActor
struct LetterheadAndLogoView: View {
    @AppStorage(OrganizationProfileStore.nameKey) private var organizationName = "iOS Center"
    @State private var details = OrganizationProfileStore().load()
    @State private var studio = MinutesStudioStore.shared
    @State private var photoItem: PhotosPickerItem?
    @State private var showsFileImporter = false
    @State private var errorMessage: String?
    @State private var previewImage: UIImage?
    private let detailsStore = OrganizationProfileStore()

    private var latestLetterhead: MinutesCustomLetterhead? {
        studio.letterheads.last
    }

    var body: some View {
        List {
            Section("Preview") {
                previewCard
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }
            Section("Logo") {
                logoRow
                ForEach(studio.letterheads) { letterhead in
                    HStack {
                        Text(letterhead.name).font(.subheadline)
                        Spacer()
                        Text(letterhead.isPDF ? "PDF" : "Image").font(.footnote).foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Remove", role: .destructive) {
                            studio.deleteLetterhead(id: letterhead.id)
                            refreshPreview()
                        }
                    }
                }
            }
            Section("Details") {
                TextField("Company Name", text: $organizationName)
                TextField("Registered Address", text: $details.address, axis: .vertical)
                TextField("CIN", text: $details.cin).textInputAutocapitalization(.characters)
                TextField("GSTIN", text: $details.gstin).textInputAutocapitalization(.characters)
                TextField("Phone", text: $details.phone).keyboardType(.phonePad)
                TextField("Email", text: $details.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }
        }
        .navigationTitle("Letterhead")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: details) { _, value in detailsStore.save(value) }
        .onChange(of: photoItem) { _, item in importPhoto(item) }
        .onAppear { refreshPreview() }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.png, .jpeg, .pdf],
            allowsMultipleSelection: false
        ) { result in importFile(result) }
        .alert("Could not add logo", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                logoThumbnail(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(organizationName.isEmpty ? "Your organization" : organizationName)
                        .font(.headline)
                    if !details.address.isEmpty {
                        Text(details.address).font(.caption).foregroundStyle(.secondary)
                    }
                    if !details.cin.isEmpty {
                        Text("CIN \(details.cin)").font(.caption2).foregroundStyle(.secondary)
                    }
                    if !details.gstin.isEmpty {
                        Text("GSTIN \(details.gstin)").font(.caption2).foregroundStyle(.secondary)
                    }
                    if !details.contactLine.isEmpty {
                        Text(details.contactLine).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Rectangle().fill(Theme.Colors.manentAccent).frame(height: 1.5)
            Text("MINUTES OF THE MEETING")
                .font(.caption2.weight(.bold))
                .frame(maxWidth: .infinity)
            ForEach(0..<3, id: \.self) { index in
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color(uiColor: .systemGray5))
                        .frame(width: proxy.size.width * (index == 2 ? 0.6 : 1.0), height: 5)
                }
                .frame(height: 5)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func logoThumbnail(size: CGFloat) -> some View {
        if let previewImage {
            Image(uiImage: previewImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Image(systemName: "building.2")
                .font(.system(size: size * 0.45))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Theme.Colors.manentAccent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var logoRow: some View {
        HStack(spacing: 12) {
            logoThumbnail(size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("Company logo").font(.subheadline.weight(.medium))
                Text("PNG, JPEG or PDF").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose Photo", systemImage: "photo")
                }
                Button("Choose File\u{2026}", systemImage: "folder") { showsFileImporter = true }
            } label: {
                Text(latestLetterhead == nil ? "Add" : "Change")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.manentAccent)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Theme.Colors.manentAccent.opacity(0.12), in: Capsule())
            }
        }
    }

    private func refreshPreview() {
        guard let latest = latestLetterhead else {
            previewImage = nil
            return
        }
        previewImage = MinutesLetterheadLoader.image(for: latest, store: studio)
    }

    private func importPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    errorMessage = MinutesStudioError.unreadableFile.localizedDescription
                    return
                }
                try studio.addLetterhead(imageData: data, fileExtension: "png", name: "Company logo")
                refreshPreview()
            } catch {
                errorMessage = error.localizedDescription
            }
            photoItem = nil
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try studio.addLetterhead(from: url, name: "Company logo")
                refreshPreview()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
