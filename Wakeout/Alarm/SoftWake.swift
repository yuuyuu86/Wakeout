import AlarmKit
import Foundation
import OSLog
import SwiftData
import SwiftUI

/// ソフト起床。本アラームの前に、**1 タップで止まる**先行アラームを鳴らす。
///
/// 深い睡眠から叩き起こされるのが苦痛の最大の原因だが、
/// 睡眠段階をその場で判定する手段は（Apple Watch 無しでは）無い。
/// そこで**ユーザーの反応そのものをセンサーにする**。
///
/// - 先行アラームに反応できた = 眠りが浅かった → そのまま起きてもらう
/// - 反応できなかった = 深く眠っている → 本アラームが従来どおり容赦なく鳴る
///
/// つまり**取りこぼしても安全側に倒れる**のが、この仕組みの要点。
/// 先行アラームの登録に失敗しても、ミッション付きの本アラームは何も変わらない。
///
/// - Important: 先行アラームを止めても本アラームは**止まらない**。
///   寝ぼけたまま停止ボタンを押せてしまうと、そのまま寝坊するため。
///   本アラームを飛ばすには、アプリ内の長押し確定（`confirmWakeUp`）を通す。
@MainActor
enum SoftWake {

    enum Refusal: LocalizedError {
        case alreadyRinging
        case noUpcomingFire

        var errorDescription: String? {
            switch self {
            case .alreadyRinging:
                "本アラームがもう鳴っています。ミッションをクリアして停止してください。"
            case .noUpcomingFire:
                "このアラームには次に鳴る予定がありません。"
            }
        }
    }

    /// 本アラームの何秒前に先行アラームを鳴らすか。
    ///
    /// 2 段構えにしてあるのは、1 回の呼びかけで浅い睡眠に当たる確率が低いため。
    /// 増やすほど当たりやすくなるが、無視され続けると「鳴っても止まらない音」に
    /// 慣れてしまうので、本アラームまでの 20 分に 2 回までとしている。
    static let leadOffsets: [TimeInterval] = [20 * 60, 10 * 60]

    /// 最初の先行アラームが鳴ってから本アラームまでの長さ（＝ソフト起床の窓）。
    static var windowLength: TimeInterval { leadOffsets.max() ?? 0 }

    /// これより近い先行アラームは登録しない。
    /// 「登録した次の瞬間に鳴る」ものは、ユーザーには事故に見える。
    private static let minimumLeadTime: TimeInterval = 60

    // MARK: - 先行アラームの登録

    /// `entry` の先行アラームを登録し直す。
    ///
    /// 予約は常に**作り直し**で管理する。古い登録を先に全部消すので、
    /// 時刻を変えても曜日を変えても、呼べば必ず現在の設定どおりになる。
    ///
    /// 登録するのは**次の 1 回分だけ**。AlarmKit には登録数の上限があり、
    /// アラーム 1 件あたり何件も抱えると本アラームの登録を押し出しかねない。
    /// アプリを開くたびに補充する（`AlarmReconciler`）。
    /// 何日も開かなければ先行アラームは尽きるが、本アラームは鳴り続ける。
    static func sync(for entry: AlarmEntry) async {
        cancelAll(forAlarmID: entry.id)

        guard entry.isEnabled, entry.softWakeEnabled else { return }
        guard AlarmScheduler.authorizationState == .authorized else { return }
        guard let fireDate = entry.nextFireDate() else { return }

        // 鳴っている最中の先行アラームは取り消されずに残っている。
        // ストアから落とすと、それが「先行アラーム」だと分からなくなり、
        // 鳴っている間だけミッション画面が出てしまう。
        var registered = SoftWakeStore.leadIDs(forAlarmID: entry.id.uuidString)

        // 登録に渡す値は、ここで SwiftData のモデルから取り出しておく。
        // 組み立てを nonisolated にしておかないと、
        // AlarmKit の設定値（Sendable ではない）をメインアクタ外へ渡せない。
        let label = entry.label
        let soundName = entry.soundName

        for offset in leadOffsets.sorted(by: >) {
            let date = fireDate.addingTimeInterval(-offset)
            guard date.timeIntervalSinceNow > minimumLeadTime else { continue }

            let id = UUID()
            do {
                _ = try await AlarmManager.shared.schedule(
                    id: id,
                    configuration: configuration(
                        label: label,
                        soundName: soundName,
                        at: date,
                        offset: offset
                    )
                )
                registered.append(id)
            } catch {
                // 先行アラームは「あれば良いもの」。ここで失敗しても本アラームには触らない。
                let nsError = error as NSError
                logger.error(
                    """
                    先行アラームを登録できなかった: \
                    alarm=\(entry.id.uuidString, privacy: .public) \
                    offset=\(Int(offset / 60))分 \
                    domain=\(nsError.domain, privacy: .public) code=\(nsError.code)
                    """
                )
            }
        }

        SoftWakeStore.setLeadIDs(registered, forAlarmID: entry.id.uuidString)
    }

    /// そのアラームの先行アラームをすべて取り消す。
    ///
    /// `AlarmScheduler.cancel(id:)` からも呼ぶので nonisolated にしてある
    /// （触るのは AlarmKit と App Group の UserDefaults だけで、アプリの状態には触らない）。
    nonisolated static func cancelAll(forAlarmID alarmID: UUID) {
        var retained: [UUID] = []
        for id in SoftWakeStore.leadIDs(forAlarmID: alarmID.uuidString) {
            // 鳴っている最中のものは止めない。音だけ消えて画面が残るより、
            // ユーザーが停止ボタンを押して終わらせるほうが分かりやすい。
            // 鳴り終わるまでは**先行アラームだと分かるようストアに残す**。
            if AlarmScheduler.isRinging(id) {
                retained.append(id)
                continue
            }
            try? AlarmManager.shared.cancel(id: id)
        }
        SoftWakeStore.setLeadIDs(retained, forAlarmID: alarmID.uuidString)
    }

    /// 先行アラームかどうか。ミッション画面を出す判断と整合処理で使う。
    nonisolated static func isLead(_ id: UUID) -> Bool { SoftWakeStore.isLead(id) }

    nonisolated private static func configuration(
        label: String,
        soundName: String,
        at date: Date,
        offset: TimeInterval
    ) -> AlarmManager.AlarmConfiguration<WakeoutAlarmMetadata> {
        let minutes = Int(offset / 60)
        let text = label.isEmpty
            ? "あと\(minutes)分で本番"
            : "\(label) まであと\(minutes)分"
        let title = LocalizedStringResource(stringLiteral: text)

        // 本番と見分けがつくよう差し色を変える。黄色（acid）は本アラーム専用にしておく。
        let attributes = AlarmAttributes<WakeoutAlarmMetadata>(
            presentation: presentation(title: title),
            metadata: WakeoutAlarmMetadata(label: label),
            tintColor: Theme.dawn
        )

        return AlarmManager.AlarmConfiguration(
            // スヌーズは持たせない。二度寝の口実を増やすためのものではない。
            countdownDuration: nil,
            // 次の 1 回だけなので、曜日の繰り返しではなく日時で指定する。
            schedule: .fixed(date),
            attributes: attributes,
            // stopIntent を**渡さない**のがソフト起床の本質。
            // ミッションを通さず、システムの停止ボタン 1 回で鳴り止む。
            stopIntent: nil,
            sound: AlarmSound.alertSound(for: soundName)
        )
    }

    nonisolated private static func presentation(
        title: LocalizedStringResource
    ) -> AlarmPresentation {
        // iOS 26.1 以降、停止ボタンの見た目はシステムが描画し `stopButton` は無視される。
        // 26.0 でだけラベルを指定したいので分岐している（`AlarmScheduler` と同じ事情）。
        if #available(iOS 26.1, *) {
            return AlarmPresentation(alert: AlarmPresentation.Alert(title: title))
        } else {
            return AlarmPresentation(
                alert: AlarmPresentation.Alert(
                    title: title,
                    stopButton: AlarmButton(
                        text: "起きた",
                        textColor: .white,
                        systemImageName: "sun.horizon"
                    )
                )
            )
        }
    }

    // MARK: - ソフト起床の窓

    /// いまが「先行アラームが鳴ってから本アラームまで」の間なら、その本アラームの時刻を返す。
    ///
    /// 窓の判定は時刻の計算だけで済ませている。
    /// 「先行アラームが鳴ったか」を保存して判断すると、保存漏れのぶんだけ
    /// 起床確定ボタンが出なくなる（＝止める手段が無いまま本アラームを待つ）。
    static func fireDateIfInWindow(for entry: AlarmEntry, now: Date = Date()) -> Date? {
        guard entry.isEnabled, entry.softWakeEnabled else { return nil }
        guard let fireDate = entry.nextFireDate(from: now) else { return nil }
        guard fireDate.timeIntervalSince(now) <= windowLength else { return nil }
        return fireDate
    }

    // MARK: - 起床確定

    /// 「もう起きた」確定。今日の本アラームを飛ばす。
    ///
    /// 繰り返しアラームでは**今日のぶんだけ**を飛ばす。曜日の繰り返しのまま登録し直すと
    /// 今日の分が復活してしまうので、次の 1 回を日時指定（`.fixed`）で押さえ直す。
    /// 週の繰り返しへは `AlarmReconciler` が今日の時刻を過ぎてから戻す。
    ///
    /// - Returns: 起床ログに残す 1 件。`context` が無ければ nil。
    @discardableResult
    static func confirmWakeUp(_ entry: AlarmEntry, context: ModelContext?) async throws -> WakeLogEntry? {
        // 本アラームが鳴っている最中にこれを通してはいけない。
        // 通せば「長押しでミッションを回避できる」抜け穴になる。
        guard !AlarmScheduler.isRinging(entry.id) else { throw Refusal.alreadyRinging }

        let upcoming = entry.snapshot.upcomingFireDates(limit: 2)
        guard let skipped = upcoming.first else { throw Refusal.noUpcomingFire }

        cancelAll(forAlarmID: entry.id)

        // 飛ばした回は記録しておく。これが無いと一覧・ウィジェット・就寝リマインダーが
        // 「もう鳴らない時刻」を次の予定として出し続ける。
        entry.skippedFireDate = skipped

        if entry.repeatDays.isEmpty {
            // 単発は鳴り終わったのと同じ状態にする（一覧とウィジェットから消える）。
            AlarmScheduler.cancel(id: entry.id)
            entry.isEnabled = false
        } else if let next = upcoming.dropFirst().first {
            AlarmScheduler.cancel(id: entry.id)
            try await AlarmScheduler.schedule(entry, overridingSchedule: .fixed(next))
        } else {
            // 次の 1 回が求まらないのは曜日の計算が壊れているとき。
            // 取り消しだけして登録し直さないと**二度と鳴らなくなる**ので、触らない。
            throw Refusal.noUpcomingFire
        }

        logger.notice(
            """
            ソフト起床で本アラームを飛ばした: \
            alarm=\(entry.id.uuidString, privacy: .public) \
            skipped=\(skipped.description, privacy: .public)
            """
        )

        return log(entry: entry, context: context)
    }

    /// ソフト起床を 1 件記録する。
    ///
    /// ミッションを解いていないので、**速さや正確さの記録には混ぜない**
    /// （`WakeProgress` 側で弾いている）。連続日数だけは伸ばす。
    /// 穏やかに起きた日が「起きていない日」になると、優しい経路を選ぶほど損になる。
    private static func log(entry: AlarmEntry, context: ModelContext?) -> WakeLogEntry? {
        guard let context else { return nil }
        let now = Date()
        let log = WakeLogEntry(
            alarmID: entry.id,
            alarmLabel: entry.label,
            firedAt: now,
            stoppedAt: now,
            missionKind: WakeLogEntry.softWakeKind,
            wrongAttempts: 0,
            isSoftWake: true
        )
        context.insert(log)
        try? context.save()
        return log
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Wakeout",
        category: "SoftWake"
    )
}
