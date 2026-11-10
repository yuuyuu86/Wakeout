import Foundation

/// アプリ本体と Widget Extension の両方から参照される共有定義。
///
/// - Important: Bundle ID を変更する場合は、ここの `appGroupID` と
///   `Wakeout.xcodeproj` の `WAKEOUT_BUNDLE_ID` (Project レベルの Build Setting) の
///   両方を書き換えること。
enum WakeoutShared {
    /// App Group の suite name。entitlements の値と完全に一致している必要がある。
    static let appGroupID = "group.com.yourname.wakeout.shared"

    /// App Group 共有の UserDefaults。
    /// 取得に失敗した場合（App Group 未設定など）は standard にフォールバックする。
    /// フォールバックすると Extension とアプリ本体で値が共有されないため、
    /// 開発中に気付けるよう assert を入れている。
    static var defaults: UserDefaults {
        guard let shared = UserDefaults(suiteName: appGroupID) else {
            assertionFailure("App Group '\(appGroupID)' が有効になっていません。Signing & Capabilities を確認してください。")
            return .standard
        }
        return shared
    }
}

/// ミッションのクリア状態と「ミッション待ち」状態を App Group 越しに管理するストア。
///
/// stopIntent はアプリ本体のプロセスで動くこともあれば Extension 側で動くこともあるため、
/// 状態は必ずここ（App Group の UserDefaults）を経由してやりとりする。
enum MissionStore {
    /// アラーム毎のミッションクリアフラグのキー。
    private static func clearedKey(_ alarmID: String) -> String {
        "mission_cleared_\(alarmID)"
    }

    /// 「ミッション画面を出さなければならないアラーム」の ID を保持するキー。
    private static let pendingKey = "pending_mission_alarm_id"

    /// ミッション未達のまま逃げられないよう予約した、再アラームの ID。
    private static let watchdogKey = "pending_mission_watchdog_id"

    // MARK: - クリアフラグ

    static func isCleared(alarmID: String) -> Bool {
        WakeoutShared.defaults.bool(forKey: clearedKey(alarmID))
    }

    static func setCleared(_ cleared: Bool, alarmID: String) {
        let defaults = WakeoutShared.defaults
        if cleared {
            defaults.set(true, forKey: clearedKey(alarmID))
        } else {
            defaults.removeObject(forKey: clearedKey(alarmID))
        }
    }

    // MARK: - ミッション待ち状態

    /// stopIntent が「まだクリアしていない」と判断したときに呼ぶ。
    /// アプリ側はこの値を見てミッション画面を強制表示する。
    static func requestMission(alarmID: String) {
        WakeoutShared.defaults.set(alarmID, forKey: pendingKey)
    }

    /// ミッション画面を出すべきアラーム ID。nil ならミッション不要。
    static var pendingAlarmID: String? {
        WakeoutShared.defaults.string(forKey: pendingKey)
    }

    static func clearPending() {
        WakeoutShared.defaults.removeObject(forKey: pendingKey)
    }

    // MARK: - 再アラーム（見張り）

    /// 予約中の再アラームの ID。無ければ nil。
    static var watchdogAlarmID: String? {
        get { WakeoutShared.defaults.string(forKey: watchdogKey) }
        set {
            if let newValue {
                WakeoutShared.defaults.set(newValue, forKey: watchdogKey)
            } else {
                WakeoutShared.defaults.removeObject(forKey: watchdogKey)
            }
        }
    }

    /// アラームをスケジュールし直すタイミングで状態をリセットする。
    static func reset(alarmID: String) {
        setCleared(false, alarmID: alarmID)
        if pendingAlarmID == alarmID {
            clearPending()
        }
    }
}

/// ウィジェット用のアラーム一覧を App Group 越しに共有するストア。
///
/// アプリ側で SwiftData が変更されるたびに書き出し、
/// Widget Extension のタイムライン生成時に読み出す。
enum AlarmSnapshotStore {
    private static let key = "alarm_snapshots"

    static func save(_ snapshots: [AlarmSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        WakeoutShared.defaults.set(data, forKey: key)
    }

    static func load() -> [AlarmSnapshot] {
        guard let data = WakeoutShared.defaults.data(forKey: key),
              let snapshots = try? JSONDecoder().decode([AlarmSnapshot].self, from: data) else {
            return []
        }
        return snapshots
    }
}

/// 先行アラーム（ソフト起床）の ID を App Group 越しに共有するストア。
///
/// 先行アラームは SwiftData に持たない。`AlarmEntry` 1 件から派生する一時的な登録で、
/// 発火のたびに作り直すため、永続モデルにすると後始末だけが増える。
/// 代わりに「いまどの ID が先行アラームなのか」をここに残す。
///
/// これが無いと 2 つ困ることが起きる。
/// - `MissionCoordinator` が先行アラームの鳴動をミッション待ちと取り違える
///   （＝1 タップで止まるはずの先行アラームでミッション画面が出る）
/// - `AlarmReconciler` が「アプリが知らない登録」として取り消してしまう
///
/// 食い違ったときは**どちらに転んでも安全**な側に倒す。
/// ストアにあって AlarmKit に無い ID は、取り消しを投げても何も起きない。
/// AlarmKit にあってストアに無い ID は整合処理で消えるだけで、
/// その朝ソフト起床が働かないにとどまる（本アラームには影響しない）。
enum SoftWakeStore {
    private static let key = "soft_wake_lead_ids"

    /// アラーム ID（文字列）→ その先行アラームの ID 群。
    private static var table: [String: [String]] {
        get {
            WakeoutShared.defaults.dictionary(forKey: key) as? [String: [String]] ?? [:]
        }
        set {
            if newValue.isEmpty {
                WakeoutShared.defaults.removeObject(forKey: key)
            } else {
                WakeoutShared.defaults.set(newValue, forKey: key)
            }
        }
    }

    static func leadIDs(forAlarmID alarmID: String) -> [UUID] {
        (table[alarmID] ?? []).compactMap(UUID.init(uuidString:))
    }

    static func setLeadIDs(_ ids: [UUID], forAlarmID alarmID: String) {
        var current = table
        if ids.isEmpty {
            current.removeValue(forKey: alarmID)
        } else {
            current[alarmID] = ids.map(\.uuidString)
        }
        table = current
    }

    /// いま登録されている先行アラームすべて。
    static var allLeadIDs: Set<UUID> {
        Set(table.values.flatMap { $0 }.compactMap(UUID.init(uuidString:)))
    }

    static func isLead(_ id: UUID) -> Bool {
        allLeadIDs.contains(id)
    }
}
