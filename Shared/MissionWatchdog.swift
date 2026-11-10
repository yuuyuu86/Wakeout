import AlarmKit
import Foundation

/// ミッションをやらずに逃げられないようにする見張り。
///
/// 停止ボタンを押すとアラート自体はその場で消える。
/// このときアプリを落とされると、アプリ側のコードは二度と動かないので、
/// ミッション待ちのフラグを立てただけでは**アプリを開かない限り何も起きない**。
/// つまりアプリを落とすだけでミッションを回避できてしまう。
///
/// そこで、停止ボタンが押された瞬間に「少し後にもう一度鳴るアラーム」を
/// AlarmKit 側へ予約しておく。予約を持っているのはシステムなので、
/// アプリを落としても、消しても（App Group の値は残る）、時間が来れば鳴る。
///
/// 再アラームの停止ボタンにも同じ `MissionGatedStopIntent` を載せてあるため、
/// 押すたびにまた見張りが張り直され、ミッションをクリアするまで終わらない。
enum MissionWatchdog {

    /// 停止ボタンを押してから再び鳴るまでの時間。
    ///
    /// 逃がさないことを優先して短くしてある。
    /// ミッションを解いている最中に鳴ることもあるが、クリアすれば `disarm()` で止まる。
    static let delay: TimeInterval = 30

    /// 見張りを張る。既に張ってあれば張り直す。
    ///
    /// - Parameter missionAlarmID: ミッションの対象になっている本来のアラーム ID。
    static func arm(missionAlarmID: String) async {
        disarm()

        let watchdogID = UUID()
        let configuration = AlarmManager.AlarmConfiguration(
            schedule: .fixed(Date().addingTimeInterval(delay)),
            attributes: attributes,
            stopIntent: MissionGatedStopIntent(alarmID: missionAlarmID),
            sound: .default
        )

        // ID は**登録する前に**記録する。
        // この見張りは SwiftData を持たないので、記録より先に登録すると、
        // その隙に AlarmReconciler が「アプリが知らない登録」として取り消してしまう。
        MissionStore.watchdogAlarmID = watchdogID.uuidString

        do {
            _ = try await AlarmManager.shared.schedule(id: watchdogID, configuration: configuration)
        } catch {
            // 予約できなくても、アプリを開いている限りミッションは表示される。
            // ここで止めるものは無いので、そのまま進める。
            MissionStore.watchdogAlarmID = nil
        }
    }

    /// 見張りを解く。ミッションが片付いたら必ず呼ぶ。
    ///
    /// 見張り自身が鳴っている最中に解くこともある（再アラームで戻ってきてクリアした場合）。
    /// `cancel` は予約を消すだけなので、鳴っているものを黙らせるために `stop` も試す。
    static func disarm() {
        guard let stored = MissionStore.watchdogAlarmID else { return }
        if let uuid = UUID(uuidString: stored) {
            try? AlarmManager.shared.stop(id: uuid)
            try? AlarmManager.shared.cancel(id: uuid)
        }
        MissionStore.watchdogAlarmID = nil
    }

    /// 見張りのアラームか。ミッションの対象そのものと区別したいときに使う。
    static func isWatchdog(_ alarmID: String) -> Bool {
        MissionStore.watchdogAlarmID == alarmID
    }

    // MARK: - 見た目

    private static var attributes: AlarmAttributes<WakeoutAlarmMetadata> {
        let title = LocalizedStringResource("ミッションが残っています")

        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title)
        } else {
            alert = AlarmPresentation.Alert(
                title: title,
                stopButton: AlarmButton(
                    text: "停止",
                    textColor: .white,
                    systemImageName: "stop.circle"
                )
            )
        }

        return AlarmAttributes<WakeoutAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: WakeoutAlarmMetadata(label: "ミッションが残っています"),
            tintColor: Theme.acid
        )
    }
}
