import Foundation
import SwiftData

/// 登録済みアラーム 1 件。
///
/// - Note: 曜日は仕様上 `Set<Int>` で扱いたいが、SwiftData のストアド属性としては
///   ビットマスク (`repeatDaysMask`) に落としている。Set/Array を直接永続化するより
///   マイグレーション耐性が高く、述語での絞り込みもしやすいため。
///   利用側は `repeatDays: Set<Int>` を通して読み書きするので使い勝手は変わらない。
@Model
final class AlarmEntry {
    /// AlarmKit の `Alarm.ID` としてもそのまま使う。
    var id: UUID = UUID()
    var hour: Int = 7
    var minute: Int = 0
    /// bit 0 = 日曜, bit 1 = 月曜, ... bit 6 = 土曜。0 なら単発アラーム。
    var repeatDaysMask: Int = 0
    var label: String = ""
    var soundName: String = AlarmSound.defaultIdentifier
    var isEnabled: Bool = true
    var createdAt: Date = Date()
    /// 最後に AlarmKit への登録が成功した時刻。一度も登録していなければ nil。
    ///
    /// 「登録したはずなのに AlarmKit 側に無い」＝ 鳴り終わった、と判断するために使う。
    /// これが nil のものは単に未登録なので、鳴り終わったとは見なさない。
    var lastScheduledAt: Date?
    /// スヌーズを許可するか。既定は無効
    /// （元の仕様どおり「スヌーズなし」を基本としつつ、アラームごとに opt-in できるようにしている）。
    var snoozeEnabled: Bool = false
    /// `MissionDifficulty` の rawValue。SwiftData に enum を直接持たせず Int で持つ。
    var missionDifficultyRaw: Int = MissionDifficulty.normal.rawValue
    /// ソフト起床で飛ばした 1 回分の発火時刻。飛ばしていなければ nil。
    ///
    /// 「今日のぶんだけ鳴らさない」を表す唯一の記録。これを見て
    /// 次回発火の計算（＝一覧・ウィジェット・就寝リマインダー）から除く。
    /// 時刻が過ぎれば次回の候補に挙がらなくなるので、消す処理は要らない。
    var skippedFireDate: Date?
    /// ソフト起床（本アラームの前に 1 タップで止まる先行アラームを鳴らす）を使うか。
    /// 既定は無効。鳴る回数が増える仕組みなので、自分で選んでもらう。
    var softWakeEnabled: Bool = false

    init(
        id: UUID = UUID(),
        hour: Int = 7,
        minute: Int = 0,
        repeatDays: Set<Int> = [],
        label: String = "",
        soundName: String = AlarmSound.defaultIdentifier,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        snoozeEnabled: Bool = false,
        missionDifficulty: MissionDifficulty = .normal,
        softWakeEnabled: Bool = false
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.repeatDaysMask = Self.mask(from: repeatDays)
        self.label = label
        self.soundName = soundName
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.snoozeEnabled = snoozeEnabled
        self.missionDifficultyRaw = missionDifficulty.rawValue
        self.softWakeEnabled = softWakeEnabled
    }

    @Transient
    var missionDifficulty: MissionDifficulty {
        get { MissionDifficulty(rawValue: missionDifficultyRaw) ?? .normal }
        set { missionDifficultyRaw = newValue.rawValue }
    }

    /// 0=日, 1=月, ..., 6=土。空セットなら単発。
    @Transient
    var repeatDays: Set<Int> {
        get { Set((0..<7).filter { repeatDaysMask & (1 << $0) != 0 }) }
        set { repeatDaysMask = Self.mask(from: newValue) }
    }

    private static func mask(from days: Set<Int>) -> Int {
        days.filter { (0..<7).contains($0) }.reduce(0) { $0 | (1 << $1) }
    }
}

// MARK: - 表示用ヘルパー

extension AlarmEntry {
    var timeText: String { snapshot.timeText }

    /// 「毎日」「平日」「月・水・金」「1回のみ」といった曜日表記。
    var repeatText: String { snapshot.repeatText }

    static let weekdaySymbols = AlarmSnapshot.weekdaySymbols

    /// ウィジェットと共有するための表現。
    /// 表示ロジック（曜日表記・次回発火時刻）はここに集約し、二重実装を避ける。
    var snapshot: AlarmSnapshot {
        AlarmSnapshot(
            id: id,
            hour: hour,
            minute: minute,
            repeatDaysMask: repeatDaysMask,
            label: label,
            isEnabled: isEnabled,
            skippedFireDate: skippedFireDate
        )
    }

    /// 次にこのアラームが鳴る日時。無効なら nil。
    func nextFireDate(from now: Date = Date(), calendar: Calendar = .current) -> Date? {
        snapshot.nextFireDate(from: now, calendar: calendar)
    }

    /// 「あと 7時間30分」のような表示。
    static func countdownText(to date: Date, from now: Date = Date()) -> String {
        let interval = max(0, Int(date.timeIntervalSince(now)))
        let hours = interval / 3600
        let minutes = (interval % 3600) / 60
        if hours == 0 { return "あと \(minutes)分" }
        return "あと \(hours)時間\(minutes)分"
    }
}
