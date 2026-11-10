import Foundation
import Observation
import UIKit

/// 「バッテリーが少ないまま充電せずに寝てしまう」のを防ぐための監視。
///
/// AlarmKit は端末の電源が落ちていれば当然鳴らない。
/// アプリを開いた・フォアグラウンドに戻ったタイミングでバッテリー残量と充電状態を見て、
/// 危険な組み合わせ（残量少 + 非充電 + 有効なアラームあり）なら
/// 画面内バナーと、アプリを閉じても届くローカル通知の両方で知らせる。
///
/// - Important: iOS シミュレータは実バッテリーを持たないため `UIDevice.batteryLevel` は
///   常に -1（不明）を返す。この機能は**実機でのみ**動作を確認できる。
@MainActor
@Observable
final class BatteryGuard {
    /// この残量を下回ったら警告する。
    private static let lowBatteryThreshold: Float = 0.2
    private static let notificationIdentifier = "wakeout.battery-low"
    private static let lastWarnedDateKey = "battery_guard_last_warned_date"
    /// 通知は「少し経ってもまだ危険な状態が続いていたら」届けたい。
    /// アプリを見ている間に即届いても意味が薄く、離れた後に効くようにする。
    private static let notificationDelay: TimeInterval = 10 * 60

    private(set) var isLow = false
    private(set) var isUnplugged = false

    var shouldShowBanner: Bool { isLow && isUnplugged }

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
    }

    func refresh() {
        let device = UIDevice.current
        let level = device.batteryLevel
        // シミュレータや取得失敗時は level が負値になる。誤警告を避けるため false 扱いにする。
        isLow = level >= 0 && level < Self.lowBatteryThreshold
        isUnplugged = device.batteryState == .unplugged
    }

    /// 有効なアラームがあるかどうかを渡してもらい、通知の要否を判断する。
    /// 条件を満たさなくなっていたら、出しっぱなしの通知を取り消す。
    ///
    /// - Important: 通知の操作は必ず `LocalNotificationScheduler` 経由で行う。
    ///   ここから `UNUserNotificationCenter` を直接呼ぶと、メインスレッドを止めたまま
    ///   他の通知処理の完了を待つ形になり、アプリごと固まる。
    func syncNotification(hasEnabledAlarm: Bool) async {
        refresh()
        guard shouldShowBanner, hasEnabledAlarm else {
            await LocalNotificationScheduler.shared
                .removePending(identifiers: [Self.notificationIdentifier])
            return
        }
        guard !warnedToday() else { return }

        await scheduleNotification()
    }

    private func warnedToday() -> Bool {
        guard let last = UserDefaults.standard.object(forKey: Self.lastWarnedDateKey) as? Date else {
            return false
        }
        return Calendar.current.isDateInToday(last)
    }

    private func scheduleNotification() async {
        guard await NotificationPermission.ensureAuthorized() else { return }

        await LocalNotificationScheduler.shared.schedule(
            identifier: Self.notificationIdentifier,
            title: "バッテリー残量が少なくなっています",
            body: "充電されていません。このままでは朝のアラームが鳴らないおそれがあります。",
            after: Self.notificationDelay
        )
        UserDefaults.standard.set(Date(), forKey: Self.lastWarnedDateKey)
    }
}
