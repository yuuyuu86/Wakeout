import Foundation
import UserNotifications

/// ローカル通知の許可まわり。
///
/// バッテリー警告と就寝リマインダーの 2 か所から使うので、
/// 「未確定なら聞く・拒否されていたら諦める」という判断をここに 1 本化している。
enum NotificationPermission {
    /// 通知を出せる状態にする。出せないなら false。
    ///
    /// - Important: `.notDetermined` のときだけ許可を求める。
    ///   一度拒否された相手に繰り返し聞いてもダイアログは出ないため、そのまま false を返す。
    static func ensureAuthorized() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }

        return await isAuthorized()
    }

    /// 今の許可状態。ダイアログは出さない。
    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}
