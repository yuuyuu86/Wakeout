import Foundation
import SwiftData

/// ミッションをクリアしてアラームを止めた 1 回分の記録。
///
/// 「いつ鳴って、いつ止められたか」「何回失敗したか」を残す。
/// アラームが削除されても記録自体は残す（過去の起床実績を消す理由がないため）、
/// そのため `alarmID` は参照ではなく値として持ち、表示用のラベルも複製して保存する。
@Model
final class WakeLogEntry {
    var id: UUID = UUID()
    var alarmID: UUID = UUID()
    /// 記録時点でのアラームのラベル。アラームが後で削除・改名されても記録は変わらない。
    var alarmLabel: String = ""
    /// ミッション画面が表示された時刻（≒ 鳴り始めた時刻）。
    var firedAt: Date = Date()
    /// ミッションをクリアして実際に停止した時刻。
    var stoppedAt: Date = Date()
    /// `MissionKind.logIdentifier`（"calculation" / "shake" / "memory" / "typing" / "walk"）。
    /// 連続出題のときは**最後に解いた 1 問**の種類。
    var missionKind: String = ""
    /// 誤答回数。シェイク・歩くのように答えの無いミッションでは常に 0。
    var wrongAttempts: Int = 0
    /// ソフト起床（先行アラームで目が覚め、本アラームを飛ばした）による記録か。
    ///
    /// ミッションを解いていないので `duration` は 0 になる。
    /// 速さ・正確さ・ミッション種類の記録に混ぜると、
    /// 「最速 0 秒」「無傷」「全制覇」が解かずに成立してしまうため、
    /// 集計側（`WakeProgress`）でこのフラグを見て弾いている。
    var isSoftWake: Bool = false

    init(
        alarmID: UUID,
        alarmLabel: String,
        firedAt: Date,
        stoppedAt: Date,
        missionKind: String,
        wrongAttempts: Int,
        isSoftWake: Bool = false
    ) {
        self.alarmID = alarmID
        self.alarmLabel = alarmLabel
        self.firedAt = firedAt
        self.stoppedAt = stoppedAt
        self.missionKind = missionKind
        self.wrongAttempts = wrongAttempts
        self.isSoftWake = isSoftWake
    }

    /// ソフト起床の記録に入れる `missionKind`。
    /// `MissionKind.logIdentifier` のどれとも重ならない値にしてある。
    static let softWakeKind = "softwake"

    /// 鳴ってから止めるまでにかかった時間。
    var duration: TimeInterval { stoppedAt.timeIntervalSince(firedAt) }
}

extension Array where Element == WakeLogEntry {
    /// 直近から連続して記録がある日数。
    ///
    /// 「今日または昨日」に記録が無ければ 0（今日はまだ寝ていない可能性があるので、
    /// 昨日まで繋がっていれば連続日数としてカウントする）。
    func currentStreak(calendar: Calendar = .current, now: Date = Date()) -> Int {
        let days = Set(map { calendar.startOfDay(for: $0.stoppedAt) })
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            // 今日はまだ無くても、昨日から繋がっていれば連続とみなす
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}
