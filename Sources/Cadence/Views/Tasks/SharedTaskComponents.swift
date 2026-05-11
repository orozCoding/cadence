import SwiftUI

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
