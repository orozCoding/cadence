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
/// • Return splits the current line at the cursor, inserting the suffix into a new row.
/// • Return on an empty checkbox exits checkbox mode (converts to plain text).
/// • Backspace on an empty row removes it and moves focus up.
/// • Empty checkbox rows are removed when focus leaves them.
struct ChecklistBodyEditor: View {
    @Binding var text: String
    var focusTrigger: Int = 0

    @FocusState private var focusedIndex: Int?
    @State private var lines: [BodyLine]
    @State private var suppressCleanup = false

    init(text: Binding<String>, focusTrigger: Int = 0) {
        self._text = text
        self.focusTrigger = focusTrigger
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
            // ForEach doesn't destroy and recreate rows on an external reset.
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
        .onChange(of: focusedIndex) { old, new in
            guard !suppressCleanup else { return }
            guard let old = old, old < lines.count else { return }
            guard case .checkbox(_, _, let t) = lines[old],
                  t.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            if lines.count > 1 {
                lines.remove(at: old)
                commit()
                if let new = new, new > old {
                    Task { @MainActor in focusedIndex = new - 1 }
                }
            } else {
                lines[0] = .plain(id: lines[0].id, text: "")
                commit()
            }
        }
        .onChange(of: focusTrigger) { _, _ in
            // All rows use TextField so every index is focusable.
            focusedIndex = lines.indices.last
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
                    let rawText = checkboxItemText(at: idx)
                    let state = checked ? "checked" : "unchecked"
                    return rawText.isEmpty ? state : "\(rawText), \(state)"
                }())
                .accessibilityHint("Toggle")

                TextField("", text: checkboxBinding(at: idx))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(checked ? AppTheme.textTertiary : AppTheme.textSecondary)
                    .strikethrough(checked, color: AppTheme.textTertiary)
                    .focused($focusedIndex, equals: idx)
                    .onKeyPress(.return) {
                        let pos = (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectedRange().location
                        handleEnterOnCheckbox(at: idx, cursorPos: pos)
                        return .handled
                    }
                    .onKeyPress(.delete) {
                        guard checkboxItemText(at: idx).trimmingCharacters(in: .whitespaces).isEmpty else { return .ignored }
                        if lines.count > 1 {
                            if idx > 0 { Task { @MainActor in focusedIndex = idx - 1 } }
                            lines.remove(at: idx)
                            commit()
                        } else {
                            lines[0] = .plain(id: lines[0].id, text: "")
                            commit()
                        }
                        return .handled
                    }
                    .accessibilityLabel(checkboxItemText(at: idx).isEmpty
                        ? (checked ? "Completed item" : "Checklist item")
                        : checkboxItemText(at: idx))
                    .accessibilityValue(checked ? "Completed" : "To do")
            }
            .padding(.vertical, 2)

        case .plain(_, _):
            TextField("", text: plainBinding(at: idx))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textSecondary)
                .focused($focusedIndex, equals: idx)
                .onKeyPress(.return) {
                    let pos = (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectedRange().location
                    handleEnterOnPlain(at: idx, cursorPos: pos)
                    return .handled
                }
                .onKeyPress(.delete) {
                    guard plainText(at: idx).isEmpty && lines.count > 1 else { return .ignored }
                    if idx > 0 { Task { @MainActor in focusedIndex = idx - 1 } }
                    lines.remove(at: idx)
                    commit()
                    return .handled
                }
                .accessibilityLabel(plainText(at: idx).isEmpty ? "Description line" : plainText(at: idx))
                .padding(.vertical, 2)
        }
    }

    // MARK: - Text helpers

    private func checkboxItemText(at idx: Int) -> String {
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
            // [] at the START of the line triggers checkbox conversion.
            // Preserve the UUID so ForEach identity is stable across the type change.
            // Use nil→idx focus hop so @FocusState sees a real transition; suppressCleanup
            // prevents the blur-cleanup from removing the newly created empty checkbox.
            if newVal.hasPrefix("[]") {
                let cleaned = String(newVal.dropFirst(2))
                guard case .plain(let id, _) = lines[idx] else { return }
                lines[idx] = .checkbox(id: id, checked: false, text: cleaned)
                commit()
                suppressCleanup = true
                focusedIndex = nil
                Task { @MainActor in
                    focusedIndex = idx
                    suppressCleanup = false
                }
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

    private func handleEnterOnCheckbox(at idx: Int, cursorPos: Int? = nil) {
        guard case .checkbox(_, let c, let t) = lines[safe: idx] else { return }
        if t.trimmingCharacters(in: .whitespaces).isEmpty {
            // Empty checkbox + Return → exit checkbox mode
            lines[idx] = .plain(id: UUID(), text: "")
            commit()
            Task { @MainActor in focusedIndex = idx }
        } else {
            // Split at cursor; if no cursor info, insert empty row below.
            let suffix: String
            if let pos = cursorPos {
                let clampedPos = min(pos, t.utf16.count)
                let splitIdx = String.Index(utf16Offset: clampedPos, in: t)
                let prefix = String(t[..<splitIdx])
                suffix = String(t[splitIdx...])
                guard case .checkbox(let id, _, _) = lines[idx] else { return }
                lines[idx] = .checkbox(id: id, checked: c, text: prefix)
            } else {
                suffix = ""
            }
            lines.insert(.checkbox(id: UUID(), checked: false, text: suffix), at: idx + 1)
            commit()
            Task { @MainActor in focusedIndex = idx + 1 }
        }
    }

    private func handleEnterOnPlain(at idx: Int, cursorPos: Int? = nil) {
        let t = plainText(at: idx)
        let suffix: String
        if let pos = cursorPos {
            let clampedPos = min(pos, t.utf16.count)
            let splitIdx = String.Index(utf16Offset: clampedPos, in: t)
            let prefix = String(t[..<splitIdx])
            suffix = String(t[splitIdx...])
            guard case .plain(let id, _) = lines[idx] else { return }
            lines[idx] = .plain(id: id, text: prefix)
        } else {
            suffix = ""
        }
        lines.insert(.plain(id: UUID(), text: suffix), at: idx + 1)
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
    /// Returns (completed, total) counting only checkboxes that have non-whitespace text.
    var checklistProgress: (completed: Int, total: Int)? {
        let all = body.components(separatedBy: "\n")
        let hasText: (String, String) -> Bool = { line, prefix in
            !line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces).isEmpty
        }
        let total = all.filter { line in
            (line.hasPrefix("- [ ] ") && hasText(line, "- [ ] ")) ||
            (line.lowercased().hasPrefix("- [x] ") && hasText(line, "- [x] "))
        }.count
        guard total > 0 else { return nil }
        let done = all.filter { $0.lowercased().hasPrefix("- [x] ") && hasText($0, "- [x] ") }.count
        return (done, total)
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
