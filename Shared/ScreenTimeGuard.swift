import FamilyControls
import Foundation
import ManagedSettings

/// ミッションをクリアするまで、選んだアプリを開けなくする。
///
/// スクリーンタイム（`ManagedSettings`）の遮断は**システム側に残る**。
/// アプリを落としても消えないので、`MissionWatchdog` と同じく
/// 「アプリを終了して逃げる」に対して有効に働く。
///
/// - Important: 裏を返すと、解除もこちらから明示的に行う必要がある。
///   ミッションが片付いていないのに遮断だけ残ると、ユーザーは自力で戻せない。
///   起動時に「ミッション待ちでなければ必ず解除する」自己修復を必ず通すこと。
///
/// - Important: `com.apple.developer.family-controls` の権限が要る。
///   権限が無い / 許可されていない場合は**何もしない**。
///   遮断できないだけで、アラームとミッションの動作には影響させない。
enum ScreenTimeGuard {

    /// 遮断に使うストア。名前を付けて、他の設定と混ざらないようにする。
    ///
    /// `ManagedSettingsStore` は Sendable ではないので使うたびに作る。
    /// 同じ名前で作れば同じ設定を指すので、持ち回す必要はない。
    private static var store: ManagedSettingsStore {
        ManagedSettingsStore(named: .init("wakeout.mission"))
    }

    private enum Key {
        static let enabled = "screen_time_guard_enabled"
        static let selection = "screen_time_guard_selection"
    }

    // MARK: - 設定

    /// 機能を使うか。既定は OFF（スクリーンタイムの許可を伴うため、自分で入れてもらう）。
    static var isEnabled: Bool {
        get { WakeoutShared.defaults.bool(forKey: Key.enabled) }
        set { WakeoutShared.defaults.set(newValue, forKey: Key.enabled) }
    }

    /// 遮断する対象。ユーザーが `FamilyActivityPicker` で選ぶ。
    ///
    /// **全アプリを一括で遮断する方法は採らない。**
    /// Wakeout 自身まで開けなくなると、ミッションを解く手段が無くなる。
    static var selection: FamilyActivitySelection {
        get {
            guard let data = WakeoutShared.defaults.data(forKey: Key.selection),
                  let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
            else { return FamilyActivitySelection() }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            WakeoutShared.defaults.set(data, forKey: Key.selection)
        }
    }

    /// 遮断する対象が 1 つでも選ばれているか。
    static var hasSelection: Bool {
        let selection = selection
        return !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
    }

    /// 実際に遮断できる状態か。
    static var isActive: Bool {
        isEnabled && isAuthorized && hasSelection
    }

    static var isAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    /// スクリーンタイムの利用許可を求める。許可されたら true。
    ///
    /// - Note: 端末の所有者本人として使うため `.individual` を指定する。
    ///   シミュレータでは失敗する（実機でのみ確認できる）。
    static func requestAuthorization() async -> Bool {
        if isAuthorized { return true }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            return isAuthorized
        } catch {
            return false
        }
    }

    // MARK: - 遮断

    /// 選ばれたアプリを開けなくする。ミッション待ちになった瞬間に呼ぶ。
    static func shield() {
        guard isActive else { return }
        let selection = selection
        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil
            : selection.webDomainTokens
    }

    /// 遮断を解く。
    ///
    /// ミッションが片付いたときだけでなく、「ミッション待ちではない」と分かったときは
    /// 常に呼んでよい。設定が OFF でも許可が無くても安全に呼べる。
    static func unshield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
    }
}
