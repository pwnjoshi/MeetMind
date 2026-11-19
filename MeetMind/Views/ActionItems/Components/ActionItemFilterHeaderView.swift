import SwiftUI

/// Header controls for filtering and grouping action items across meetings
public struct ActionItemFilterHeaderView: View {
    public let selectedScope: ActionItemFilterScope
    public let selectedGrouping: ActionItemGrouping
    public let onSelectScope: (ActionItemFilterScope) -> Void
    public let onSelectGrouping: (ActionItemGrouping) -> Void
    
    public init(
        selectedScope: ActionItemFilterScope,
        selectedGrouping: ActionItemGrouping,
        onSelectScope: @escaping (ActionItemFilterScope) -> Void,
        onSelectGrouping: @escaping (ActionItemGrouping) -> Void
    ) {
        self.selectedScope = selectedScope
        self.selectedGrouping = selectedGrouping
        self.onSelectScope = onSelectScope
        self.onSelectGrouping = onSelectGrouping
    }
    
    public var body: some View {
        Picker("Action status", selection: Binding(get: { selectedScope }, set: onSelectScope)) {
            Text("All").tag(ActionItemFilterScope.all)
            Text("Open").tag(ActionItemFilterScope.pending)
            Text("Done").tag(ActionItemFilterScope.completed)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .tint(Color(hex: "#4B3FF0"))
        .accessibilityHint("Choose which actions appear below")
    }
}
