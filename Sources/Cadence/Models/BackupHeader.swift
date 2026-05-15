import Foundation

/// Minimal slice of a backup file used to read the `format` marker and
/// `schemaVersion` without committing to a full payload decode.
///
/// Two-stage decoding (header, then full backup) lets us reject obviously
/// wrong files and gate on schema version before any of the payload-shape
/// requirements kick in. That way a legitimately newer schema reports as
/// "update the app" instead of being mistaken for a malformed file.
struct BackupHeader: Decodable {
    let format: String
    let schemaVersion: Int

    private enum CodingKeys: String, CodingKey {
        case format, schemaVersion
    }
}
