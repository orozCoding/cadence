import SwiftUI
import AppKit

// MARK: - Public view (API unchanged)

struct ChecklistBodyEditor: View {
    @Binding var text: String
    var focusTrigger: Int = 0

    var body: some View {
        BodyEditorRepresentable(text: $text, focusTrigger: focusTrigger)
    }
}

// MARK: - Checkbox attachment

private final class CheckboxAttachment: NSTextAttachment {
    let isChecked: Bool

    init(isChecked: Bool) {
        self.isChecked = isChecked
        super.init(data: nil, ofType: nil)
        applyImage()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func applyImage() {
        let symName = isChecked ? "checkmark.square.fill" : "square"
        let color   = isChecked ? NSColor(AppTheme.accent) : NSColor(AppTheme.textTertiary)
        guard let base = NSImage(systemSymbolName: symName, accessibilityDescription: nil),
              let sized = base.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        else { return }

        // Build tinted image with right-side padding so the icon doesn't crowd text.
        let iconW: CGFloat = 14
        let pad:  CGFloat  = 4
        let h:    CGFloat  = 14
        let img = NSImage(size: NSSize(width: iconW + pad, height: h), flipped: false) { rect in
            sized.draw(in: NSRect(x: 0, y: 0, width: iconW, height: h))
            color.set()
            NSRect(x: 0, y: 0, width: iconW, height: h).fill(using: .sourceAtop)
            return true
        }
        image  = img
        bounds = CGRect(x: 0, y: -2, width: iconW + pad, height: h)
    }
}

// MARK: - NSTextView subclass

private final class BodyNSTextView: NSTextView {
    weak var bodyCoordinator: BodyEditorCoordinator?

    func configure(coordinator: BodyEditorCoordinator) {
        bodyCoordinator = coordinator
        isEditable      = true
        isSelectable    = true
        allowsUndo      = true
        isRichText      = true
        importsGraphics = false
        usesFontPanel   = false
        usesRuler       = false
        backgroundColor = .clear
        drawsBackground = false
        isVerticallyResizable   = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        textContainer?.lineFragmentPadding = 0
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticDashSubstitutionEnabled   = false
        isAutomaticQuoteSubstitutionEnabled  = false
        isAutomaticTextReplacementEnabled    = false
        delegate = coordinator
    }

    override var intrinsicContentSize: NSSize {
        guard let lm = layoutManager, let tc = textContainer else { return super.intrinsicContentSize }
        lm.ensureLayout(for: tc)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(lm.usedRect(for: tc).height, 16))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    // Detect clicks on attachment chars and route them as checkbox toggles.
    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if let lm = layoutManager, let tc = textContainer, let ts = textStorage {
            let idx = lm.characterIndex(for: pt, in: tc, fractionOfDistanceBetweenInsertionPoints: nil)
            if idx < ts.length,
               (ts.string as NSString).character(at: idx) == 0xFFFC,
               let att = ts.attribute(.attachment, at: idx, effectiveRange: nil) as? CheckboxAttachment {
                bodyCoordinator?.toggleCheckbox(att, in: self)
                return
            }
        }
        super.mouseDown(with: event)
    }

    // Fix [p2]: plain-text copy exports raw markdown, not U+FFFC attachment chars.
    // When nothing is selected, delegate to super (standard AppKit: copy nothing).
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let sel = selectedRange()
        guard sel.length > 0, let ts = textStorage, let coordinator = bodyCoordinator else {
            return super.writeSelection(to: pboard, types: types)
        }
        pboard.clearContents()
        pboard.setString(coordinator.extractRaw(from: ts, range: sel), forType: .string)
        return true
    }

    // Fix [p2]: VoiceOver reads readable descriptions instead of the U+FFFC glyph.
    override func accessibilityString(for range: NSRange) -> String? {
        guard let ts = textStorage, let coordinator = bodyCoordinator else {
            return super.accessibilityString(for: range)
        }
        let raw = coordinator.extractRaw(from: ts, range: range)
        // Convert "- [ ] " / "- [x] " to human-readable AX labels.
        return raw
            .replacingOccurrences(of: "- [x] ", with: "✓ ", options: .caseInsensitive)
            .replacingOccurrences(of: "- [ ] ", with: "□ ")
    }
}

// MARK: - NSViewRepresentable

private struct BodyEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    var focusTrigger: Int

    func makeCoordinator() -> BodyEditorCoordinator { BodyEditorCoordinator(text: $text) }

    func makeNSView(context: Context) -> BodyNSTextView {
        let tv = BodyNSTextView()
        tv.configure(coordinator: context.coordinator)
        context.coordinator.render(text, to: tv)
        return tv
    }

    func updateNSView(_ tv: BodyNSTextView, context: Context) {
        let c = context.coordinator
        if c.committedText != text { c.render(text, to: tv) }
        if focusTrigger > c.lastFocusTrigger {
            c.lastFocusTrigger = focusTrigger
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: tv.textStorage?.length ?? 0, length: 0))
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: BodyNSTextView, context: Context) -> CGSize? {
        guard let w = proposal.width, w > 0,
              let lm = tv.layoutManager, let tc = tv.textContainer else { return nil }
        tc.containerSize = CGSize(width: w, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        return CGSize(width: w, height: max(lm.usedRect(for: tc).height, 16))
    }
}

// MARK: - Coordinator

private final class BodyEditorCoordinator: NSObject, NSTextViewDelegate {
    @Binding var text: String
    var lastFocusTrigger = 0
    var committedText    = ""
    private var isRendering = false

    init(text: Binding<String>) {
        _text         = text
        committedText = text.wrappedValue
    }

    // MARK: Build display attributed string from raw text

    func buildAttr(_ raw: String) -> NSAttributedString {
        let result   = NSMutableAttributedString()
        let font     = NSFont.systemFont(ofSize: 13)
        let secondary = NSColor(AppTheme.textSecondary)
        let tertiary  = NSColor(AppTheme.textTertiary)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        let plainAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: secondary, .paragraphStyle: para]

        for (i, line) in raw.components(separatedBy: "\n").enumerated() {
            if i > 0 { result.append(NSAttributedString(string: "\n", attributes: plainAttrs)) }

            if line.hasPrefix("- [ ] ") || line.lowercased().hasPrefix("- [x] ") {
                let checked = line.lowercased().hasPrefix("- [x] ")
                let attAS = NSMutableAttributedString(attachment: CheckboxAttachment(isChecked: checked))
                attAS.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: attAS.length))
                result.append(attAS)
                let content = String(line.dropFirst(6))
                if checked {
                    result.append(NSAttributedString(string: content, attributes: [
                        .font: font, .foregroundColor: tertiary,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .strikethroughColor: tertiary, .paragraphStyle: para
                    ]))
                } else {
                    result.append(NSAttributedString(string: content, attributes: plainAttrs))
                }
            } else {
                result.append(NSAttributedString(string: line, attributes: plainAttrs))
            }
        }
        return result
    }

    // MARK: Extract raw text from display textStorage
    // Attachment chars (U+FFFC) are replaced with their "- [ ] " / "- [x] " prefixes.

    func extractRaw(from ts: NSTextStorage) -> String {
        extractRaw(from: ts, range: NSRange(location: 0, length: ts.length))
    }

    func extractRaw(from ts: NSTextStorage, range: NSRange) -> String {
        let ns     = ts.string as NSString
        let len    = ts.length
        let start  = max(0, range.location)
        let end    = min(len, NSMaxRange(range))
        var result = ""
        var i      = start
        while i < end {
            let ch = ns.character(at: i)
            if ch == 0xFFFC {
                if let att = ts.attribute(.attachment, at: i, effectiveRange: nil) as? CheckboxAttachment {
                    result += att.isChecked ? "- [x] " : "- [ ] "
                }
                i += 1
            } else if ch >= 0xD800 && ch <= 0xDBFF {
                // High surrogate: always emit as a pair to avoid malformed UTF-16.
                // Include the low surrogate even if it lies just outside the requested
                // range — a lone high surrogate is inherently invalid.
                let pairLen = (i + 1 < len) ? 2 : 1
                result += ns.substring(with: NSRange(location: i, length: pairLen))
                i += pairLen
            } else {
                result += ns.substring(with: NSRange(location: i, length: 1))
                i += 1
            }
        }
        return result
    }

    // MARK: Apply render (full rebuild)

    func render(_ raw: String, to tv: BodyNSTextView) {
        isRendering = true
        let sel = tv.selectedRange()
        tv.textStorage?.setAttributedString(buildAttr(raw))
        let newLen = tv.textStorage?.length ?? 0
        tv.setSelectedRange(NSRange(location: min(sel.location, newLen), length: 0))
        committedText = raw
        tv.invalidateIntrinsicContentSize()
        isRendering = false
    }

    // MARK: Checkbox toggle

    func toggleCheckbox(_ att: CheckboxAttachment, in tv: BodyNSTextView) {
        guard let ts = tv.textStorage else { return }
        let raw = extractRaw(from: ts)
        var lines = raw.components(separatedBy: "\n")
        // Identify which line holds this attachment object by identity.
        let ns = ts.string as NSString
        var lineIdx = 0
        var found   = false
        for i in 0..<ts.length {
            if ns.character(at: i) == 0x0A { lineIdx += 1 }
            if ns.character(at: i) == 0xFFFC,
               let a = ts.attribute(.attachment, at: i, effectiveRange: nil) as? CheckboxAttachment,
               a === att {
                found = true; break
            }
        }
        guard found, lineIdx < lines.count else { return }
        let ln = lines[lineIdx]
        if ln.hasPrefix("- [ ] ") {
            lines[lineIdx] = "- [x] " + ln.dropFirst(6)
        } else if ln.lowercased().hasPrefix("- [x] ") {
            lines[lineIdx] = "- [ ] " + ln.dropFirst(6)
        }
        let newRaw = lines.joined(separator: "\n")
        text = newRaw
        committedText = newRaw
        render(newRaw, to: tv)
    }

    // MARK: textDidChange

    func textDidChange(_ notification: Notification) {
        guard !isRendering,
              let tv = notification.object as? BodyNSTextView,
              let ts = tv.textStorage else { return }

        var raw = extractRaw(from: ts)

        // Scope `[]` detection to the currently-edited line only so that existing
        // plain-text lines that happen to start with `[]` are never silently converted.
        let cursor = tv.selectedRange().location
        let lines  = raw.components(separatedBy: "\n")
        let curLI  = lineIndex(for: cursor, in: ts)
        var conversionLine: Int? = nil
        if curLI < lines.count, lines[curLI].hasPrefix("[]") {
            var newLines = lines
            newLines[curLI] = "- [ ] " + newLines[curLI].dropFirst(2)
            raw = newLines.joined(separator: "\n")
            conversionLine = curLI
        }

        guard raw != committedText else { return }
        text = raw; committedText = raw

        let sel = tv.selectedRange()

        if let _ = conversionLine {
            // Structural change (attachment inserted): full rebuild required.
            // Regular typing does NOT rebuild — preserves IME/dead-key marked-text state.
            isRendering = true
            ts.setAttributedString(buildAttr(raw))
            let newLen = ts.length
            // `[]` (2 display chars) → `[FFFC]` (1 display char): shift cursor back by 1.
            tv.setSelectedRange(NSRange(location: min(max(0, sel.location - 1), newLen), length: 0))
            isRendering = false
        } else {
            // Check if the display structure is out of sync with the raw text.
            // This catches pasted checkbox syntax (including "- [X] " capital X)
            // that arrived as plain characters without attachment rendering.
            let newAttr = buildAttr(raw)
            if newAttr.string != ts.string {
                isRendering = true
                ts.setAttributedString(newAttr)
                tv.setSelectedRange(NSRange(location: min(sel.location, ts.length), length: 0))
                isRendering = false
            }
        }

        tv.invalidateIntrinsicContentSize()
    }

    // MARK: End-editing cleanup — remove empty checkbox lines on blur

    func textDidEndEditing(_ notification: Notification) {
        guard let tv = notification.object as? BodyNSTextView,
              let ts = tv.textStorage else { return }
        let raw   = extractRaw(from: ts)
        var lines = raw.components(separatedBy: "\n")

        let isEmptyCheckbox: (String) -> Bool = { line in
            (line.hasPrefix("- [ ] ") || line.lowercased().hasPrefix("- [x] ")) &&
            line.dropFirst(6).trimmingCharacters(in: .whitespaces).isEmpty
        }

        if lines.count > 1 {
            let filtered = lines.filter { !isEmptyCheckbox($0) }
            guard filtered.count != lines.count else { return }
            lines = filtered.isEmpty ? [""] : filtered
        } else if lines.count == 1, isEmptyCheckbox(lines[0]) {
            lines[0] = ""
        } else {
            return
        }

        let newRaw = lines.joined(separator: "\n")
        text = newRaw; committedText = newRaw
        isRendering = true
        ts.setAttributedString(buildAttr(newRaw))
        isRendering = false
        tv.invalidateIntrinsicContentSize()
    }

    // MARK: Return key — maintain checklist line continuation

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)),
              let tv = textView as? BodyNSTextView,
              let ts = tv.textStorage else { return false }

        let cursor = tv.selectedRange().location
        let ns     = ts.string as NSString

        // Find start of current line by scanning backwards for newline.
        var lineStart = 0
        if cursor > 0 {
            for i in stride(from: cursor - 1, through: 0, by: -1) {
                if ns.character(at: i) == 0x0A { lineStart = i + 1; break }
            }
        }

        // Only intercept if the line starts with a checkbox attachment.
        guard lineStart < ts.length,
              ns.character(at: lineStart) == 0xFFFC,
              let att = ts.attribute(.attachment, at: lineStart, effectiveRange: nil) as? CheckboxAttachment
        else { return false }

        // Content starts immediately after the attachment char.
        let contentStart = lineStart + 1
        var lineEnd = ts.length
        for i in contentStart..<ts.length {
            if ns.character(at: i) == 0x0A { lineEnd = i; break }
        }
        let displayContent = lineEnd > contentStart
            ? ns.substring(with: NSRange(location: contentStart, length: lineEnd - contentStart))
            : ""

        let raw      = extractRaw(from: ts)
        var rawLines = raw.components(separatedBy: "\n")
        let li       = lineIndex(for: lineStart, in: ts)
        guard li < rawLines.count else { return false }

        if displayContent.trimmingCharacters(in: .whitespaces).isEmpty {
            // Empty checkbox → exit checkbox mode (convert to plain text line).
            rawLines[li] = ""
            let newRaw = rawLines.joined(separator: "\n")
            text = newRaw; committedText = newRaw
            // Fix [p3]: rebuild and explicitly place cursor on the new plain line
            // (don't reuse the old offset which still referenced the attachment char).
            let newAttr = buildAttr(newRaw)
            isRendering = true
            ts.setAttributedString(newAttr)
            let newLinePos = displayLineStart(li, in: tv)
            tv.setSelectedRange(NSRange(location: min(newLinePos, ts.length), length: 0))
            isRendering = false
            tv.invalidateIntrinsicContentSize()
        } else {
            // Split content at cursor using UTF-16 offsets (NSTextView cursor is UTF-16).
            // Using grapheme-based Swift String indexing would mis-split on emoji.
            // max(0, ...) clamps gracefully when cursor sits on the attachment glyph itself.
            let utf16Offset   = max(0, min(cursor - contentStart, (displayContent as NSString).length))
            let displayNS     = displayContent as NSString
            let before        = displayNS.substring(to: utf16Offset)
            let after         = displayNS.substring(from: utf16Offset)

            let pfx = att.isChecked ? "- [x] " : "- [ ] "
            rawLines[li] = pfx + before
            rawLines.insert("- [ ] " + after, at: li + 1)
            let newRaw = rawLines.joined(separator: "\n")
            text = newRaw; committedText = newRaw

            let newAttr = buildAttr(newRaw)
            isRendering = true
            ts.setAttributedString(newAttr)
            let newLen = ts.length
            // Cursor goes to the start of the new checkbox's content area.
            let newLinePos = lineContentStart(li + 1, in: tv)
            tv.setSelectedRange(NSRange(location: min(newLinePos, newLen), length: 0))
            isRendering = false
            tv.invalidateIntrinsicContentSize()
        }
        return true
    }

    // MARK: Helpers

    /// Index (0-based) of the line that contains display position `pos`.
    private func lineIndex(for pos: Int, in ts: NSTextStorage) -> Int {
        let ns = ts.string as NSString
        var count = 0
        for i in 0..<min(pos, ts.length) {
            if ns.character(at: i) == 0x0A { count += 1 }
        }
        return count
    }

    /// Display position of the first char of `lineIdx` (0-based).
    private func displayLineStart(_ lineIdx: Int, in tv: BodyNSTextView) -> Int {
        guard let ts = tv.textStorage else { return 0 }
        let ns = ts.string as NSString
        var count = 0
        for i in 0..<ts.length {
            if count == lineIdx { return i }
            if ns.character(at: i) == 0x0A { count += 1 }
        }
        return ts.length
    }

    /// Display position of the content area start of `lineIdx`.
    /// For checkbox lines that's lineStart+1; for plain lines it's lineStart.
    private func lineContentStart(_ lineIdx: Int, in tv: BodyNSTextView) -> Int {
        guard let ts = tv.textStorage else { return 0 }
        let start = displayLineStart(lineIdx, in: tv)
        if start < ts.length,
           (ts.string as NSString).character(at: start) == 0xFFFC {
            return start + 1
        }
        return start
    }
}

// MARK: - CadenceTask checklist helpers

extension CadenceTask {
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
