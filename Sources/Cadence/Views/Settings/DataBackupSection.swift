import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings section that lets the user export every piece of app state to a
/// single JSON file (and immediately share it through the system share
/// sheet) or import such a file to restore everything on a different
/// machine. "Everything" means tasks, folders, focus history, preferences,
/// and the active folder — anything the app persists.
struct DataBackupSection: View {
    @State private var showImportConfirm = false
    @State private var pendingImport: CadenceBackup?
    @State private var pendingImportFilename: String?
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var shareAnchor: NSView?
    @State private var canRestore = BackupService.hasPreImportSnapshot()
    @State private var hadInterruptedImport = BackupService.hasInterruptedImport()
    @State private var showRestoreConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)

            Text("Back up everything — tasks, folders, focus history, and preferences — to a single file you can move between machines.")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if hadInterruptedImport {
                interruptedImportBanner
            }

            HStack(spacing: 8) {
                ShareAnchorButton(
                    title: "Export & Share…",
                    systemImage: "square.and.arrow.up",
                    isPrimary: true
                ) { anchor in
                    exportAndShare(anchor: anchor)
                }
                .accessibilityHint("Save a backup file and present the share sheet")

                Button {
                    chooseImportFile()
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .pointerCursor()
                .accessibilityHint("Replace all local data with the contents of a backup file")

                Spacer()
            }

            if canRestore {
                HStack(spacing: 8) {
                    Button {
                        showRestoreConfirm = true
                    } label: {
                        Label("Restore previous data", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .pointerCursor()
                    .accessibilityHint("Roll back to the state captured just before the most recent import")

                    Button {
                        BackupService.clearPreImportSnapshot()
                        canRestore = BackupService.hasPreImportSnapshot()
                    } label: {
                        Text("Forget snapshot")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.textTertiary)
                    .pointerCursor()
                    .accessibilityHint("Discard the rollback snapshot from the most recent import")

                    Spacer()
                }
            }

            if let infoMessage {
                Text(infoMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.accent)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.destructive)
            }
        }
        .onAppear {
            canRestore = BackupService.hasPreImportSnapshot()
            hadInterruptedImport = BackupService.hasInterruptedImport()
        }
        .alert("Restore previous data?", isPresented: $showRestoreConfirm) {
            Button("Restore", role: .destructive) {
                let ok = BackupService.restoreLastPreImport()
                if ok {
                    infoMessage = "Restored data from before the most recent import."
                    errorMessage = nil
                    hadInterruptedImport = BackupService.hasInterruptedImport()
                    canRestore = BackupService.hasPreImportSnapshot()
                } else {
                    errorMessage = "No rollback snapshot was available."
                    infoMessage = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces every task, folder, focus-time entry, and preference with the snapshot captured just before your most recent import.")
        }
        .alert("Import will replace all local data", isPresented: $showImportConfirm, presenting: pendingImport) { backup in
            Button("Replace and Import", role: .destructive) {
                BackupService.apply(backup)
                infoMessage = "Imported \(backup.tasks.count) tasks, \(backup.folders.count) folders, and \(backup.focusDailySeconds.count) focus days."
                errorMessage = nil
                pendingImport = nil
                pendingImportFilename = nil
                canRestore = BackupService.hasPreImportSnapshot()
                hadInterruptedImport = BackupService.hasInterruptedImport()
            }
            Button("Cancel", role: .cancel) {
                pendingImport = nil
                pendingImportFilename = nil
            }
        } message: { backup in
            let exported = ISO8601DateFormatter().string(from: backup.exportedAt)
            let source = pendingImportFilename ?? "this file"
            Text("Importing from \(source) (exported \(exported)) will overwrite every task, folder, focus-time entry, and preference currently in Cadence. You'll be able to roll back from the Data section if needed.")
        }
    }

    /// Banner shown when an `apply()` started but never cleared its
    /// in-progress flag — almost certainly because the app crashed or was
    /// killed mid-import. Offers a one-click rollback before any further
    /// mutation can happen.
    private var interruptedImportBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.destructive)
            VStack(alignment: .leading, spacing: 4) {
                Text("Last import didn't finish")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Cadence detected that an import was interrupted. You can restore the snapshot captured just before it started, or dismiss this warning if everything looks correct.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button {
                        showRestoreConfirm = true
                    } label: {
                        Text("Restore previous data")
                    }
                    .buttonStyle(.borderedProminent)
                    .pointerCursor()

                    Button {
                        // Clearing the flag is the only way to dismiss the banner;
                        // the snapshot is kept so the user can still restore later.
                        UserDefaults.standard.removeObject(forKey: BackupService.importInProgressKey)
                        hadInterruptedImport = false
                    } label: {
                        Text("Dismiss")
                    }
                    .buttonStyle(.bordered)
                    .pointerCursor()
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(AppTheme.destructive.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(AppTheme.destructive.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Export + share

    private func exportAndShare(anchor: NSView?) {
        let backup = BackupService.makeBackup()
        let data: Data
        do {
            data = try BackupService.encode(backup)
        } catch {
            errorMessage = "Couldn't build backup: \(error.localizedDescription)"
            infoMessage = nil
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = BackupService.suggestedFilename()
        panel.canCreateDirectories = true
        panel.title = "Export Cadence Backup"
        panel.message = "Save a complete backup of all Cadence data."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = "Couldn't write backup: \(error.localizedDescription)"
            infoMessage = nil
            return
        }

        infoMessage = "Saved \(url.lastPathComponent). Choose a share option, or close the picker if you only wanted the file."
        errorMessage = nil

        let picker = NSSharingServicePicker(items: [url])
        if let view = anchor ?? NSApp.keyWindow?.contentView {
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }

    // MARK: - Import

    private func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import Cadence Backup"
        panel.message = "Pick a .json file previously exported from Cadence."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            errorMessage = "Couldn't read file: \(error.localizedDescription)"
            infoMessage = nil
            return
        }

        let backup: CadenceBackup
        do {
            backup = try BackupService.decode(data)
        } catch {
            errorMessage = "That file doesn't look like a Cadence backup. (\(error.localizedDescription))"
            infoMessage = nil
            return
        }

        if backup.schemaVersion > CadenceBackup.currentSchemaVersion {
            errorMessage = "This backup was made by a newer version of Cadence (schema \(backup.schemaVersion)). Update the app and try again."
            infoMessage = nil
            return
        }

        pendingImport = backup
        pendingImportFilename = url.lastPathComponent
        errorMessage = nil
        showImportConfirm = true
    }
}
