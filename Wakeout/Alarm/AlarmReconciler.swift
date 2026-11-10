import Foundation
import OSLog
import SwiftData

/// SwiftData と AlarmKit の食い違いを直す。
///
/// 起動時とフォアグラウンド復帰時に走らせる。直す食い違いは 4 種類。
///
/// 1. **単発アラームが鳴り終わっている**
///    登録済みだったのに AlarmKit から消えている単発アラームは、鳴り終わったということ。
///    `isEnabled` を落とさないと、一覧とウィジェットが二度と来ない予定を表示し続ける。
/// 2. **有効なのに登録されていない**
///    権限を入れ直した後などに起きる。SwiftData を正として登録し直す。
///    これが無いと「一覧では ON なのに鳴らない」状態になる。
/// 3. **無効なのに登録が残っている**
///    OFF にした直後にアプリが落ちた場合など。取り消す。
/// 4. **アプリが知らない登録が残っている**
///    保存に失敗した・クラッシュした後などに、SwiftData に無い登録が AlarmKit 側だけに残る。
///    一覧に出ないのでユーザーには消す手段が無く、そのまま鳴り続ける。取り消す。
/// 5. **繰り返しアラームが日時指定で登録されたままになっている**
///    ソフト起床で今日のぶんを飛ばすと、次の 1 回だけを `.fixed` で押さえた状態になる。
///    そのままでは翌週以降が入らないので、飛ばした時刻を過ぎたら週の繰り返しへ戻す。
///
/// あわせて、先行アラーム（ソフト起床）の補充もここで行う。
/// 1 回分しか登録しない作りなので、アプリが開かれるたびに次の分を張り直す。
@MainActor
enum AlarmReconciler {

    static func reconcile(context: ModelContext) async {
        // 権限が無い等で現状を取得できないときは何もしない。
        // ここで「登録ゼロ」と誤認すると、有効なアラームを全部 OFF にしてしまう。
        guard let scheduledIDs = AlarmScheduler.scheduledIDs() else { return }

        let descriptor = FetchDescriptor<AlarmEntry>()
        guard let entries = try? context.fetch(descriptor) else { return }

        var didChange = false

        for entry in entries {
            let isScheduled = scheduledIDs.contains(entry.id)

            switch (entry.isEnabled, isScheduled) {
            case (true, false):
                if entry.repeatDays.isEmpty, entry.lastScheduledAt != nil {
                    // 1. 単発が鳴り終わっている
                    entry.isEnabled = false
                    didChange = true
                } else if !entry.repeatDays.isEmpty {
                    // 2. 繰り返しアラームの登録が消えている → 貼り直す
                    try? await AlarmScheduler.schedule(entry)
                    didChange = true
                }
                // 単発で lastScheduledAt が nil のものは「まだ登録していない」だけなので触らない

            case (true, true):
                // 5. 飛ばした回を過ぎたら、週の繰り返しへ戻す
                if await restoreWeeklyIfNeeded(entry) {
                    didChange = true
                }

            case (false, true):
                // 3. 無効なのに登録が残っている
                //
                // ただし鳴っている最中なら触らない。ここで取り消すと
                // ミッションを通さずにアラームが止まってしまう。
                // 鳴り終われば次回の実行で取り消される。
                guard !AlarmScheduler.isRinging(entry.id) else { break }
                AlarmScheduler.cancel(id: entry.id)

            default:
                break
            }
        }

        cancelOrphans(scheduledIDs: scheduledIDs, knownIDs: Set(entries.map(\.id)))

        // 先行アラームの補充。鳴り終わったぶんは消えているので、次の 1 回を張り直す。
        for entry in entries where entry.isEnabled && entry.softWakeEnabled {
            await SoftWake.sync(for: entry)
        }

        if didChange {
            try? context.save()
        }
    }

    /// 繰り返しアラームが `.fixed` で登録されていたら、週の繰り返しへ戻す。
    ///
    /// 戻してよいのは**飛ばした回を過ぎてから**。曜日から求まる次回が、
    /// 押さえてある日時より前にあるなら、それが意図して飛ばした回なので触らない
    /// （ここで戻すと、飛ばしたはずの今日の時刻に鳴ってしまう）。
    private static func restoreWeeklyIfNeeded(_ entry: AlarmEntry) async -> Bool {
        guard !entry.repeatDays.isEmpty else { return false }
        guard case .fixed(let pinned)? = AlarmScheduler.registeredSchedule(of: entry.id) else {
            return false
        }
        // 鳴っている最中に登録し直すと、ミッションを通さずに鳴り止んでしまう。
        guard !AlarmScheduler.isRinging(entry.id) else { return false }
        // ここでは**飛ばした回も含めた**曜日どおりの次回を見る。
        // `entry.nextFireDate()` は飛ばした回を除くので、
        // それで比べると飛ばした直後に週の繰り返しへ戻してしまう（＝今日また鳴る）。
        var unskipped = entry.snapshot
        unskipped.skippedFireDate = nil
        guard let weeklyNext = unskipped.nextFireDate(), weeklyNext >= pinned else { return false }

        logger.notice(
            "日時指定から週の繰り返しへ戻す: id=\(entry.id.uuidString, privacy: .public)"
        )
        try? await AlarmScheduler.schedule(entry)
        return true
    }

    /// アプリが知らない登録を取り消す。
    ///
    /// 触ってはいけないものが 3 つあるので、条件を絞って消す。
    /// - **見張りの再アラーム**は意図的に SwiftData を持たない。消すと逃走防止が無効になる。
    /// - **先行アラーム（ソフト起床）**も SwiftData を持たない。消すとソフト起床が働かない。
    /// - **鳴っている最中のアラーム**は、消すとミッションを通さずに止まってしまう。
    ///
    /// さらに、ミッション待ちの間はこの掃除自体を行わない。
    /// その瞬間だけ現れる登録（予約直後の見張りなど）を巻き込む余地を残さないため。
    private static func cancelOrphans(scheduledIDs: Set<UUID>, knownIDs: Set<UUID>) {
        guard MissionStore.pendingAlarmID == nil else { return }

        let watchdogID = MissionStore.watchdogAlarmID.flatMap(UUID.init(uuidString:))
        let leadIDs = SoftWakeStore.allLeadIDs
        let orphans = scheduledIDs.subtracting(knownIDs)

        for orphan in orphans {
            if orphan == watchdogID { continue }
            if leadIDs.contains(orphan) { continue }
            guard !AlarmScheduler.isRinging(orphan) else { continue }
            logger.notice("アプリが知らない登録を取り消す: id=\(orphan.uuidString, privacy: .public)")
            AlarmScheduler.cancel(id: orphan)
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Wakeout",
        category: "AlarmReconciler"
    )
}
