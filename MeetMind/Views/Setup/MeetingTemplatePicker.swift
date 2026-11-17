import SwiftUI

/// Horizontal scrolling template picker component
public struct MeetingTemplatePicker: View {
    public let templates: [MeetingTemplate]
    public let selectedTemplate: MeetingTemplateType?
    public let onSelect: (MeetingTemplate) -> Void
    
    public init(
        templates: [MeetingTemplate],
        selectedTemplate: MeetingTemplateType?,
        onSelect: @escaping (MeetingTemplate) -> Void
    ) {
        self.templates = templates
        self.selectedTemplate = selectedTemplate
        self.onSelect = onSelect
    }
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(templates) { template in
                    let isSelected = selectedTemplate?.name == template.name
                    Button {
                        onSelect(template)
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: template.iconName)
                                .font(.system(size: 13, weight: .semibold))
                            Text(template.name)
                                .font(Typography.footnote)
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                        .background(isSelected ? Theme.Colors.primarySlate : Theme.Colors.secondaryBackground)
                        .foregroundStyle(isSelected ? .white : Theme.Colors.textPrimary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? Theme.Colors.primarySlate : Theme.Colors.cardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityLabel("Template: \(template.name)")
                }
            }
            .padding(.vertical, Spacing.xxs)
        }
    }
}

public typealias MeetingTemplateSelectorView = MeetingTemplatePicker
