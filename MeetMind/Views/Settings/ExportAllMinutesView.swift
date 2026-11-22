import SwiftUI
import SwiftData
import PDFKit
import UIKit

enum ExportAllFormat: String, CaseIterable, Identifiable {
    case combinedPDF
    case combinedText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .combinedPDF: return "PDF"
        case .combinedText: return "Plain Text"
        }
    }

    var detail: String {
        switch self {
        case .combinedPDF: return "One file with every finalized meeting"
        case .combinedText: return "One readable .txt file"
        }
    }

    var systemImage: String {
        switch self {
        case .combinedPDF: return "doc.richtext"
        case .combinedText: return "text.alignleft"
        }
    }

    var color: Color {
        switch self {
        case .combinedPDF: return .red
        case .combinedText: return .blue
        }
    }
}

enum ExportAllRange: String, CaseIterable, Identifiable {
    case allTime
    case lastYear
    case lastMonth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allTime: return "All Time"
        case .lastYear: return "Last 12 Months"
        case .lastMonth: return "Last 30 Days"
        }
    }

    func cutoff(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .allTime: return nil
        case .lastYear: return calendar.date(byAdding: .month, value: -12, to: now)
        case .lastMonth: return calendar.date(byAdding: .day, value: -30, to: now)
        }
    }
}

/// Selects meetings whose minutes are final (minutes exist and no edit invalidated them).
enum ExportAllSelection {
    static func isFinalized(_ meeting: Meeting) -> Bool {
        meeting.summary != nil && meeting.minutesNeedFinalization != true
    }

    static func meetings(from all: [Meeting], range: ExportAllRange, now: Date = Date()) -> [Meeting] {
        let cutoff = range.cutoff(now: now)
        return all
            .filter { isFinalized($0) }
            .filter { meeting in
                guard let cutoff else { return true }
                return meeting.createdAt >= cutoff
            }
            .sorted { $0.createdAt < $1.createdAt }
    }
}

/// H13 Export all minutes. The user starts the export and chooses where it goes in the share sheet.
@MainActor
struct ExportAllMinutesView: View {
    @Query(sort: \Meeting.createdAt) private var meetings: [Meeting]
    @State private var format: ExportAllFormat = .combinedPDF
    @State private var range: ExportAllRange = .allTime
    @State private var includesTranscripts = false
    @State private var isWorking = false
    @State private var shareURL: URL?
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var selected: [Meeting] {
        ExportAllSelection.meetings(from: meetings, range: range)
    }

    var body: some View {
        let chosen = selected
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(countTitle(chosen.count)).font(.title2.bold())
                    Text(rangeLine(chosen)).font(.subheadline).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section("Format") {
                ForEach(ExportAllFormat.allCases) { option in
                    Button { format = option } label: {
                        HStack(spacing: 12) {
                            SettingsIconTile(systemImage: option.systemImage, color: option.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title).font(.subheadline).foregroundStyle(.primary)
                                Text(option.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if format == option {
                                Image(systemName: "checkmark").foregroundStyle(Theme.Colors.manentAccent)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(format == option ? .isSelected : [])
                }
            }
            Section {
                Toggle("Transcripts", isOn: $includesTranscripts)
                Picker("Date Range", selection: $range) {
                    ForEach(ExportAllRange.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Include")
            } footer: {
                Text("Only finalized minutes are exported. Audio never leaves Manent in this export.")
            }
            if let statusMessage {
                Section { Text(statusMessage).font(.subheadline).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(action: startExport) {
                Text(isWorking ? "Preparing\u{2026}" : buttonTitle(chosen.count))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.manentAccent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(chosen.isEmpty || isWorking)
            .padding()
        }
        .sheet(item: Binding(
            get: { shareURL.map { ExportShareItem(url: $0) } },
            set: { if $0 == nil { shareURL = nil } }
        )) { item in
            ExportActivitySheet(url: item.url) { completed in
                statusMessage = completed ? "Shared." : "Export was not shared."
                try? FileManager.default.removeItem(at: item.url)
                shareURL = nil
            }
        }
        .alert("Could not export", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func countTitle(_ count: Int) -> String {
        count == 1 ? "1 meeting" : "\(count) meetings"
    }

    private func buttonTitle(_ count: Int) -> String {
        count == 1 ? "Export 1 Meeting" : "Export \(count) Meetings"
    }

    private func rangeLine(_ chosen: [Meeting]) -> String {
        guard let first = chosen.first, let last = chosen.last else {
            return "No finalized minutes yet. Finalize minutes to export them."
        }
        let style = Date.FormatStyle().month(.abbreviated).year()
        return "\(first.createdAt.formatted(style)) \u{2013} \(last.createdAt.formatted(style))"
    }

    private func startExport() {
        guard !isWorking else { return }
        isWorking = true
        statusMessage = nil
        let chosen = selected
        let currentFormat = format
        let withTranscripts = includesTranscripts
        Task { @MainActor in
            defer { isWorking = false }
            do {
                shareURL = try build(chosen, format: currentFormat, transcripts: withTranscripts)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func build(_ chosen: [Meeting], format: ExportAllFormat, transcripts: Bool) throws -> URL {
        let service = ExportService()
        var snapshots: [DocumentSnapshot] = []
        for meeting in chosen {
            let snapshot = DocumentSnapshot.make(from: meeting)
            snapshots.append(transcripts ? snapshot : snapshot.withoutTranscript())
        }
        guard !snapshots.isEmpty else { throw ExportError.emptyMeetingData }
        let stamp = Date().formatted(.iso8601.year().month().day())
        switch format {
        case .combinedPDF:
            let combined = PDFDocument()
            for snapshot in snapshots {
                let data = try service.generatePDFReport(snapshot: snapshot)
                guard let part = PDFDocument(data: data) else { continue }
                for index in 0..<part.pageCount {
                    if let page = part.page(at: index) { combined.insert(page, at: combined.pageCount) }
                }
            }
            guard let data = combined.dataRepresentation(), combined.pageCount > 0 else {
                throw ExportError.pdfGenerationFailed("No pages were produced.")
            }
            return try write(data, name: "Manent Minutes \(stamp).pdf")
        case .combinedText:
            let text = snapshots
                .map { service.generatePlainText(snapshot: $0) }
                .joined(separator: "\n\n----------------------------------------\n\n")
            guard let data = text.data(using: .utf8) else { throw ExportError.emptyMeetingData }
            return try write(data, name: "Manent Minutes \(stamp).txt")
        }
    }

    private func write(_ data: Data, name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ManentExport-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            throw ExportError.fileWriteFailed(error.localizedDescription)
        }
    }
}

struct ExportShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Share sheet wrapper that reports whether the user actually completed a share.
struct ExportActivitySheet: UIViewControllerRepresentable {
    let url: URL
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            DispatchQueue.main.async { onFinish(completed) }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
