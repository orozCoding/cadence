import SwiftUI

// MARK: - Line model (file-private)

private enum BodyLine {
    case checkbox(id: UUID, checked: Bool, text: String)
    case plain(id: UUID, text: String)

    var id: UUID {
        switch self {
        case .checkbox(let id, _, _): return id
        case .plain(let id, _): return id
        }
    }
}

private func parseBodyLines(_ body: String) -> [BodyLine] {
    guard !body.isEmpty else { return [.plain(id: UUID(), text: "")] }
    return body.components(separatedBy: "\n").map { line in
        if line.hasPrefix("- [ ] ") {
            return .checkbox(id: UUID(), checked: false, text: String(line.dropFirst(6)))
        } else if line.lowercased().hasPrefix("- [x] ") {
            // Accept both [x] and [X] as checked markers
            return .checkbox(id: UUID(), checked: true, text: String(line.dropFirst(6)))
        } else {
            return .plain(id: UUID(), text: line)
        }
    }
}

private func serializeBodyLines(_ lines: [BodyLine]) -> String {
    lines.map { line -> String in
        switch line {
        case .checkbox(_, let checked, let text):
            return (checked ? "- [x] " : "- [ ] ") + text
        case .plain(_, let text):
            return text
        }
    }.joined(separator: "\n")
}

// MARK: - ChecklistBodyEditor

/// Renders a task body as a mix of interactive checkbox rows and plain-text lines.
/// Typing `[]` in any plain-text line instantly converts it to an unchecked checkbox.
/// Pressing Return on a non-empty checkbox inserts a new empty checkbox below.
/// Pressing Return on an empty checkbox exits checkbox mode (converts to plain text).
struct ChecklistBodyEditor: View {
    @Binding var text: String

    @FocusState private var focusedIndex: Int?
    @State private var lines: [BodyLine]

    init(text: Binding<String>) {
        self._text = text
        self._lines = State(initialValue: parseBodyLines(text.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                rowView(at: idx, line: line)
            }
        }
        .onChange(of: text) { _, newText in
            if serializeBodyLines(lines) != newText {
                lines = parseBodyLines(newText)
            }
        }
    }

    // MARK: - Row rendering

    @ViewBuilder
    private func rowView(at idx: Int, line: BodyLine) -> some View {
        switch line {
        case .checkbox(_, let checked, _):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button { toggleCheckbox(at: idx) } label: {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14))
                        .foregroundStyle(checked ? AppTheme.accent : AppTheme.textTertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .accessibilityLabel({
                    let label = checked ? checkedText(at: idx) : uncheckedText(at: idx)
                    let state = checked ? "checked" : "unchecked"
                    return label.isEmpty ? state : "\(label), \(state)"
                }())
                .accessibilityHint("Toggle")

                if checked {
                    Text(checkedText(at: idx))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textTertiary)
                        .strikethrough(true, color: AppTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleCheckbox(at: idx) }
                        .accessibilityLabel(checkedText(at: idx))
                        .accessibilityValue("Completed")
                } else {
                    TextField("", text: checkboxBinding(at: idx))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                        .focused($focusedIndex, equals: idx)
                        .onSubmit { handleEnterOnCheckbox(at: idx) }
                        .accessibilityLabel(uncheckedText(at: idx).isEmpty ? "Checklist item" : uncheckedText(at: idx))
                        .accessibilityValue("Unchecked")
                }
            }
            .padding(.vertical, 2)

        case .plain(_, _):
            TextField("", text: plainBinding(at: idx))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textSecondary)
                .focused($focusedIndex, equals: idx)
                .onSubmit { handleEnterOnPlain(at: idx) }
                .accessibilityLabel(plainText(at: idx).isEmpty ? "Description line" : plainText(at: idx))
                .padding(.vertical, 2)
        }
    }

    private func checkedText(at idx: Int) -> String {
        guard case .checkbox(_, _, let t) = lines[safe: idx] else { return "" }
        return t.isEmpty ? " " : t
    }

    private func uncheckedText(at idx: Int) -> String {
        guard case .checkbox(_, _, let t) = lines[safe: idx] else { return "" }
        return t
    }

    private func plainText(at idx: Int) -> String {
        guard case .plain(_, let t) = lines[safe: idx] else { return "" }
        return t
    }

    // MARK: - Bindings

    private func checkboxBinding(at idx: Int) -> Binding<String> {
        Binding {
            guard case .checkbox(_, _, let t) = lines[safe: idx] else { return "" }
            return t
        } set: { newVal in
            guard idx < lines.count, case .checkbox(let id, let c, _) = lines[idx] else { return }
            lines[idx] = .checkbox(id: id, checked: c, text: newVal)
            commit()
        }
    }

    private func plainBinding(at idx: Int) -> Binding<String> {
        Binding {
            guard case .plain(_, let t) = lines[safe: idx] else { return "" }
            return t
        } set: { newVal in
            guard idx < lines.count else { return }
            // [] at the START of the line triggers a checkbox conversion,
            // so prose like "array[idx]" is never accidentally converted.
            if newVal.hasPrefix("[]") {
                let cleaned = String(newVal.dropFirst(2))
                lines[idx] = .checkbox(id: UUID(), checked: false, text: cleaned)
                commit()
                Task { @MainActor in focusedIndex = idx }
                return
            }
            guard case .plain(let id, _) = lines[idx] else { return }
            lines[idx] = .plain(id: id, text: newVal)
            commit()
        }
    }

    // MARK: - Actions

    private func toggleCheckbox(at idx: Int) {
        guard idx < lines.count, case .checkbox(let id, let c, let t) = lines[idx] else { return }
        lines[idx] = .checkbox(id: id, checked: !c, text: t)
        commit()
    }

    private func handleEnterOnCheckbox(at idx: Int) {
        guard case .checkbox(_, _, let t) = lines[safe: idx] else { return }
        if t.isEmpty {
            // Empty checkbox + Return → exit checkbox mode
            lines[idx] = .plain(id: UUID(), text: "")
            commit()
            Task { @MainActor in focusedIndex = idx }
        } else {
            // Non-empty checkbox + Return → new empty checkbox below
            lines.insert(.checkbox(id: UUID(), checked: false, text: ""), at: idx + 1)
            commit()
            Task { @MainActor in focusedIndex = idx + 1 }
        }
    }

    private func handleEnterOnPlain(at idx: Int) {
        lines.insert(.plain(id: UUID(), text: ""), at: idx + 1)
        commit()
        Task { @MainActor in focusedIndex = idx + 1 }
    }

    private func commit() {
        let serialized = serializeBodyLines(lines)
        if text != serialized { text = serialized }
    }
}

// MARK: - CadenceTask checklist helpers

extension CadenceTask {
    /// Returns (completed, total) if the body contains any checkbox lines, otherwise nil.
    var checklistProgress: (completed: Int, total: Int)? {
        let all = body.components(separatedBy: "\n")
        let total = all.filter { $0.hasPrefix("- [ ] ") || $0.lowercased().hasPrefix("- [x] ") }.count
        guard total > 0 else { return nil }
        let done = all.filter { $0.lowercased().hasPrefix("- [x] ") }.count
        return (done, total)
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
