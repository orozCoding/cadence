import SwiftUI

struct FolderSwitcher: View {
    @EnvironmentObject var folderStore: FolderStore
    @Binding var showAddFolder: Bool

    var body: some View {
        Menu {
            ForEach(folderStore.folders) { folder in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        folderStore.setActive(folder)
                    }
                } label: {
                    if folder.id == folderStore.activeFolder.id {
                        Label(folder.name, systemImage: "checkmark")
                    } else {
                        Text(folder.name)
                    }
                }
            }
            Divider()
            Button("Add New Folder…") { showAddFolder = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.accent)
                Text(folderStore.activeFolder.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).fill(AppTheme.hoveredItem))
        }
        .menuStyle(.borderlessButton)
        .pointerCursor()
    }
}
