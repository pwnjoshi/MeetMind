import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Meeting type (169:642)

@MainActor
struct MinutesMeetingTypeView: View {
    let model: MinutesStudioModel
    @State private var showTemplates = false

    var body: some View {
        List {
            Section {
                ForEach(MinutesMeetingType.allCases) { type in
                    MinutesChoiceRow(
                        title: type.title,
                        subtitle: type.subtitle,
                        isSelected: model.config.meetingType == type
                    ) {
                        model.selectMeetingType(type)
                        showTemplates = true
                    }
                }
            } header: {
                Text("Choose the group that met.")
                    .textCase(nil)
                    .font(.subheadline)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Meeting Type")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: $showTemplates) {
            MinutesTemplatesView(model: model)
        }
    }
}

// MARK: - Templates (169:660, 605:1699, 2042:333)

@MainActor
struct MinutesTemplatesView: View {
    let model: MinutesStudioModel
    @State private var alerts = MinutesAlertCenter()
    @State private var showImporter = false
    @State private var showNameAlert = false
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                ForEach(MinutesBuiltInTemplate.allCases) { template in
                    MinutesChoiceRow(
                        title: template.title,
                        subtitle: template.subtitle,
                        isSelected: model.config.templateID == template.rawValue
                    ) {
                        model.selectTemplate(template)
                    }
                }
                ForEach(model.store.templates) { template in
                    MinutesChoiceRow(
                        title: template.name,
                        subtitle: template.subtitle,
                        isSelected: model.config.templateID == template.id.uuidString
                    ) {
                        model.selectCustomTemplate(template)
                    }
                }
                .onDelete { offsets in
                    let items = model.store.templates
                    for index in offsets where items.indices.contains(index) {
                        model.deleteCustomTemplate(items[index])
                    }
                }
            }
            Section {
                Button("Import from PDF…") {
                    showImporter = true
                }
                .foregroundStyle(Theme.Colors.manentAccent)
                Button("Save Current Setup") {
                    newName = ""
                    showNameAlert = true
                }
                .foregroundStyle(Theme.Colors.manentAccent)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: MinutesStudioRoute.format) {
                    Text("Format")
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url):
                do {
                    let template = try model.store.importTemplatePDF(from: url)
                    model.selectCustomTemplate(template)
                    alerts.showNotice("Template Added")
                } catch {
                    alerts.showError(error)
                }
            case .failure(let error):
                alerts.showError(error)
            }
        }
        .alert("Save Current Setup", isPresented: $showNameAlert) {
            TextField("Template name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                do {
                    let template = try model.store.saveCurrentSetup(named: newName, from: model.config)
                    model.update { $0.templateID = template.id.uuidString }
                    alerts.showNotice("Template Saved")
                } catch {
                    alerts.showError(error)
                }
            }
        } message: {
            Text("Name this template. It keeps the current format, contents and letterhead.")
        }
        .minutesAlerts(alerts)
    }
}

// MARK: - Format (169:678)

@MainActor
struct MinutesFormatView: View {
    let model: MinutesStudioModel

    var body: some View {
        List {
            Section {
                ForEach(MinutesFormat.allCases) { format in
                    MinutesChoiceRow(
                        title: format.title,
                        subtitle: format.subtitle,
                        isSelected: model.config.format == format
                    ) {
                        model.selectFormat(format)
                    }
                }
            } header: {
                Text("Standard Formats")
            } footer: {
                Text("Formal formats depend on the meeting type. Verify applicability with your Company Secretary.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Format")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Letterhead (169:696, 2042:368)

@MainActor
struct MinutesLetterheadView: View {
    let model: MinutesStudioModel
    @State private var alerts = MinutesAlertCenter()
    @State private var showSourceChoice = false
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?

    private var selectedBuiltIn: MinutesBuiltInLetterhead? {
        MinutesBuiltInLetterhead(rawValue: model.config.letterheadID)
    }

    var body: some View {
        List {
            Section {
                ForEach(MinutesBuiltInLetterhead.allCases) { letterhead in
                    MinutesChoiceRow(
                        title: letterhead.title,
                        subtitle: letterhead.subtitle,
                        isSelected: model.config.letterheadID == letterhead.rawValue
                    ) {
                        model.selectLetterhead(id: letterhead.rawValue)
                    }
                }
                ForEach(model.store.letterheads) { letterhead in
                    MinutesChoiceRow(
                        title: letterhead.name,
                        subtitle: letterhead.isPDF ? "Uploaded PDF" : "Uploaded image",
                        isSelected: model.config.letterheadID == letterhead.id.uuidString
                    ) {
                        model.selectLetterhead(id: letterhead.id.uuidString)
                    }
                }
                .onDelete { offsets in
                    let items = model.store.letterheads
                    for index in offsets where items.indices.contains(index) {
                        model.deleteCustomLetterhead(items[index])
                    }
                }
            }

            if let builtIn = selectedBuiltIn, builtIn != .plain {
                Section {
                    TextField(
                        builtIn == .company ? "Company name" : "Name",
                        text: Binding(
                            get: { model.config.organisationName },
                            set: { value in model.update { $0.organisationName = value } }
                        )
                    )
                    if builtIn == .company {
                        TextField(
                            "Registered office",
                            text: Binding(
                                get: { model.config.organisationAddress },
                                set: { value in model.update { $0.organisationAddress = value } }
                            )
                        )
                    }
                } header: {
                    Text("Header Text")
                } footer: {
                    Text("Printed at the top of the document. Stored only on this iPhone.")
                }
            }

            Section {
                Button("Upload Letterhead…") {
                    showSourceChoice = true
                }
                .foregroundStyle(Theme.Colors.manentAccent)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Letterhead")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Upload Letterhead", isPresented: $showSourceChoice, titleVisibility: .visible) {
            Button("Choose from Files") { showFileImporter = true }
            Button("Choose from Photos") { showPhotoPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image, .pdf]) { result in
            switch result {
            case .success(let url):
                do {
                    let letterhead = try model.store.addLetterhead(from: url)
                    model.selectLetterhead(id: letterhead.id.uuidString)
                    alerts.showNotice("Letterhead Added")
                } catch {
                    alerts.showError(error)
                }
            case .failure(let error):
                alerts.showError(error)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
        .minutesAlerts(alerts)
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw MinutesStudioError.unreadableFile
            }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let name = "Letterhead \(model.store.letterheads.count + 1)"
            let letterhead = try model.store.addLetterhead(imageData: data, fileExtension: ext, name: name)
            model.selectLetterhead(id: letterhead.id.uuidString)
            alerts.showNotice("Letterhead Added")
        } catch {
            alerts.showError(error)
        }
    }
}
