import Foundation
import Observation

enum MinutesStudioError: LocalizedError, Equatable {
    case emptyName
    case notAPDF
    case unreadableFile
    case storageFailed

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a name first."
        case .notAPDF: return "The selected file is not a PDF."
        case .unreadableFile: return "The selected file could not be read."
        case .storageFailed: return "The file could not be saved on this iPhone."
        }
    }
}

/// Local JSON persistence for Minutes Studio. Nothing leaves the device.
@MainActor
@Observable
final class MinutesStudioStore {
    static let shared = MinutesStudioStore()

    private(set) var library: MinutesStudioLibrary
    private var configFile: MinutesStudioConfigFile

    private let directory: URL
    private let fileManager = FileManager.default

    var templates: [MinutesCustomTemplate] { library.templates }
    var letterheads: [MinutesCustomLetterhead] { library.letterheads }

    /// - Parameter directory: Folder used for all files. Defaults to Application Support/MinutesStudio.
    init(directory: URL? = nil) {
        let base: URL
        if let directory {
            base = directory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            base = support.appendingPathComponent("MinutesStudio", isDirectory: true)
        }
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.library = Self.read(MinutesStudioLibrary.self, from: base.appendingPathComponent("library.json"))
            ?? .empty
        self.configFile = Self.read(MinutesStudioConfigFile.self, from: base.appendingPathComponent("configs.json"))
            ?? MinutesStudioConfigFile(configs: [:])
    }

    // MARK: Paths

    private var templatesFolder: URL { directory.appendingPathComponent("Templates", isDirectory: true) }
    private var letterheadsFolder: URL { directory.appendingPathComponent("Letterheads", isDirectory: true) }

    func templateFileURL(_ template: MinutesCustomTemplate) -> URL? {
        guard let name = template.pdfFileName else { return nil }
        return templatesFolder.appendingPathComponent(name)
    }

    func letterheadFileURL(_ letterhead: MinutesCustomLetterhead) -> URL {
        letterheadsFolder.appendingPathComponent(letterhead.fileName)
    }

    // MARK: Per-meeting configuration

    func config(for meetingID: UUID) -> MinutesStudioConfig? {
        configFile.configs[meetingID.uuidString]
    }

    func save(_ config: MinutesStudioConfig, for meetingID: UUID) {
        configFile.configs[meetingID.uuidString] = config
        persistConfigs()
    }

    func removeConfig(for meetingID: UUID) {
        configFile.configs.removeValue(forKey: meetingID.uuidString)
        persistConfigs()
    }

    // MARK: Lookup

    func template(withID id: String) -> MinutesCustomTemplate? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return library.templates.first { $0.id == uuid }
    }

    func letterhead(withID id: String) -> MinutesCustomLetterhead? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return library.letterheads.first { $0.id == uuid }
    }

    func templateName(for id: String) -> String {
        if let builtIn = MinutesBuiltInTemplate(rawValue: id) { return builtIn.title }
        return template(withID: id)?.name ?? MinutesBuiltInTemplate.projectReview.title
    }

    func letterheadName(for id: String) -> String {
        if let builtIn = MinutesBuiltInLetterhead(rawValue: id) { return builtIn.title }
        return letterhead(withID: id)?.name ?? MinutesBuiltInLetterhead.plain.title
    }

    // MARK: Templates

    @discardableResult
    func saveCurrentSetup(named name: String, from config: MinutesStudioConfig, now: Date = Date()) throws -> MinutesCustomTemplate {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MinutesStudioError.emptyName }
        let template = MinutesCustomTemplate(
            id: UUID(),
            name: trimmed,
            kind: .savedSetup,
            createdAt: now,
            meetingType: config.meetingType,
            format: config.format,
            enabledSections: config.enabledSections,
            sectionOrder: config.sectionOrder,
            letterheadID: config.letterheadID,
            pdfFileName: nil
        )
        library.templates.append(template)
        persistLibrary()
        return template
    }

    /// Stores the chosen PDF and records it as a named template that uses the standard structure.
    @discardableResult
    func importTemplatePDF(from url: URL, name: String? = nil, now: Date = Date()) throws -> MinutesCustomTemplate {
        guard url.pathExtension.lowercased() == "pdf" else { throw MinutesStudioError.notAPDF }
        let displayName = Self.cleanName(name, fallback: url.deletingPathExtension().lastPathComponent)
        guard !displayName.isEmpty else { throw MinutesStudioError.emptyName }
        let id = UUID()
        let fileName = "\(id.uuidString).pdf"
        try copyIn(url, folder: templatesFolder, fileName: fileName)
        let standard = MinutesBuiltInTemplate.projectReview
        let template = MinutesCustomTemplate(
            id: id,
            name: displayName,
            kind: .importedPDF,
            createdAt: now,
            meetingType: .teamProject,
            format: .corporateStandard,
            enabledSections: standard.defaultSections,
            sectionOrder: MinutesSection.allCases,
            letterheadID: nil,
            pdfFileName: fileName
        )
        library.templates.append(template)
        persistLibrary()
        return template
    }

    func deleteTemplate(id: UUID) {
        guard let index = library.templates.firstIndex(where: { $0.id == id }) else { return }
        let removed = library.templates.remove(at: index)
        if let url = templateFileURL(removed) { try? fileManager.removeItem(at: url) }
        persistLibrary()
    }

    // MARK: Letterheads

    @discardableResult
    func addLetterhead(from url: URL, name: String? = nil, now: Date = Date()) throws -> MinutesCustomLetterhead {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { throw MinutesStudioError.unreadableFile }
        let displayName = Self.cleanName(name, fallback: url.deletingPathExtension().lastPathComponent)
        guard !displayName.isEmpty else { throw MinutesStudioError.emptyName }
        let id = UUID()
        let fileName = "\(id.uuidString).\(ext)"
        try copyIn(url, folder: letterheadsFolder, fileName: fileName)
        let letterhead = MinutesCustomLetterhead(id: id, name: displayName, createdAt: now, fileName: fileName, isPDF: ext == "pdf")
        library.letterheads.append(letterhead)
        persistLibrary()
        return letterhead
    }

    @discardableResult
    func addLetterhead(imageData: Data, fileExtension: String, name: String, now: Date = Date()) throws -> MinutesCustomLetterhead {
        let displayName = Self.cleanName(name, fallback: "")
        guard !displayName.isEmpty else { throw MinutesStudioError.emptyName }
        guard !imageData.isEmpty else { throw MinutesStudioError.unreadableFile }
        let id = UUID()
        let fileName = "\(id.uuidString).\(fileExtension.lowercased())"
        do {
            try fileManager.createDirectory(at: letterheadsFolder, withIntermediateDirectories: true)
            try imageData.write(to: letterheadsFolder.appendingPathComponent(fileName), options: .atomic)
        } catch {
            throw MinutesStudioError.storageFailed
        }
        let letterhead = MinutesCustomLetterhead(id: id, name: displayName, createdAt: now, fileName: fileName, isPDF: false)
        library.letterheads.append(letterhead)
        persistLibrary()
        return letterhead
    }

    func deleteLetterhead(id: UUID) {
        guard let index = library.letterheads.firstIndex(where: { $0.id == id }) else { return }
        let removed = library.letterheads.remove(at: index)
        try? fileManager.removeItem(at: letterheadFileURL(removed))
        persistLibrary()
    }

    // MARK: Helpers

    static func cleanName(_ name: String?, fallback: String) -> String {
        let candidate = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.isEmpty { return candidate }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyIn(_ source: URL, folder: URL, fileName: String) throws {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw MinutesStudioError.unreadableFile
        }
    }

    private func persistLibrary() {
        Self.write(library, to: directory.appendingPathComponent("library.json"))
    }

    private func persistConfigs() {
        Self.write(configFile, to: directory.appendingPathComponent("configs.json"))
    }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
