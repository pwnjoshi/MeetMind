import SwiftUI

/// Agenda as ordered points. Stored as plain text with one point per line (the minutes engine
/// already reads lines as topics), so these helpers convert between that text and a list.
enum AgendaPoints {
    /// One line without its list marker ("- ", "* ", a bullet, "1." or "1)").
    static func cleaned(_ line: String) -> String {
        var item = line.trimmingCharacters(in: .whitespaces)
        item = String(item.drop(while: { $0 == "-" || $0 == "*" || $0 == "\u{2022}" || $0 == " " }))
        item = item.replacingOccurrences(of: #"^\d+[.)]\s+"#, with: "", options: .regularExpression)
        return item.trimmingCharacters(in: .whitespaces)
    }

    /// The points of a stored agenda: one per non-empty line, markers removed.
    static func parse(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { cleaned(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// Stored text for a list of points: trimmed, empty points dropped, one per line.
    static func join(_ points: [String]) -> String {
        points
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Splits a paragraph at sentence ends (". ", "! ", "? "). A trailing full stop is dropped.
    static func splitSentences(_ text: String) -> [String] {
        let characters = Array(text)
        var sentences: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            current.append(character)
            guard character == "." || character == "!" || character == "?" else { continue }
            let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            if next == nil || next?.isWhitespace == true {
                sentences.append(current)
                current = ""
            }
        }
        sentences.append(current)
        return sentences
            .map { sentence -> String in
                var value = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if value.hasSuffix(".") { value.removeLast() }
                return cleaned(value)
            }
            .filter { !$0.isEmpty }
    }

    /// What an edit of a single point turns into.
    /// Returns nil for ordinary typing. A line break (return key or a pasted list) gives one entry per line;
    /// a final "" means return was pressed at the end and a new empty point should follow.
    /// A pasted multi-sentence paragraph (more than one character added at once) gives one entry per sentence.
    static func splitEdit(old: String, new: String) -> [String]? {
        if new.contains(where: \.isNewline) {
            let parts = new
                .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                .map { cleaned(String($0)) }
            let lastIndex = parts.count - 1
            var kept: [String] = []
            for (index, part) in parts.enumerated() where !part.isEmpty || index == lastIndex {
                kept.append(part)
            }
            return kept
        }
        guard new.count - old.count > 1 else { return nil }
        let sentences = splitSentences(new)
        return sentences.count > 1 ? sentences : nil
    }
}

struct AgendaPointItem: Identifiable, Equatable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

private struct AgendaRowHeightKey: PreferenceKey {
    static let defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

/// Editor for agenda points. Return adds the next point, a pasted paragraph splits into points,
/// swipe left deletes and the handle on the right reorders by dragging.
struct PrepAgendaEditor: View {
    @Binding var text: String

    @State private var items: [AgendaPointItem] = []
    @State private var didLoad = false
    @State private var lastWritten = ""
    @State private var rowHeights: [UUID: CGFloat] = [:]
    @State private var draggingID: UUID?
    @State private var dragOffset: CGFloat = 0
    @FocusState private var focusedID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                AgendaPointRow(
                    id: item.id,
                    number: index + 1,
                    total: items.count,
                    text: binding(for: item.id),
                    focus: $focusedID,
                    isDragging: draggingID == item.id,
                    dragOffset: dragOffset,
                    onReturn: { submit(item.id) },
                    onDelete: { remove(item.id) },
                    onMove: { move(item.id, by: $0) },
                    onDragChanged: { dragChanged(item.id, $0) },
                    onDragEnded: { dragEnded(item.id, $0) }
                )
                .zIndex(draggingID == item.id ? 1 : 0)
            }
            addButton
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onPreferenceChange(AgendaRowHeightKey.self) { rowHeights = $0 }
        .onAppear { loadIfNeeded() }
        .onChange(of: text) { _, newValue in reloadIfChangedElsewhere(newValue) }
        .onChange(of: items) { _, _ in commit() }
        .onChange(of: focusedID) { _, newValue in pruneBlankPoints(keeping: newValue) }
    }

    private var addButton: some View {
        Button { addPoint(after: nil) } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.body)
                    .frame(minWidth: 20, alignment: .leading)
                Text("Add Point")
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.Colors.manentAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Adds an agenda point")
    }

    // MARK: Loading and saving

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        lastWritten = text
        items = AgendaPoints.parse(text).map { AgendaPointItem(text: $0) }
    }

    private func commit() {
        let joined = AgendaPoints.join(items.map(\.text))
        lastWritten = joined
        if joined != text { text = joined }
    }

    private func reloadIfChangedElsewhere(_ newValue: String) {
        guard newValue != lastWritten else { return }
        lastWritten = newValue
        items = AgendaPoints.parse(newValue).map { AgendaPointItem(text: $0) }
    }

    // MARK: Editing

    private func binding(for id: UUID) -> Binding<String> {
        Binding(
            get: { items.first(where: { $0.id == id })?.text ?? "" },
            set: { handleEdit(id, $0) }
        )
    }

    private func handleEdit(_ id: UUID, _ newValue: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard let parts = AgendaPoints.splitEdit(old: items[index].text, new: newValue) else {
            items[index].text = newValue
            return
        }
        if parts.count <= 1 {
            // Return pressed in a point that has nothing in it, or a single line pasted with a break.
            let single = parts.first ?? ""
            items[index].text = single
            if single.isEmpty { focusedID = nil }
            return
        }
        items[index].text = parts[0]
        let added = parts.dropFirst().map { AgendaPointItem(text: $0) }
        items.insert(contentsOf: added, at: index + 1)
        if let last = added.last { focus(last.id) }
    }

    private func submit(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if items[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            focusedID = nil
        } else {
            addPoint(after: id)
        }
    }

    private func addPoint(after id: UUID?) {
        if let id, let index = items.firstIndex(where: { $0.id == id }) {
            let nextIndex = index + 1
            if nextIndex < items.count, isBlank(items[nextIndex]) {
                focus(items[nextIndex].id)
                return
            }
            let point = AgendaPointItem(text: "")
            items.insert(point, at: nextIndex)
            focus(point.id)
        } else {
            if let last = items.last, isBlank(last) {
                focus(last.id)
                return
            }
            let point = AgendaPointItem(text: "")
            items.append(point)
            focus(point.id)
        }
    }

    private func remove(_ id: UUID) {
        withAnimation(.snappy) {
            items.removeAll { $0.id == id }
        }
    }

    private func move(_ id: UUID, by delta: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let target = index + delta
        guard items.indices.contains(target) else { return }
        withAnimation(.snappy) {
            items.swapAt(index, target)
        }
    }

    private func pruneBlankPoints(keeping focused: UUID?) {
        guard items.contains(where: { isBlank($0) && $0.id != focused }) else { return }
        withAnimation(.snappy) {
            items.removeAll { isBlank($0) && $0.id != focused }
        }
    }

    private func isBlank(_ item: AgendaPointItem) -> Bool {
        item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func focus(_ id: UUID) {
        DispatchQueue.main.async { focusedID = id }
    }

    // MARK: Reordering by dragging the handle

    private func dragChanged(_ id: UUID, _ translation: CGFloat) {
        if draggingID != id { draggingID = id }
        dragOffset = translation
    }

    private func dragEnded(_ id: UUID, _ translation: CGFloat) {
        defer {
            withAnimation(.snappy) {
                draggingID = nil
                dragOffset = 0
            }
        }
        guard let from = items.firstIndex(where: { $0.id == id }) else { return }
        let fallback: CGFloat = 56
        var starts: [CGFloat] = []
        var top: CGFloat = 0
        for item in items {
            starts.append(top)
            top += rowHeights[item.id] ?? fallback
        }
        let center = starts[from] + (rowHeights[id] ?? fallback) / 2 + translation
        var target = items.count - 1
        for (index, item) in items.enumerated() {
            if center < starts[index] + (rowHeights[item.id] ?? fallback) {
                target = index
                break
            }
        }
        guard target != from else { return }
        withAnimation(.snappy) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: target > from ? target + 1 : target)
        }
    }
}

/// One editable point: number, text field that wraps, reorder handle, swipe-to-delete.
private struct AgendaPointRow: View {
    let id: UUID
    let number: Int
    let total: Int
    @Binding var text: String
    var focus: FocusState<UUID?>.Binding
    let isDragging: Bool
    let dragOffset: CGFloat
    let onReturn: () -> Void
    let onDelete: () -> Void
    let onMove: (Int) -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void

    @State private var swipeOffset: CGFloat = 0
    @State private var isRevealed = false
    private let revealWidth: CGFloat = 76

    var body: some View {
        VStack(spacing: 0) {
            rowContent
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .offset(x: swipeOffset)
                .background(alignment: .trailing) { deleteButton }
                .clipped()
            Divider().padding(.leading, 52)
        }
        .background(heightReader)
        .offset(y: isDragging ? dragOffset : 0)
        .shadow(color: Color.black.opacity(isDragging ? 0.18 : 0), radius: 8, y: 2)
        .simultaneousGesture(swipeGesture)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Move up") { onMove(-1) }
        .accessibilityAction(named: "Move down") { onMove(1) }
        .accessibilityAction(named: "Delete point") { onDelete() }
    }

    private var rowContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.Colors.manentAccent)
                .frame(minWidth: 20, alignment: .leading)
                .accessibilityHidden(true)
            TextField("Add point", text: $text, axis: .vertical)
                .focused(focus, equals: id)
                .submitLabel(.next)
                .onSubmit(onReturn)
                .accessibilityLabel("Agenda point \(number)")
            if total > 1 {
                dragHandle
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.body.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { onDragChanged($0.translation.height) }
                    .onEnded { onDragEnded($0.translation.height) }
            )
            .accessibilityHidden(true)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            onDelete()
        } label: {
            Image(systemName: "trash")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: revealWidth)
                .frame(maxHeight: .infinity)
                .background(Color.red)
        }
        .buttonStyle(.plain)
        .opacity(swipeOffset < 0 ? 1 : 0)
        .allowsHitTesting(swipeOffset < -8)
        .accessibilityHidden(true)
    }

    private var heightReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: AgendaRowHeightKey.self, value: [id: proxy.size.height])
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                guard isHorizontal || swipeOffset != 0 else { return }
                let base: CGFloat = isRevealed ? -revealWidth : 0
                swipeOffset = min(0, max(-revealWidth * 2, base + value.translation.width))
            }
            .onEnded { _ in
                if swipeOffset <= -revealWidth * 1.8 {
                    swipeOffset = 0
                    isRevealed = false
                    onDelete()
                    return
                }
                let opens = swipeOffset < -revealWidth / 2
                withAnimation(.snappy) {
                    isRevealed = opens
                    swipeOffset = opens ? -revealWidth : 0
                }
            }
    }
}
