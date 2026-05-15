import Foundation

/// Errors thrown by `BackupService.decode`. Each case carries enough context
/// to render a clear, user-facing message in the Settings UI.
enum BackupError: LocalizedError {
    /// The file's `format` field is missing or doesn't match
    /// `CadenceBackup.formatIdentifier`.
    case notACadenceBackup(format: String)

    /// The file's `schemaVersion` is greater than the current build supports.
    case unsupportedSchema(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case .notACadenceBackup(let format):
            return "Not a Cadence backup (format = \"\(format)\")."
        case .unsupportedSchema(let found, let supported):
            return "This backup uses schema \(found), but this version of Cadence only understands up to schema \(supported). Update the app and try again."
        }
    }
}
