import Foundation

/// 「起きられない原因の大半は寝るのが遅いこと」に効かせるための就寝リマインダー。
///
/// 次に鳴るアラームの時刻から目標睡眠時間を引いた時刻に、ローカル通知を出す。
/// アラーム本体（AlarmKit）とは無関係の仕組みなので、
/// この通知が出せなくてもアラームの動作には一切影響しない。
///
/// 予約は「作り直し」で管理する。アラームの追加・変更・ON/OFF や設定変更のたびに
/// `sync` を呼べば、古い予約は消えて新しい予約だけが残る。
enum BedtimeReminder {
    /// 予約済み通知の識別子の接頭辞。これで自分の予約だけを見分ける。
    private static let identifierPrefix = "wakeout.bedtime."

    /// 何回分先まで予約しておくか。
    ///
    /// アプリを開かない日が続いても数日は効くように複数持たせる。
    /// iOS の保留通知数の上限（64）に対しては十分小さい。
    private static let maxScheduled = 3

    /// 直前すぎる通知は意味がないので、この時間より先のものだけ予約する。
    private static let minimumLeadTime: TimeInterval = 60

    /// 1 件分の予約内容。
    struct Plan: Equatable {
        /// 通知を出す時刻（＝ 就寝すべき時刻）。
        let remindAt: Date
        /// その通知が対象にしているアラームの発火時刻。
        let fireAt: Date
    }

    // MARK: - 予約

    /// 就寝リマインダーの予約を作り直す。
    ///
    /// - Parameters:
    ///   - snapshots: 現在のアラーム一覧。
    ///   - isEnabled: 設定で有効になっているか。false なら予約を全部消して終わる。
    ///   - sleepHours: 目標睡眠時間。
    static func sync(snapshots: [AlarmSnapshot], isEnabled: Bool, sleepHours: Double) async {
        await cancelAll()

        guard isEnabled else { return }

        let plans = plans(snapshots: snapshots, sleepHours: sleepHours)
        guard !plans.isEmpty else { return }

        // 予約するものが実際にあるときだけ許可を求める
        // （アラームが 1 件も無い状態でいきなり通知の確認が出るのを避ける）。
        guard await NotificationPermission.ensureAuthorized() else { return }

        for (index, plan) in plans.enumerated() {
            await LocalNotificationScheduler.shared.schedule(
                identifier: identifierPrefix + String(index),
                title: "そろそろ寝る時間です",
                body: body(for: plan, sleepHours: sleepHours),
                at: plan.remindAt
            )
        }
    }

    /// 予約済みの就寝リマインダーをすべて取り消す。
    static func cancelAll() async {
        await LocalNotificationScheduler.shared.removePending(withPrefix: identifierPrefix)
    }

    // MARK: - 予定の計算

    /// これから出す就寝リマインダーを早い順に返す。設定画面の予告表示にも使う。
    static func plans(
        snapshots: [AlarmSnapshot],
        sleepHours: Double,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Plan] {
        let sleepInterval = sleepHours * 3600
        let cutoff = now.addingTimeInterval(minimumLeadTime)

        let candidates = snapshots
            .flatMap { $0.upcomingFireDates(limit: maxScheduled, from: now, calendar: calendar) }
            .map { Plan(remindAt: $0.addingTimeInterval(-sleepInterval), fireAt: $0) }
            .filter { $0.remindAt > cutoff }
            .sorted { $0.remindAt < $1.remindAt }

        // 複数のアラームが同じ朝に鳴る（2 段構えなど）場合、
        // 就寝時刻の通知が何度も届いても意味がないので、同じ分のものは 1 件に畳む。
        var seen = Set<Date>()
        var result: [Plan] = []
        for plan in candidates {
            let minute = calendar.date(
                from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.remindAt)
            ) ?? plan.remindAt
            guard seen.insert(minute).inserted else { continue }
            result.append(plan)
            if result.count == maxScheduled { break }
        }
        return result
    }

    // MARK: - 通知の中身

    private static func body(for plan: Plan, sleepHours: Double) -> String {
        "今から寝ないと、\(timeText(plan.fireAt)) のアラームまでに"
            + "\(AppSettings.sleepHoursText(sleepHours))眠れません。"
    }

    private static func timeText(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}
