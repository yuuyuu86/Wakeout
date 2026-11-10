import AlarmKit
import AppIntents
import Foundation

/// AlarmKit のアラート UI の停止ボタンから起動される Intent。
///
/// ミッション未クリアの間は `AlarmManager.shared.stop(id:)` を **呼ばない**。
/// 代わりに `MissionStore.requestMission(alarmID:)` でミッション待ち状態を立て、
/// `supportedModes = .foreground(.immediate)` によってアプリを強制的に
/// フォアグラウンド化し、`MissionView` を表示させる。
///
/// ミッションクリア後は `MissionCoordinator` がアプリ内から直接 `stop(id:)` を呼ぶため、
/// この Intent の「クリア済み」分岐は、クリア直後に再度停止ボタンが押された場合などの
/// フォールバック経路として機能する。
struct MissionGatedStopIntent: LiveActivityIntent {
    // Swift 6 の strict concurrency では `static var` は
    // 「nonisolated global shared mutable state」としてエラーになるため `static let` で宣言する。
    static let title: LocalizedStringResource = "Stop Alarm"
    static let description = IntentDescription("ミッションをクリアするまでアラームを停止しません。")

    /// 停止ボタンをタップしてもアプリを前面に出すために必須。
    /// これがないとアラームは鳴り続けるだけでミッション画面に到達できない。
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        guard let uuid = UUID(uuidString: alarmID) else {
            // ID が壊れている場合、鳴りっぱなしを避けるため素直に停止する。
            return .result()
        }

        if MissionStore.isCleared(alarmID: alarmID) {
            try AlarmManager.shared.stop(id: uuid)
            MissionStore.reset(alarmID: alarmID)
            MissionWatchdog.disarm()
            ScreenTimeGuard.unshield()
        } else {
            // ミッション未クリア → 停止しない。アプリ側にミッション表示を要求する。
            MissionStore.requestMission(alarmID: alarmID)

            // 停止ボタンを押すとアラート自体はその場で消えるので、
            // ここでアプリを落とされるとミッションを回避できてしまう。
            // アプリが動いていなくても効くよう、システム側に預けておく。
            await MissionWatchdog.arm(missionAlarmID: alarmID)
            ScreenTimeGuard.shield()
        }

        return .result()
    }
}
