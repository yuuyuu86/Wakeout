import Foundation
import Observation

/// アプリ全体の設定。アラーム 1 件ごとの設定（スヌーズ・難易度）は `AlarmEntry` 側に持たせ、
/// ここには「アプリの振る舞い」だけを置く。
///
/// SwiftData ではなく UserDefaults に置いているのは、
/// 単純なスカラー値の集まりで、マイグレーションを伴う構造を持たないため。
/// 将来ウィジェットからも参照できるよう App Group の suite に書いている。
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    /// 目標睡眠時間の選択肢（時間）。
    static let sleepHourOptions: [Double] = [5, 5.5, 6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10]

    private enum Key {
        static let bedtimeReminder = "settings_bedtime_reminder_enabled"
        static let sleepHours = "settings_sleep_hours"
        static let batteryWarning = "settings_battery_warning_enabled"
        static let missingAlarmWarning = "settings_missing_alarm_warning_enabled"
        static let missionBrightness = "settings_mission_brightness_enabled"
    }

    /// 就寝リマインダーを出すか。
    /// 通知の許可を求めることになるので、既定は OFF（ユーザーが自分で有効にする）。
    var isBedtimeReminderEnabled: Bool {
        didSet { defaults.set(isBedtimeReminderEnabled, forKey: Key.bedtimeReminder) }
    }

    /// 目標睡眠時間。「次のアラームのこの時間前」に就寝リマインダーを出す。
    var sleepHours: Double {
        didSet { defaults.set(sleepHours, forKey: Key.sleepHours) }
    }

    /// バッテリー残量の警告を出すか。既定は ON（鳴らない事故を防ぐ側に倒す）。
    var isBatteryWarningEnabled: Bool {
        didSet { defaults.set(isBatteryWarningEnabled, forKey: Key.batteryWarning) }
    }

    /// 明日のアラームが無いときに知らせるか。既定は ON（かけ忘れは寝坊原因の筆頭）。
    var isMissingAlarmWarningEnabled: Bool {
        didSet { defaults.set(isMissingAlarmWarningEnabled, forKey: Key.missingAlarmWarning) }
    }

    /// ミッション中に画面を最大の明るさにするか。既定は ON。
    var isMissionBrightnessEnabled: Bool {
        didSet { defaults.set(isMissionBrightnessEnabled, forKey: Key.missionBrightness) }
    }

    private let defaults = WakeoutShared.defaults

    private init() {
        let defaults = WakeoutShared.defaults
        isBedtimeReminderEnabled = defaults.bool(forKey: Key.bedtimeReminder)
        // 未設定と「0 時間」を区別するため object で取り出す。
        let storedHours = defaults.object(forKey: Key.sleepHours) as? Double
        sleepHours = storedHours ?? 8
        isBatteryWarningEnabled = defaults.object(forKey: Key.batteryWarning) as? Bool ?? true
        isMissingAlarmWarningEnabled =
            defaults.object(forKey: Key.missingAlarmWarning) as? Bool ?? true
        isMissionBrightnessEnabled =
            defaults.object(forKey: Key.missionBrightness) as? Bool ?? true
    }

    /// 「8時間」「7時間30分」のような表記。
    /// 通知本文の組み立て（MainActor 外）からも使うので nonisolated にしている。
    nonisolated static func sleepHoursText(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)時間" : "\(h)時間\(m)分"
    }
}
