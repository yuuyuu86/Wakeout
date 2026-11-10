import AlarmKit
import Foundation
import Observation
import SwiftData

/// 表示中のミッション。`fullScreenCover(item:)` に渡すため Identifiable。
struct PendingMission: Identifiable, Equatable {
    /// アラームの UUID 文字列。
    let id: String

    var alarmUUID: UUID? { UUID(uuidString: id) }
}

/// 「ミッションをクリアするまでアラームを止めさせない」状態機械。
///
/// ミッション画面を出すトリガーは 2 系統あり、どちらでも復帰できるようにしている:
/// 1. `MissionGatedStopIntent` が App Group に書いた「ミッション待ち」フラグ
/// 2. `AlarmManager.alarmUpdates` で観測した `.alerting` 状態のアラーム
///
/// 2 があるおかげで、アプリを強制終了して再起動した場合でもミッション画面へ戻される。
@MainActor
@Observable
final class MissionCoordinator {
    /// 非 nil の間、アプリはミッション画面に固定される。
    private(set) var pending: PendingMission?

    /// 停止処理に失敗したときのメッセージ（画面に出して再挑戦させる）。
    private(set) var errorMessage: String?

    /// 突破直後に見せる結果。閉じるまで全画面を占有し続ける。
    ///
    /// `pending` と入れ替わりに立てる。全画面を一度閉じてから開き直すと
    /// 画面が黒く落ちるので、**同じ全画面の中身だけを差し替える**（`RootView` 参照）。
    private(set) var celebration: WakeCelebration?

    /// ミッション画面か祝いの画面を出すべきか。
    var isPresentingFullScreen: Bool { pending != nil || celebration != nil }

    /// 今のミッションが表示され始めた時刻。起床記録の「鳴った時刻」に使う。
    private(set) var pendingSince: Date?

    /// 起床記録の書き込み先。RootView から一度だけ渡してもらう。
    var modelContext: ModelContext?

    // MARK: - 監視

    /// scenePhase が active になったとき / 起動時に呼ぶ。
    func refresh() {
        if let alerting = currentlyAlertingAlarmID() {
            present(alarmID: missionTarget(forAlerting: alerting))
            return
        }
        if let stored = MissionStore.pendingAlarmID {
            // AlarmKit に登録すら無い ID のフラグが残っていることがある
            // （アラート放置でタイムアウトした、アラームを消した、など）。
            // これで画面を出すと、クリアしても止める相手が居らず詰まるので捨てる。
            //
            // ただし見張りを張ってある間は捨てない。
            // 停止ボタンを押した後、対象が単発アラームだと AlarmKit 側から消えるため、
            // ここで捨てるとミッションを回避できてしまう。
            let isKnown = UUID(uuidString: stored).map { state(of: $0) != nil } ?? false
            if isKnown || MissionStore.watchdogAlarmID != nil {
                present(alarmID: stored)
                return
            }
            MissionStore.reset(alarmID: stored)
            MissionWatchdog.disarm()
        }
        // 鳴っているアラームもミッション待ちもない = 画面を閉じてよい
        clearPendingState()
    }

    /// 鳴っているアラームに対して、実際に解かせるミッションの対象を返す。
    ///
    /// 見張りの再アラームが鳴っている場合、解くべきなのは**本来のアラーム**のミッション。
    /// 見張りの ID で画面を出すと、停止する相手も記録も取り違える。
    private func missionTarget(forAlerting id: UUID) -> String {
        if MissionWatchdog.isWatchdog(id.uuidString), let pending = MissionStore.pendingAlarmID {
            return pending
        }
        return id.uuidString
    }

    /// AlarmKit の状態変化を購読し続ける。View の `.task` から呼ぶ想定。
    func observeAlarmUpdates() async {
        for await alarms in AlarmManager.shared.alarmUpdates {
            // 先行アラーム（ソフト起床）は除く。1 タップで止まるのがその存在理由で、
            // ここで拾うとミッション画面が出て、本アラームと区別がつかなくなる。
            if let alerting = alarms.first(where: {
                $0.state == .alerting && !SoftWake.isLead($0.id)
            }) {
                present(alarmID: missionTarget(forAlerting: alerting.id))
            } else if MissionStore.pendingAlarmID == nil {
                // 鳴っているアラームも、ミッション待ちのフラグも無い。
                // 他経路（アラート画面の停止ボタン等）で止まったということなので画面を閉じる。
                //
                // ここでクリア済みかどうかを条件に入れてはいけない。
                // アプリからの停止に失敗してクリア済みフラグが立ったまま
                // アラート画面側で停止された場合に、画面が閉じられなくなる。
                clearPendingState()
            }
        }
    }

    private func currentlyAlertingAlarmID() -> UUID? {
        guard let alarms = try? AlarmManager.shared.alarms else { return nil }
        return alarms.first { $0.state == .alerting && !SoftWake.isLead($0.id) }?.id
    }

    private func present(alarmID: String) {
        guard pending?.id != alarmID else { return }
        // 別のアラームに切り替わった場合も含めて設定し直す
        MissionStore.requestMission(alarmID: alarmID)
        // 設定していれば、この瞬間から他のアプリを開けなくする。
        ScreenTimeGuard.shield()
        errorMessage = nil
        // 前の回の祝いが出たままだと、次のアラームのミッション画面が隠れてしまう。
        celebration = nil
        pending = PendingMission(id: alarmID)
        pendingSince = Date()
    }

    /// ミッション待ちではないと確定したときの後始末。
    ///
    /// **アプリの遮断はシステム側に残る。** ミッションが片付いていないのに
    /// 遮断だけ残ると、ユーザーは自力で戻せない。
    /// 「待ちではない」と分かった経路では必ずここを通す。
    private func clearPendingState() {
        ScreenTimeGuard.unshield()
        pending = nil
        pendingSince = nil
    }

    /// 祝いの画面を閉じる。
    func dismissCelebration() {
        celebration = nil
    }

    // MARK: - クリア

    /// ミッション成功時に呼ぶ。ここではじめてアラームを停止し、起床記録を残す。
    ///
    /// - Parameters:
    ///   - missionKind: `"calculation"` または `"shake"`。記録用。
    ///   - wrongAttempts: 計算ミッションでの誤答回数（シェイクは 0 を渡す）。
    func completeMission(missionKind: String, wrongAttempts: Int) {
        guard let mission = pending else { return }
        guard let uuid = mission.alarmUUID else {
            MissionStore.clearPending()
            MissionWatchdog.disarm()
            clearPendingState()
            return
        }

        // Intent 側のフォールバック経路でも停止できるようフラグを立ててから停止する。
        MissionStore.setCleared(true, alarmID: mission.id)

        do {
            try AlarmManager.shared.stop(id: uuid)
        } catch {
            // 鳴っていないアラームに stop() を投げると AlarmKit は throw する。
            // その状態でここに留まらせると、ミッションをクリアしたのに
            // **二度とこの画面から出られなくなる**（fullScreenCover は閉じられない）。
            // 実際に鳴っているときだけ失敗として扱い、それ以外は「止めるものが無い」＝
            // 目的は達成済みとみなして先へ進める。
            guard state(of: uuid) == .alerting else {
                finish(alarmUUID: uuid, mission: mission, missionKind: missionKind, wrongAttempts: wrongAttempts)
                return
            }

            // 本当に鳴っているのに止められなかった場合。
            // クリア済みフラグは**落とさない**。こうしておけば、
            // アラート画面の停止ボタン（MissionGatedStopIntent）が素通しで停止できる。
            errorMessage = "アプリからは停止できませんでした。アラーム画面の停止ボタンを押すと停止します。"
            return
        }

        finish(alarmUUID: uuid, mission: mission, missionKind: missionKind, wrongAttempts: wrongAttempts)
    }

    /// 停止が済んだ（あるいは止めるものが無かった）ときの後始末。
    private func finish(
        alarmUUID: UUID,
        mission: PendingMission,
        missionKind: String,
        wrongAttempts: Int
    ) {
        let result = logWake(
            alarmUUID: alarmUUID,
            missionKind: missionKind,
            wrongAttempts: wrongAttempts
        )

        // 次回の発火に備えてクリアフラグは必ず落としておく。
        MissionStore.reset(alarmID: mission.id)
        // 逃走防止の再アラームも解く。残すとミッション達成後に鳴ってしまう。
        MissionWatchdog.disarm()
        // アプリの遮断も解く。ここを忘れると自力で戻せなくなる。
        ScreenTimeGuard.unshield()
        pending = nil
        pendingSince = nil
        errorMessage = nil
        // 記録を残せなかった場合は nil。祝う材料が無いので、そのまま全画面を閉じる。
        celebration = result
    }

    /// AlarmKit が把握しているアラームの状態。登録が無ければ nil。
    private func state(of id: UUID) -> Alarm.State? {
        guard let alarms = try? AlarmManager.shared.alarms else { return nil }
        return alarms.first { $0.id == id }?.state
    }

    /// 起床記録を 1 件残し、祝いの画面に出す結果を組み立てる。
    ///
    /// 記録を書けない（`modelContext` が未設定）ときは nil。
    /// 自己ベストや実績は記録から導くものなので、記録が無いなら祝う材料も無い。
    private func logWake(
        alarmUUID: UUID,
        missionKind: String,
        wrongAttempts: Int
    ) -> WakeCelebration? {
        guard let modelContext else { return nil }

        let label = (try? modelContext.fetch(
            FetchDescriptor<AlarmEntry>(predicate: #Predicate { $0.id == alarmUUID })
        ))?.first?.label ?? ""

        // 「今回を含まない記録」を先に押さえる。自己ベスト更新と実績の解除は、
        // どちらも**今回の 1 件が加わって初めて成立したか**で決まる。
        let previous = (try? modelContext.fetch(FetchDescriptor<WakeLogEntry>())) ?? []
        let previousFastest = WakeProgress.accumulated(previous).fastestDuration

        let entry = WakeLogEntry(
            alarmID: alarmUUID,
            alarmLabel: label,
            firedAt: pendingSince ?? Date(),
            stoppedAt: Date(),
            missionKind: missionKind,
            wrongAttempts: wrongAttempts
        )
        modelContext.insert(entry)
        try? modelContext.save()

        let all = previous + [entry]
        return WakeCelebration(
            id: alarmUUID.uuidString,
            duration: entry.duration,
            isFastestRecord: previousFastest.map { entry.duration < $0 } ?? false,
            records: WakeRecords.make(entries: all),
            unlockedTitles: AchievementCatalog
                .newlyUnlocked(before: previous, after: all)
                .map(\.title)
        )
    }
}
