import SwiftUI
import SwiftData

enum MinutesStudioRoute: Hashable {
    case meetingType
    case templates
    case format
    case letterhead
    case attendance
    case attendanceStatus(UUID)
    case contents
    case preview
}

/// Minutes Studio entry. Push this inside an existing NavigationStack.
@MainActor
struct MinutesStudioView: View {
    @State private var model: MinutesStudioModel

    init(meeting: Meeting) {
        _model = State(initialValue: MinutesStudioModel(meeting: meeting))
    }

    var body: some View {
        List {
            Section {
                NavigationLink(value: MinutesStudioRoute.meetingType) {
                    MinutesValueRow(title: "Template", value: model.templateName)
                }
                NavigationLink(value: MinutesStudioRoute.letterhead) {
                    MinutesValueRow(title: "Letterhead", value: model.letterheadName)
                }
            }
            Section {
                NavigationLink(value: MinutesStudioRoute.attendance) {
                    MinutesValueRow(title: "Attendance", value: model.attendanceSummary)
                }
                NavigationLink(value: MinutesStudioRoute.contents) {
                    MinutesValueRow(title: "Contents", value: model.contentsSummary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Minutes Studio")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: MinutesStudioRoute.self) { route in
            destination(for: route)
        }
        .safeAreaInset(edge: .bottom) {
            NavigationLink(value: MinutesStudioRoute.preview) {
                Text("Preview Document")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.Colors.manentAccent, in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func destination(for route: MinutesStudioRoute) -> some View {
        switch route {
        case .meetingType:
            MinutesMeetingTypeView(model: model)
        case .templates:
            MinutesTemplatesView(model: model)
        case .format:
            MinutesFormatView(model: model)
        case .letterhead:
            MinutesLetterheadView(model: model)
        case .attendance:
            MinutesAttendanceView(model: model)
        case .attendanceStatus(let id):
            MinutesAttendanceStatusView(model: model, participantID: id)
        case .contents:
            MinutesContentsView(model: model)
        case .preview:
            MinutesDocumentPreviewView(model: model)
        }
    }
}

// MARK: - Shared rows

struct MinutesValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct MinutesChoiceRow: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.Colors.manentAccent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
