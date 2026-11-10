import Foundation

/// 起床記録を古い順に 1 件ずつ取り込んで積み上げた状態。
///
/// **最終状態が「今の自己ベスト」、途中の状態が「実績を解除した瞬間」**になる。
/// 記録（`WakeRecords`）と実績（`AchievementCatalog`）で同じ数え方を二度書かないよう、
/// どちらもこの型を通す。
struct WakeProgress {
    /// 通算の起床回数。
    private(set) var total = 0
    /// 突破にかかった最短時間。1 件も無ければ nil。
    private(set) var fastestDuration: TimeInterval?
    /// いちばん早く起きた時刻（0 時からの分）。
    private(set) var earliestMinutes: Int?
    /// 誤答ゼロで突破した回数。
    private(set) var flawlessCount = 0
    /// 突破したミッションの種類（`MissionKind.logIdentifier`）。
    private(set) var kinds: Set<String> = []
    /// これまでで最も長かった連続日数。
    private(set) var longestStreak = 0

    /// 日 → その日で終わる連続日数。
    ///
    /// 古い順に取り込む前提なので、前日の値に 1 を足すだけで連続日数が求まる。
    /// 毎回すべての記録を走査し直す必要がない。
    private var streakByDay: [Date: Int] = [:]

    /// 1 件取り込む。**必ず古い順に呼ぶこと**（連続日数の計算が前日の結果に依存する）。
    mutating func add(_ entry: WakeLogEntry, calendar: Calendar = .current) {
        total += 1

        let minutes = Self.minutesOfDay(entry.stoppedAt, calendar: calendar)
        earliestMinutes = Swift.min(earliestMinutes ?? minutes, minutes)

        // ソフト起床はミッションを解いていない。回数・連続日数・起床時刻には数えるが、
        // 突破の速さ・正確さ・種類には混ぜない。混ぜると「最速 0 秒」「無傷」「全制覇」が
        // 1 度も解かずに成立してしまう。
        if !entry.isSoftWake {
            let duration = max(0, entry.duration)
            fastestDuration = Swift.min(fastestDuration ?? duration, duration)

            if entry.wrongAttempts == 0 { flawlessCount += 1 }
            kinds.insert(entry.missionKind)
        }

        // 1 日に複数回記録があっても、その日の連続日数は 1 度しか伸ばさない。
        let day = calendar.startOfDay(for: entry.stoppedAt)
        if streakByDay[day] == nil {
            let previousDay = calendar.date(byAdding: .day, value: -1, to: day)
            let previous = previousDay.flatMap { streakByDay[$0] } ?? 0
            streakByDay[day] = previous + 1
        }
        longestStreak = Swift.max(longestStreak, streakByDay[day] ?? 1)
    }

    /// 並び順を問わず受け取り、古い順に積み上げた結果を返す。
    static func accumulated(
        _ entries: [WakeLogEntry],
        calendar: Calendar = .current
    ) -> WakeProgress {
        var progress = WakeProgress()
        for entry in entries.sorted(by: { $0.stoppedAt < $1.stoppedAt }) {
            progress.add(entry, calendar: calendar)
        }
        return progress
    }

    private static func minutesOfDay(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

/// 起床記録から引き出す「自己ベスト」。
///
/// `WakeStats` が「ならしてどうなのか」を見るためのものなのに対し、
/// こちらは**更新を狙える一点もの**を扱う。毎朝の同じ作業に目標を作るのが目的。
struct WakeRecords: Equatable {
    let totalCount: Int
    /// 今まさに続いている連続日数。途切れると 0 に戻る。
    let currentStreak: Int
    /// 過去最長の連続日数。途切れても消えない。
    ///
    /// 連続日数だけを見せると、途切れた朝に「積み上げを失った」だけが残る。
    /// 隣に最長を置くことで、ゼロに戻っても手元に残るものが見える。
    let longestStreak: Int
    let fastestDuration: TimeInterval?
    let earliestMinutes: Int?

    static let empty = WakeRecords(
        totalCount: 0,
        currentStreak: 0,
        longestStreak: 0,
        fastestDuration: nil,
        earliestMinutes: nil
    )

    var hasAny: Bool { totalCount > 0 }

    static func make(
        entries: [WakeLogEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WakeRecords {
        let progress = WakeProgress.accumulated(entries, calendar: calendar)
        return WakeRecords(
            totalCount: progress.total,
            currentStreak: entries.currentStreak(calendar: calendar, now: now),
            longestStreak: progress.longestStreak,
            fastestDuration: progress.fastestDuration,
            earliestMinutes: progress.earliestMinutes
        )
    }

    /// 「52秒」「1分5秒」。記録が無ければ「—」。
    static func durationText(_ interval: TimeInterval?) -> String {
        guard let interval else { return "—" }
        let seconds = Swift.max(0, Int(interval.rounded()))
        if seconds < 60 { return "\(seconds)秒" }
        return "\(seconds / 60)分\(seconds % 60)秒"
    }
}
