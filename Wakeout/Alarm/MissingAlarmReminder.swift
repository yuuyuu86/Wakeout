import Foundation

/// 「明日の朝に鳴るアラームがありません」と夜のうちに知らせる。
///
/// 寝坊の原因で一番多いのは、そもそもアラームをかけ忘れていること。
/// 起きられなかった後では手遅れなので、**まだ間に合う夜のうちに**気付かせる。
///
/// 判定はアラームの一覧が変わるたび・アプリを開くたびにやり直す。
/// 夜までにアラームを入れれば予約は取り消される。
enum MissingAlarmReminder {
    private static let identifier = "wakeout.missing-alarm"

    /// 知らせる時刻（この時刻に通知する）。
    ///
    /// 遅すぎると寝る直前で慌てるし、早すぎると「これから入れるところだ」になる。
    static let checkHour = 21

    /// 「明日の朝」とみなす範囲。判定時刻から何時間先までを見るか。
    ///
    /// 21 時から 15 時間 ＝ 翌日の正午まで。
    /// 昼まで見るのは、遅番・夜勤で朝が遅い人のアラームを「無い」と誤判定しないため。
    private static let morningWindow: TimeInterval = 15 * 3600

    /// 予約を作り直す。
    static func sync(snapshots: [AlarmSnapshot], isEnabled: Bool) async {
        await LocalNotificationScheduler.shared.removePending(identifiers: [identifier])

        guard isEnabled, let checkDate = nextCheckDate() else { return }
        guard !hasAlarm(after: checkDate, within: morningWindow, snapshots: snapshots) else { return }
        guard await NotificationPermission.ensureAuthorized() else { return }

        await LocalNotificationScheduler.shared.schedule(
            identifier: identifier,
            title: "明日のアラームがありません",
            body: "このままでは朝に鳴りません。今のうちに設定してください。",
            at: checkDate
        )
    }

    /// 次に判定する日時。今日の該当時刻を過ぎていれば明日。
    static func nextCheckDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let today = calendar.date(
            bySettingHour: checkHour, minute: 0, second: 0, of: now
        ) else { return nil }

        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today)
    }

    /// その時刻から一定時間内に鳴るアラームがあるか。
    static func hasAlarm(
        after date: Date,
        within interval: TimeInterval,
        snapshots: [AlarmSnapshot],
        calendar: Calendar = .current
    ) -> Bool {
        let deadline = date.addingTimeInterval(interval)
        return snapshots.contains { snapshot in
            snapshot
                .upcomingFireDates(limit: 3, from: date, calendar: calendar)
                .contains { $0 <= deadline }
        }
    }
}
