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
/// • Typing `[]` at the start of a line converts it to an unchecked checkbox.
/// • Return on a non-empty checkbox inserts a new empty checkbox below.
/// • Return on an empty checkbox exits checkbox mode (converts to plain text).
/// • Empty checkbox rows are silently removed when focus leaves them.
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
            guard serializeBodyLines(lines) != newText else { return }
            let newParsed = parseBodyLines(newText)
            // Preserve UUID identity for same-type lines at the same position so
            // ForEach doesn't destroy and recreate every row on an external reset.
            lines = newParsed.enumerated().map { i, newLine in
                guard i < lines.count else { return newLine }
                switch (lines[i], newLine) {
                case (.checkbox(let id, _, _), .checkbox(_, let c, let t)):
                    return .checkbox(id: id, checked: c, text: t)
                case (.plain(let id, _), .plain(_, let t)):
                    return .plain(id: id, text: t)
                default:
                    return newLine
                }
            }
        }
        .onChange(of: focusedIndex) { old, _ in
            // Remove empty checkbox rows the moment they lose focus.
            guard let old = old, old < lines.count else { return }
            if case .checkbox(_, _, let t) = lines[old], t.isEmpty, lines.count > 1 {
                let newFocus = focusedIndex
                lines.remove(at: old)
                commit()
                if let new = newFocus, new > old {
                    Task { @MainActor in focusedIndex = new - 1 }
                }
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
                    // Use raw text (no space-padding) so VoiceOver never says "space, checked"
                    let rawText = checkboxItemText(at: idx)
                    let state = checked ? "checked" : "unchecked"
                    return rawText.isEmpty ? state : "\(rawText), \(state)"
                }())
                .accessibilityHint("Toggle")

                if checked {
                    Text(checkedDisplayText(at: idx))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textTertiary)
                        .strikethrough(true, color: AppTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleCheckbox(at: idx) }
                        .accessibilityLabel(checkboxItemText(at: idx).isEmpty ? "Completed item" : checkboxItemText(at: idx))
                        .accessibilityValue("Completed")
                        .accessibilityHint("Tap to uncheck")
                } else {
                    TextField("", text: checkboxBinding(at: idx))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                        .focused($focusedIndex, equals: idx)
                        .onSubmit { handleEnterOnCheckbox(at: idx) }
                        .accessibilityLabel(checkboxItemText(at: idx).isEmpty ? "Checklist item" : checkboxItemText(at: idx))
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

    // MARK: - Text helpers

    /// Returns the raw text of a checkbox line (no space-padding for layout).
    private func checkboxItemText(at idx: Int) -> String {
        guard case .checkbox(_, _, let t) = lines[safe: idx] else { return "" }
        return t
    }

    /// Returns the checkbox text with a non-breaking space fallback for layout stability.
    private func checkedDisplayText(at idx: Int) -> String {
        let t = checkboxItemText(at: idx)
        return t.isEmpty ? "\u{00A0}" : t
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
            // Preserve the line's UUID so ForEach identity is stable and the
            // focusedIndex binding re-focuses the new checkbox TextField without
            // a nil-hop, avoiding a race with the empty-row cleanup onChange.
            if newVal.hasPrefix("[]") {
                let cleaned = String(newVal.dropFirst(2))
                guard case .plain(let id, _) = lines[idx] else { return }
                lines[idx] = .checkbox(id: id, checked: false, text: cleaned)
                commit()
                // focusedIndex is already idx — the re-rendered TextField claims focus.
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
            // Non-empty checkbox + Return → new empty checkbox below.
            // Note: SwiftUI TextField does not expose the cursor position, so the
            // text is not split at the caret — this is a known TextFieldlimitation.
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
    /// Returns (completed, total) counting only checkboxes that have text content.
    /// Bare `- [ ] ` markers with no label are excluded so the badge is not inflated
    /// by placeholder rows created while typing.
    var checklistProgress: (completed: Int, total: Int)? {
        let all = body.components(separatedBy: "\n")
        let total = all.filter { line in
            (line.hasPrefix("- [ ] ") && line.count > 6) ||
            (line.lowercased().hasPrefix("- [x] ") && line.count > 6)
        }.count
        guard total > 0 else { return nil }
        let done = all.filter { $0.lowercased().hasPrefix("- [x] ") && $0.count > 6 }.count
        return (done, total)
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
