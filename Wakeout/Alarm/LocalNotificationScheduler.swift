import Foundation
import UserNotifications

/// ローカル通知の予約・取り消しの唯一の窓口。
///
/// `UNUserNotificationCenter` を複数の場所から同時に触ってはいけない。
/// バッテリー警告（メインスレッド）と就寝リマインダー（バックグラウンド）から
/// 並行して呼んだ結果、メインスレッドが `removePendingNotificationRequests` から
/// 戻らなくなり、アプリが起動直後に固まった。
///
/// actor にして呼び出しを直列化し、かつ**メインスレッドの外**で実行させる。
/// 引数は Sendable な値だけにして、通知オブジェクトの組み立てもこの中で行う。
actor LocalNotificationScheduler {
    static let shared = LocalNotificationScheduler()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - 予約

    /// 指定した日時に通知する。同じ識別子の予約があれば置き換わる。
    func schedule(identifier: String, title: String, body: String, at date: Date) async {
        // 秒まで含めると半端な時刻に届くので分で切る。
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        await add(
            identifier: identifier,
            title: title,
            body: body,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }

    /// 指定した時間だけ後に通知する。
    func schedule(identifier: String, title: String, body: String, after interval: TimeInterval) async {
        await add(
            identifier: identifier,
            title: title,
            body: body,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        )
    }

    private func add(
        identifier: String,
        title: String,
        body: String,
        trigger: UNNotificationTrigger
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    // MARK: - 取り消し

    func removePending(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// 識別子が特定の文字列で始まる予約をまとめて取り消す。
    func removePending(withPrefix prefix: String) async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        removePending(identifiers: identifiers)
    }
}
