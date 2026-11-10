import SwiftData
import SwiftUI

/// アプリのルート。ミッション待ちの間はホーム画面を覆い隠して操作をブロックする。
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @State private var coordinator = MissionCoordinator()

    var body: some View {
        AlarmListView()
            // fullScreenCover はスワイプで閉じられないため、
            // ミッション未クリアの間は他画面に触れない。
            //
            // ミッションと祝いで**同じ 1 枚の全画面を使い回す**。
            // 別々の cover にすると、閉じる指示と開く指示が同じ瞬間に重なり、
            // 画面が一度黒く落ちるうえ、開き直しが取りこぼされることがある。
            .fullScreenCover(isPresented: Binding(
                get: { coordinator.isPresentingFullScreen },
                set: { _ in /* ユーザー操作では閉じさせない */ }
            )) {
                MissionFlow(coordinator: coordinator, difficulty: difficulty(for:))
            }
            .tint(Theme.blue)
            .task {
                // 起床記録を書き込めるように、ここで一度だけ渡す。
                coordinator.modelContext = modelContext
                // 起動直後に、鳴りっぱなし / ミッション待ちのアラームがないか確認する。
                coordinator.refresh()
                // SwiftData と AlarmKit の食い違いを直す
                // （鳴り終わった単発の後始末、消えた登録の貼り直し）。
                await AlarmReconciler.reconcile(context: modelContext)
                // 以降は AlarmKit の状態変化を購読し続ける。
                await coordinator.observeAlarmUpdates()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // アプリを強制終了して再起動した場合も、ここで強制的にミッション画面へ戻す。
                guard newPhase == .active else { return }
                coordinator.refresh()
                Task { await AlarmReconciler.reconcile(context: modelContext) }
            }
            .onChange(of: coordinator.pending) { oldValue, newValue in
                // ミッションをクリアしてアラームが止まった直後にも整合を取る。
                // 単発アラームはここで OFF になり、一覧とウィジェットが即座に正しくなる。
                guard oldValue != nil, newValue == nil else { return }
                Task { await AlarmReconciler.reconcile(context: modelContext) }
            }
    }

    /// 鳴っているアラームに設定された難易度を引く。
    /// アラームが見つからない（削除済みなど）場合は `.normal` にフォールバックする。
    private func difficulty(for mission: PendingMission) -> MissionDifficulty {
        guard let uuid = mission.alarmUUID else { return .normal }
        let descriptor = FetchDescriptor<AlarmEntry>(predicate: #Predicate { $0.id == uuid })
        return (try? modelContext.fetch(descriptor))?.first?.missionDifficulty ?? .normal
    }
}

/// 全画面の中身。ミッション → 突破の祝い、と切り替わる。
///
/// 中身をここで差し替えるのは、`fullScreenCover` に渡した値の変化では
/// 中身が組み立て直されない場合があるため。`coordinator` を直接読むことで、
/// 全画面は出したまま、状態の変化に確実に追随させている。
private struct MissionFlow: View {
    let coordinator: MissionCoordinator
    let difficulty: (PendingMission) -> MissionDifficulty

    var body: some View {
        ZStack {
            if let celebration = coordinator.celebration {
                CelebrationView(result: celebration) { coordinator.dismissCelebration() }
                    .transition(.opacity)
            } else if let mission = coordinator.pending {
                MissionView(coordinator: coordinator, difficulty: difficulty(mission))
                    // 別のアラームに切り替わったら、解きかけの状態を持ち越さない。
                    .id(mission.id)
            }
        }
        .animation(.snappy(duration: 0.25), value: coordinator.celebration)
    }
}
