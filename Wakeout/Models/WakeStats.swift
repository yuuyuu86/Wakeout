import Foundation

/// 起床記録の集計。表示から切り離して純粋な計算にしてある。
///
/// 1 日に複数回記録がある場合（スヌーズ後にもう一度鳴った、など）は
/// **その日の最初の記録**を「その日の起床」として扱う。
struct WakeStats {
    /// グラフの 1 日分。
    struct DayPoint: Identifiable {
        let date: Date
        /// 起床時刻を「0 時からの分」で表したもの。記録が無ければ nil。
        let minutes: Int?

        var id: Date { date }
    }

    /// 平均などの集計に使った日数。
    let sampleCount: Int
    /// 平均起床時刻（0 時からの分）。記録が無ければ nil。
    let averageMinutes: Int?
    /// 集計期間で最も早かった／遅かった起床時刻。
    let earliestMinutes: Int?
    let latestMinutes: Int?
    /// 1 回あたりの平均誤答数。
    let averageWrongAttempts: Double
    /// 直近 7 日分（古い順）。
    let days: [DayPoint]
    /// グラフの左端・右端（0 時からの分）。
    let windowStart: Int
    let windowEnd: Int

    /// 集計期間（日数）。
    static let windowDays = 30
    /// グラフに並べる日数。
    static let chartDays = 7

    // MARK: - 集計

    static func make(
        entries: [WakeLogEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WakeStats {
        let today = calendar.startOfDay(for: now)
        let periodStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today) ?? today

        // 日 → その日の最初の起床時刻（分）
        var firstWake: [Date: Int] = [:]
        var wrongAttempts: [Int] = []

        for entry in entries where entry.stoppedAt >= periodStart {
            let day = calendar.startOfDay(for: entry.stoppedAt)
            let minutes = minutesOfDay(entry.stoppedAt, calendar: calendar)
            if let existing = firstWake[day] {
                firstWake[day] = min(existing, minutes)
            } else {
                firstWake[day] = minutes
            }
            // ミッションを解いていないソフト起床は「平均誤答数」の母数に入れない。
            if !entry.isSoftWake {
                wrongAttempts.append(entry.wrongAttempts)
            }
        }

        let samples = Array(firstWake.values)
        let average = circularMeanMinutes(samples)

        // グラフは直近 chartDays 日を古い順に並べる（記録が無い日も欠けさせない）。
        let days: [DayPoint] = (0..<chartDays).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayPoint(date: date, minutes: firstWake[date])
        }

        // グラフの横軸は、表示する 7 日と平均が必ず収まる範囲にする。
        let plotted = days.compactMap(\.minutes) + [average].compactMap { $0 }
        let low = plotted.min() ?? 6 * 60
        let high = plotted.max() ?? 8 * 60
        // 幅が狭すぎると 1 分の差が画面端まで動いてしまうので、最低 2 時間の幅を持たせる。
        let padding = max(30, (120 - (high - low)) / 2)
        let windowStart = max(0, low - padding)
        let windowEnd = min(24 * 60, high + padding)

        return WakeStats(
            sampleCount: samples.count,
            averageMinutes: average,
            earliestMinutes: samples.min(),
            latestMinutes: samples.max(),
            averageWrongAttempts: wrongAttempts.isEmpty
                ? 0
                : Double(wrongAttempts.reduce(0, +)) / Double(wrongAttempts.count),
            days: days,
            windowStart: windowStart,
            windowEnd: max(windowStart + 60, windowEnd)
        )
    }

    // MARK: - 表示ヘルパー

    /// 「07:12」形式。
    static func timeText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    /// グラフ上での横位置（0.0〜1.0）。範囲外なら nil。
    func position(of minutes: Int) -> Double? {
        let span = Double(windowEnd - windowStart)
        guard span > 0 else { return nil }
        let ratio = Double(minutes - windowStart) / span
        guard (0...1).contains(ratio) else { return nil }
        return ratio
    }

    // MARK: - 計算

    private static func minutesOfDay(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// 時刻の平均。
    ///
    /// 単純な相加平均だと 23:50 と 00:10 の平均が 12:00 になってしまう。
    /// 1 日を円周とみなし、単位ベクトルの平均から角度を戻す（円周平均）ことで
    /// 日付をまたぐ起床時刻でも破綻しないようにしている。
    private static func circularMeanMinutes(_ samples: [Int]) -> Int? {
        guard !samples.isEmpty else { return nil }

        var sumSin = 0.0
        var sumCos = 0.0
        for minutes in samples {
            let angle = Double(minutes) / (24 * 60) * 2 * .pi
            sumSin += sin(angle)
            sumCos += cos(angle)
        }

        // ちょうど正反対の時刻が揃うと平均ベクトルが 0 になり、向きが定まらない。
        let magnitude = (sumSin * sumSin + sumCos * sumCos).squareRoot() / Double(samples.count)
        guard magnitude > 0.000_1 else { return nil }

        var angle = atan2(sumSin, sumCos)
        if angle < 0 { angle += 2 * .pi }
        let minutes = Int((angle / (2 * .pi) * 24 * 60).rounded())
        return minutes % (24 * 60)
    }
}
