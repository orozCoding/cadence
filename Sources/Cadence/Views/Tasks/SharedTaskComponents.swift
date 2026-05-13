import SwiftUI
import AppKit

struct TasksHeader<Trailing: View>: View {
    let title: String
    let onNewTask: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, onNewTask: @escaping () -> Void, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.onNewTask = onNewTask
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            trailing()

            Button(action: onNewTask) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(AppTheme.accent))
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("New Task")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}


struct SectionHeader: View {
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Text("\(count)")
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(AppTheme.contentBackground)
    }
}

struct EmptyStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(AppTheme.textTertiary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Deadline toggle row (used by TaskCreateView and TaskEditView)

struct DeadlineToggleRow<Content: View>: View {
    let icon: String
    let label: String
    @Binding var isEnabled: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            Toggle(label, isOn: $isEnabled)
                .labelsHidden()
                .accessibilityLabel("\(label) deadline")
                .toggleStyle(.switch)
                .controlSize(.small)
                .pointerCursor()

            Button(action: { isEnabled.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(isEnabled ? AppTheme.accent : AppTheme.textTertiary)
                        .frame(width: 16)

                    Text(label)
                        .font(.system(size: 13))
                        .foregroundStyle(isEnabled ? AppTheme.textPrimary : AppTheme.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .pointerCursor()

            Spacer()

            if isEnabled {
                content()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isEnabled)
    }
}

// MARK: - URL Normalization

func normalizeURL(_ raw: String) -> String {
    let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return s }
    // Return early only when :// belongs to a scheme at the very start of the string.
    // s.contains("://") would falsely match query values like
    // example.com?next=https://idp.example/callback.
    // RFC 3986 scheme chars: ALPHA / DIGIT / "+" / "-" / "."
    let possibleScheme = s.prefix(while: { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." })
    if !possibleScheme.isEmpty && s[possibleScheme.endIndex...].hasPrefix("://") { return s }
    let lower = s.lowercased()
    // Loopback addresses → http. Match at hostname boundary so localhost.run
    // or 127.0.0.1.example.com are not misclassified.
    let loopbackHosts = ["localhost", "127.0.0.1", "[::1]"]
    for host in loopbackHosts where lower.hasPrefix(host) {
        let rest = lower.dropFirst(host.count)
        if rest.isEmpty || rest.hasPrefix(":") || rest.hasPrefix("/")
            || rest.hasPrefix("?") || rest.hasPrefix("#") {
            return "http://" + s
        }
    }
    // Distinguish host:port from a non-authority URI scheme (mailto:, tel:, spotify:, etc.).
    // Only inspect the authority portion — before the first / ? # — so that a colon inside
    // a query string (e.g. example.com?next=foo:bar) is not mistaken for a scheme separator.
    let authEnd = s.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? s.endIndex
    let authority = s[s.startIndex..<authEnd]
    // For IPv6 literals like [2001:db8::1]:3000 the colons inside the brackets
    // must not be treated as a scheme separator; start searching after the ']'.
    let colonSearchFrom: String.Index
    if authority.hasPrefix("["), let bracket = authority.firstIndex(of: "]") {
        colonSearchFrom = authority.index(after: bracket)
    } else {
        colonSearchFrom = authority.startIndex
    }
    if let colon = authority[colonSearchFrom...].firstIndex(of: ":") {
        let afterColon = authority[authority.index(after: colon)...]
        let portStr = String(afterColon.prefix(while: \.isNumber))
        let isPort = !portStr.isEmpty
            && afterColon.dropFirst(portStr.count).isEmpty
            && (Int(portStr) ?? 65536) <= 65535
        if !isPort {
            // Treat this as a URI scheme (mailto:, tel:, spotify:, etc.) only when
            // the part before the colon contains no dot.  No registered URI scheme
            // name includes a dot, so a dot signals a hostname (e.g. example.com:abc)
            // that should receive the https:// prefix instead.
            let beforeColon = String(authority[colonSearchFrom..<colon])
            if !beforeColon.contains(".") { return s }
        }
    }
    return "https://" + s
}

// MARK: - URL Components

struct URLEditSection: View {
    @Binding var urls: [String]
    // Stable per-row identities so SwiftUI doesn't remap TextField state
    // (focus, cursor) when a middle entry is removed.
    @State private var entryIds: [UUID]

    init(urls: Binding<[String]>) {
        self._urls = urls
        self._entryIds = State(initialValue: urls.wrappedValue.map { _ in UUID() })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("URLs", systemImage: "globe")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)

            ForEach(Array(zip(entryIds, urls.indices)), id: \.0) { _, i in
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 13))
                        .foregroundStyle(urls[i].isEmpty ? AppTheme.textTertiary : AppTheme.accent)
                        .frame(width: 16)
                        .animation(.easeInOut(duration: 0.15), value: urls[i].isEmpty)

                    TextField("Paste a URL...", text: $urls[i])
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.sidebarBackground))

                    if urls.count > 1 {
                        Button(action: {
                            var nextUrls = urls
                            var nextIds = entryIds
                            nextUrls.remove(at: i)
                            nextIds.remove(at: i)
                            urls = nextUrls
                            entryIds = nextIds
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .pointerCursor()
                        .accessibilityLabel("Remove URL")
                    }
                }
            }

            if !(urls.last?.isEmpty ?? true) && urls.count < 10 {
                Button(action: { urls.append(""); entryIds.append(UUID()) }) {
                    Label("Add URL", systemImage: "plus.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                .animation(.easeInOut(duration: 0.15), value: urls.last?.isEmpty ?? true)
            }
        }
    }
}

struct URLBadgeIcon: View {
    let url: String
    @State private var isHovered = false

    var body: some View {
        Button(action: openInBrowser) {
            Image(systemName: "globe")
                .font(.system(size: 10))
                .foregroundStyle(isHovered ? AppTheme.accentDark : AppTheme.accentLight)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.accentLight.opacity(isHovered ? 0.22 : 0.12))
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { isHovered = $0 }
        .help(url)
        .accessibilityLabel("Open URL: \(url)")
    }

    private func openInBrowser() {
        // URLs are normalized at save time; apply normalizeURL as a fallback for legacy entries.
        guard let u = URL(string: normalizeURL(url)) else { return }
        NSWorkspace.shared.open(u)
    }
}

struct URLOverflowBadge: View {
    let urls: [String]
    @State private var isHovered = false

    var body: some View {
        Button(action: openAll) {
            Text("+\(urls.count)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(isHovered ? AppTheme.textSecondary : AppTheme.textTertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTheme.divider.opacity(isHovered ? 0.75 : 0.5))
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { isHovered = $0 }
        .help("Open \(urls.count) more URL\(urls.count == 1 ? "" : "s")")
        .accessibilityLabel("Open \(urls.count) more URL\(urls.count == 1 ? "" : "s")")
    }

    private func openAll() {
        for url in urls {
            guard let u = URL(string: normalizeURL(url)) else { continue }
            NSWorkspace.shared.open(u)
        }
    }
}
