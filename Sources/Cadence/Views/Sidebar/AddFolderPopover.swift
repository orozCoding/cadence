import SwiftUI

struct AddFolderPopover: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var folderStore: FolderStore
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Folder")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)

            TextField("Folder name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.sidebarBackground))
                .onSubmit { createFolder() }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .pointerCursor()

                Button("Add") { createFolder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(name.trimmingCharacters(in: .whitespaces).isEmpty ? AppTheme.textTertiary : AppTheme.accent)
                    )
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .pointerCursor()
            }
        }
        .padding(16)
        .frame(width: 220)
    }

    private func createFolder() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        folderStore.add(name: trimmed)
        isPresented = false
    }
}
