import Foundation

/// ウィジェットに渡すアラーム 1 件の情報。
///
/// Widget Extension から SwiftData のストアを直接読むとスキーマを二重管理することになるため、
/// 表示に必要な最小限だけを App Group の UserDefaults に JSON で書き出して共有する。
///
/// 「次に鳴る時刻」はウィジェット側のタイムライン更新時に計算し直す必要があるので、
/// 計算済みの日時ではなく時刻と曜日そのものを持たせている。
struct AlarmSnapshot: Codable, Hashable, Sendable {
    var id: UUID
    var hour: Int
    var minute: Int
    /// bit 0 = 日曜, ... bit 6 = 土曜。0 なら単発。
    var repeatDaysMask: Int
    var label: String
    var isEnabled: Bool
    /// ソフト起床で飛ばした 1 回分の発火時刻。飛ばしていなければ nil。
    ///
    /// これを持たせないと、飛ばした直後の画面とウィジェットが
    /// 「もう鳴らない時刻」を次の予定として出し続けることになる。
    var skippedFireDate: Date?

    var repeatDays: Set<Int> {
        Set((0..<7).filter { repeatDaysMask & (1 << $0) != 0 })
    }

    var timeText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// 「毎日」「平日」「月・水・金」「1回のみ」といった曜日表記。
    var repeatText: String {
        let days = repeatDays
        if days.isEmpty { return "1回のみ" }
        if days == Set(0..<7) { return "毎日" }
        if days == Set(1...5) { return "平日" }
        if days == Set([0, 6]) { return "週末" }
        return days.sorted().map { AlarmSnapshot.weekdaySymbols[$0] }.joined(separator: "・")
    }

    static let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    /// 次にこのアラームが鳴る日時。無効なら nil。
    func nextFireDate(from now: Date = Date(), calendar: Calendar = .current) -> Date? {
        upcomingFireDates(limit: 1, from: now, calendar: calendar).first
    }

    /// これから鳴る日時を古い順に最大 `limit` 件。無効なら空。
    ///
    /// 就寝リマインダーのように「今夜だけでなく数日先まで」予約したい用途で使う。
    /// 0=日曜 に対して `Calendar` の weekday は 1=日曜 なので 1 ずらして比較する。
    func upcomingFireDates(
        limit: Int,
        from now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Date] {
        guard isEnabled, limit > 0 else { return [] }

        let days = repeatDays
        var result: [Date] = []
        // 今日から 8 日先まで見れば、単発・毎週どちらも必ず 1 巡する。
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let candidate = calendar.date(
                    bySettingHour: hour, minute: minute, second: 0, of: day
                  ) else { continue }

            guard candidate > now else { continue }

            // ソフト起床で飛ばした回は、予定として数えない。
            // 1 分の幅を見ているのは、同じ時刻でも秒以下やタイムゾーンの扱いで
            // 完全一致にならない場合があるため。
            if let skipped = skippedFireDate,
               abs(candidate.timeIntervalSince(skipped)) < 60 {
                continue
            }

            if days.isEmpty {
                // 単発は 1 回しか鳴らない。
                return [candidate]
            }

            let weekdayIndex = calendar.component(.weekday, from: candidate) - 1
            if days.contains(weekdayIndex) {
                result.append(candidate)
                if result.count == limit { return result }
            }
        }
        return result
    }
}

extension Array where Element == AlarmSnapshot {
    /// 一覧のうち最も早く鳴るもの。
    func nextToFire(from now: Date = Date()) -> (alarm: AlarmSnapshot, date: Date)? {
        compactMap { alarm in
            alarm.nextFireDate(from: now).map { (alarm, $0) }
        }
        .min { $0.1 < $1.1 }
    }
}
