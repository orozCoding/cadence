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
    // Protocol-relative reference (//host/path) → prepend https:
    if s.hasPrefix("//") { return "https:" + s }
    // Return early only when :// belongs to a scheme at the very start of the string.
    // s.contains("://") would falsely match query values like
    // example.com?next=https://idp.example/callback.
    // RFC 3986 scheme chars: ALPHA / DIGIT / "+" / "-" / "."
    let possibleScheme = s.prefix(while: { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." })
    if !possibleScheme.isEmpty && s[possibleScheme.endIndex...].hasPrefix("://") { return s }
    // Bare email address (localpart@domain, no scheme) → mailto:
    // Fires when @ appears before the first '/' (so path @-signs like /@handle are ignored)
    // and the local part contains no colon (which would indicate user:pass credentials).
    // No dot requirement so single-label domains (user@localhost, user@buildbox) are covered.
    let firstSlash = s.firstIndex(of: "/")
    if let at = s.firstIndex(of: "@"), firstSlash == nil || at < (firstSlash ?? s.endIndex) {
        let localPart = String(s[..<at])
        if !localPart.contains(":") { return "mailto:" + s }
    }
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
    // Private/link-local IPv4 ranges → http (these rarely have TLS certs).
    // Extract the host portion (up to the first : / ? #) and parse octets.
    let hostPart = lower.prefix(while: { $0 != ":" && $0 != "/" && $0 != "?" && $0 != "#" })
    let octets = hostPart.split(separator: ".").compactMap { Int($0) }
    if octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) {
        let (a, b) = (octets[0], octets[1])
        if a == 10 || a == 127 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) || (a == 169 && b == 254) {
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
        let beforeColon = String(authority[colonSearchFrom..<colon])
        let bcLower = beforeColon.lowercased()
        // Empty afterColon + path/query after authority = scheme with single-slash path
        // (e.g. com.example.app:/oauth). Leave non-web deep links as-is; repair http:/https:.
        if afterColon.isEmpty && authEnd < s.endIndex {
            if bcLower == "http" || bcLower == "https" {
                let pathStart = s.index(after: authEnd)
                return bcLower + "://" + String(s[pathStart...])
            }
            return s
        }
        // Known non-web URI schemes whose "opaque part" is all-numeric (e.g. tel:911, sms:1234).
        // Check these before the port heuristic so they are not mangled into https://tel:911.
        let knownNonWebSchemes: Set<String> = ["tel", "sms", "fax", "callto", "xmpp"]
        if knownNonWebSchemes.contains(bcLower) { return s }

        // Port heuristic: purely-numeric afterColon within valid range = host:port.
        // This ensures single-label intranet hosts (buildbox:8080, jenkins:3000/path) are
        // correctly prefixed with https:// rather than silently stored as opaque URIs.
        let portStr = String(afterColon.prefix(while: \.isNumber))
        let isPort = !portStr.isEmpty
            && afterColon.dropFirst(portStr.count).isEmpty
            && (Int(portStr) ?? 65536) <= 65535
        if !isPort {
            if !beforeColon.isEmpty && beforeColon.allSatisfy(\.isLetter) {
                // All-letter, non-port afterColon = URI scheme (tel:+1234, spotify:track, etc.)
                if bcLower == "http" || bcLower == "https" {
                    let pathSuffix = authEnd < s.endIndex ? String(s[authEnd...]) : ""
                    return bcLower + "://" + String(afterColon) + pathSuffix
                }
                return s
            }
            // beforeColon has dots/digits: hostname territory.
            // A dot means it's a hostname (example.com:abc) — fall through to prepend https://.
            // No dot and no valid port: unknown opaque form — leave as-is.
            if !beforeColon.contains(".") { return s }
        }
    }
    return "https://" + s
}

// Returns true when the (already-normalized) URL string is safe to save / open.
// Rejects http/https with an empty host, which URL(string:) accepts but browsers reject.
func isSaveableURL(_ normalized: String) -> Bool {
    guard let u = URL(string: normalized) else { return false }
    let scheme = u.scheme?.lowercased() ?? ""
    // Reject execution/data schemes — URL(string:) accepts them but NSWorkspace won't open them.
    if scheme == "javascript" || scheme == "data" { return false }
    // Reject http/https with empty host (e.g. "https://") — valid URL but browsers refuse it.
    if scheme == "http" || scheme == "https" { return !(u.host?.isEmpty ?? true) }
    return true
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

    // Rows beyond this threshold scroll inside a fixed-height container so the
    // deadline pickers and Save button are never pushed off-screen.
    private static let scrollThreshold = 4

    @ViewBuilder
    private var urlRows: some View {
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

                if !urls[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   isSaveableURL(normalizeURL(urls[i])) {
                    Button(action: {
                        let normalized = normalizeURL(urls[i])
                        guard let u = URL(string: normalized) else { return }
                        NSWorkspace.shared.open(u)
                    }) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .help("Open link")
                    .accessibilityLabel("Open \(urls[i])")
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .animation(.easeInOut(duration: 0.12), value: urls[i].isEmpty)
                }

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
                    .accessibilityLabel("Remove \(urls[i].isEmpty ? "empty URL" : urls[i])")
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("URLs", systemImage: "globe")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)

            // When few rows are present use a plain VStack; beyond the threshold
            // wrap in a fixed-height ScrollView so the footer never overflows.
            if urls.count <= URLEditSection.scrollThreshold {
                VStack(spacing: 8) { urlRows }
            } else {
                ScrollView {
                    VStack(spacing: 8) { urlRows }
                }
                .frame(height: 176)
            }

            if !(urls.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) && urls.count < 10 {
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
        .onChange(of: urls.count) { count in
            // Keep entryIds in sync if the parent binding is mutated externally
            // (avoids zip silently dropping rows when counts diverge).
            while entryIds.count < count { entryIds.append(UUID()) }
            if entryIds.count > count { entryIds = Array(entryIds.prefix(count)) }
            // Guarantee at least one row so the Add URL button is always reachable.
            if count == 0 { urls.append(""); entryIds.append(UUID()) }
        }
    }
}

struct URLBadgeIcon: View {
    let url: String
    @State private var isHovered = false
    @State private var showPopover = false

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
                .animation(.easeInOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                // Delay prevents the popover from flashing when the mouse passes over quickly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if isHovered { showPopover = true }
                }
            } else {
                showPopover = false
            }
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            Text(url)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 220, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .accessibilityLabel("Open URL: \(url)")
        .accessibilityAddTraits(.isLink)
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
