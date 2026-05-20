import Foundation

/// Snapshot of every user preference managed by `AppSettings`.
/// String/Int raw values are stored so the file remains human-readable and
/// resilient if enum cases are renamed at the Swift level.
struct BackupSettings: Codable, Equatable {
    var weekStartsOn: Int
    var timerFinishSound: String
    var timerStyle: String
    var timerDirection: String
    var animateDockIcon: Bool
    var iCloudSyncEnabled: Bool

    init(
        weekStartsOn: Int = Weekday.monday.rawValue,
        timerFinishSound: String = TimerFinishSound.standard.rawValue,
        timerStyle: String = TimerStyle.glassy.rawValue,
        timerDirection: String = TimerDirection.original.rawValue,
        animateDockIcon: Bool = true,
        iCloudSyncEnabled: Bool = false
    ) {
        self.weekStartsOn = weekStartsOn
        self.timerFinishSound = timerFinishSound
        self.timerStyle = timerStyle
        self.timerDirection = timerDirection
        self.animateDockIcon = animateDockIcon
        self.iCloudSyncEnabled = iCloudSyncEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case weekStartsOn, timerFinishSound, timerStyle, timerDirection, animateDockIcon, iCloudSyncEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weekStartsOn = try c.decodeIfPresent(Int.self, forKey: .weekStartsOn) ?? Weekday.monday.rawValue
        timerFinishSound = try c.decodeIfPresent(String.self, forKey: .timerFinishSound) ?? TimerFinishSound.standard.rawValue
        timerStyle = try c.decodeIfPresent(String.self, forKey: .timerStyle) ?? TimerStyle.glassy.rawValue
        timerDirection = try c.decodeIfPresent(String.self, forKey: .timerDirection) ?? TimerDirection.original.rawValue
        animateDockIcon = try c.decodeIfPresent(Bool.self, forKey: .animateDockIcon) ?? true
        // decodeIfPresent so backups exported from older builds (which
        // didn't have this field) decode cleanly with the default off.
        iCloudSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .iCloudSyncEnabled) ?? false
    }
}
