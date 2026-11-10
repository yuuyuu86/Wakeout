import AlarmKit
import Foundation
import OSLog
import SwiftUI

/// AlarmKit への登録・解除をまとめた薄いラッパ。
enum AlarmScheduler {

    enum SchedulingError: LocalizedError {
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                "アラームの権限が許可されていません。"
            }
        }
    }

    // MARK: - 権限

    static var authorizationState: AlarmManager.AuthorizationState {
        AlarmManager.shared.authorizationState
    }

    /// 未決定なら権限ダイアログを出す。決定済みならその状態をそのまま返す。
    @discardableResult
    static func requestAuthorizationIfNeeded() async -> AlarmManager.AuthorizationState {
        let current = AlarmManager.shared.authorizationState
        guard current == .notDetermined else { return current }
        do {
            return try await AlarmManager.shared.requestAuthorization()
        } catch {
            return AlarmManager.shared.authorizationState
        }
    }

    // MARK: - スケジュール

    /// スヌーズを選んだ場合に再度鳴るまでの時間。
    static let snoozeDuration: TimeInterval = 9 * 60

    /// `entry` を AlarmKit に登録する。
    ///
    /// 既存の同 ID は登録し直せないので、登録済みなら先に取り消す。
    /// ただし**今まさに鳴っているアラームには触らない**。
    ///
    /// - Parameter overridingSchedule: 曜日の繰り返しの代わりに使う予定。
    ///   ソフト起床で「今日のぶんだけ飛ばす」ときに、次の 1 回を日時で押さえるために使う
    ///   （`SoftWake.confirmWakeUp`）。普段は nil のままにすること。
    ///
    /// SwiftData のモデル（`entry`）に触るので `@MainActor`。
    /// 呼び出し元は画面か整合処理で、いずれもメインアクタ上にある。
    @MainActor
    static func schedule(
        _ entry: AlarmEntry,
        overridingSchedule: Alarm.Schedule? = nil
    ) async throws {
        guard AlarmManager.shared.authorizationState == .authorized else {
            throw SchedulingError.notAuthorized
        }

        // 鳴っている（あるいはスヌーズ待ちの）アラームを登録し直してはいけない。
        // 取り消せばその場で鳴り止み、ミッション待ちフラグも消えて、
        // **ミッションをやらずにアラームが止まる**。この状態は触らずに抜ける。
        //
        // フォアグラウンド復帰のたびに AlarmReconciler が走るので、
        // 停止ボタン → アプリ前面化 の直後がちょうどこの条件に当たる。
        if let state = currentState(of: entry.id), state != .scheduled {
            logger.notice(
                "鳴っている最中のため登録し直さない: id=\(entry.id.uuidString, privacy: .public)"
            )
            return
        }

        // 再スケジュール時は必ずミッション状態をリセットしておく。
        // （前回クリア済みのフラグが残っていると停止ボタン一発で止まってしまう）
        MissionStore.reset(alarmID: entry.id.uuidString)

        let attributes = AlarmAttributes<WakeoutAlarmMetadata>(
            presentation: presentation(for: entry),
            metadata: WakeoutAlarmMetadata(label: entry.label),
            // システムが描画するアラート UI の差し色。アプリ内の「有効状態」と同じ色にする。
            tintColor: Theme.acid
        )

        // スヌーズを許可したアラームだけ postAlert のカウントダウンを持たせる。
        // これが無いと secondaryButtonBehavior = .countdown を指定しても再アラートされない。
        let countdownDuration: Alarm.CountdownDuration? = entry.snoozeEnabled
            ? Alarm.CountdownDuration(preAlert: nil, postAlert: snoozeDuration)
            : nil

        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: overridingSchedule ?? schedule(for: entry),
            attributes: attributes,
            stopIntent: MissionGatedStopIntent(alarmID: entry.id.uuidString),
            sound: AlarmSound.alertSound(for: entry.soundName)
        )

        // 既に登録されている ID は、そのままでは登録し直せない。
        // AlarmKit は "Not scheduling an alarm with a duplicate ID" として拒否し、
        // アプリ側には invalidInput（画面上は「エラー0」）としてだけ返ってくる。
        // 編集して保存するときは必ずこれに当たるので、先に取り消しておく。
        if isRegistered(entry.id) {
            try? AlarmManager.shared.cancel(id: entry.id)
        }

        do {
            _ = try await AlarmManager.shared.schedule(id: entry.id, configuration: configuration)
        } catch {
            log(error, phase: "schedule", id: entry.id)
            // 取り消しが行き渡る前に登録し直した可能性がある。1 度だけやり直す。
            try? AlarmManager.shared.cancel(id: entry.id)
            do {
                _ = try await AlarmManager.shared.schedule(id: entry.id, configuration: configuration)
            } catch {
                log(error, phase: "再試行", id: entry.id)
                throw error
            }
        }
        entry.lastScheduledAt = Date()

        // 先行アラームは本アラームの時刻から決まるので、必ず登録し直す。
        //
        // ただし予定を差し替えたとき（＝今日のぶんを飛ばした直後）は張らない。
        // そのときの「次に鳴る時刻」は SwiftData 側の曜日から求まる今日の時刻のままで、
        // 飛ばしたはずの時刻に向けて先行アラームを張ることになる。
        // 次の分はアプリを開いたときに補充される（`AlarmReconciler`）。
        if overridingSchedule == nil {
            await SoftWake.sync(for: entry)
        }
    }

    /// AlarmKit が持っているその ID の状態。登録が無ければ nil。
    private static func currentState(of id: UUID) -> Alarm.State? {
        guard let alarms = try? AlarmManager.shared.alarms else { return nil }
        return alarms.first { $0.id == id }?.state
    }

    /// AlarmKit がその ID を登録している予定。登録が無ければ nil。
    ///
    /// 「繰り返しアラームなのに日時指定で登録されている」＝ ソフト起床で
    /// 今日のぶんを飛ばした直後、という判定に使う（`AlarmReconciler`）。
    static func registeredSchedule(of id: UUID) -> Alarm.Schedule? {
        guard let alarms = try? AlarmManager.shared.alarms else { return nil }
        return alarms.first { $0.id == id }?.schedule
    }

    /// その ID が AlarmKit に登録されているか。
    private static func isRegistered(_ id: UUID) -> Bool {
        currentState(of: id) != nil
    }

    /// 今まさに鳴っている（またはスヌーズ待ち・一時停止中の）アラームか。
    ///
    /// この状態のアラームを取り消すと、ミッションを通さずに鳴り止んでしまう。
    /// 自動で後始末をする処理は、この判定で必ず避けること。
    static func isRinging(_ id: UUID) -> Bool {
        guard let state = currentState(of: id) else { return false }
        return state != .scheduled
    }

    /// 失敗の中身を残す。
    ///
    /// AlarmKit のエラーは画面上「エラー0」としか出ず、原因の切り分けができない。
    /// ドメインとコードだけでもログに残しておく。
    private static func log(_ error: Error, phase: String, id: UUID) {
        let nsError = error as NSError
        logger.error(
            """
            アラームの登録に失敗: phase=\(phase, privacy: .public) \
            id=\(id.uuidString, privacy: .public) \
            domain=\(nsError.domain, privacy: .public) code=\(nsError.code) \
            info=\(nsError.userInfo.description, privacy: .public)
            """
        )
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Wakeout",
        category: "AlarmScheduler"
    )

    /// AlarmKit から登録を取り消す。SwiftData 側の削除は呼び出し元の責任。
    static func cancel(id: UUID) {
        // 本アラームが無くなれば、その前触れも要らない。
        SoftWake.cancelAll(forAlarmID: id)
        do {
            try AlarmManager.shared.cancel(id: id)
        } catch {
            // 未登録の ID を cancel すると throw されるが、
            // 「結果的に登録されていない」状態は望みどおりなので握りつぶす。
        }
        MissionStore.reset(alarmID: id.uuidString)
    }

    /// 登録に失敗した理由を、次の行動が分かる日本語にする。
    ///
    /// AlarmKit の生のエラーは「com.apple.AlarmKit.Alarm エラー0」のように出るため、
    /// そのまま見せても何をすればよいか分からない。
    static func userFacingMessage(for error: Error) -> String {
        if let alarmError = error as? AlarmManager.AlarmError {
            switch alarmError {
            case .maximumLimitReached:
                return "登録できるアラームの上限に達しました。使っていないアラームを削除するか OFF にしてから、もう一度保存してください。"
            @unknown default:
                break
            }
        }
        if let schedulingError = error as? SchedulingError {
            return schedulingError.localizedDescription
        }
        return "アラームを登録できませんでした。（\(error.localizedDescription)）"
    }

    /// 現在 AlarmKit に登録されているアラームの ID。
    /// 権限が無い / 取得に失敗した場合は nil を返す。
    /// **空配列と nil を区別すること。** nil を「全部消えた」と誤解すると全件を消してしまう。
    static func scheduledIDs() -> Set<UUID>? {
        guard AlarmManager.shared.authorizationState == .authorized else { return nil }
        guard let alarms = try? AlarmManager.shared.alarms else { return nil }
        return Set(alarms.map(\.id))
    }

    // MARK: - 組み立て

    private static func presentation(for entry: AlarmEntry) -> AlarmPresentation {
        let title = LocalizedStringResource(stringLiteral: entry.label.isEmpty ? "Wakeout" : entry.label)

        // スヌーズを許可したアラームだけ副ボタンを持たせる。
        // .countdown を指定すると、タップ時にシステムが自動でカウントダウン状態へ遷移し、
        // postAlert の時間が経つとまた鳴る（カスタム Intent は不要）。
        let secondaryButton: AlarmButton? = entry.snoozeEnabled
            ? AlarmButton(text: "スヌーズ", textColor: .white, systemImageName: "zzz")
            : nil
        let secondaryButtonBehavior: AlarmPresentation.Alert.SecondaryButtonBehavior? =
            entry.snoozeEnabled ? .countdown : nil

        // iOS 26.1 以降、停止ボタンの見た目はシステムが描画するようになり
        // `stopButton` は無視される（API 自体が deprecated）。
        // 26.0 でだけ「停止」ラベルを指定したいので分岐している。
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(
                title: title,
                secondaryButton: secondaryButton,
                secondaryButtonBehavior: secondaryButtonBehavior
            )
        } else {
            alert = AlarmPresentation.Alert(
                title: title,
                stopButton: AlarmButton(
                    text: "停止",
                    textColor: .white,
                    systemImageName: "stop.circle"
                ),
                secondaryButton: secondaryButton,
                secondaryButtonBehavior: secondaryButtonBehavior
            )
        }

        let countdown: AlarmPresentation.Countdown? = entry.snoozeEnabled
            ? AlarmPresentation.Countdown(title: "スヌーズ中")
            : nil

        return AlarmPresentation(alert: alert, countdown: countdown)
    }

    private static func schedule(for entry: AlarmEntry) -> Alarm.Schedule {
        let time = Alarm.Schedule.Relative.Time(hour: entry.hour, minute: entry.minute)
        let weekdays = entry.repeatDays.sorted().compactMap(Self.weekday(fromIndex:))
        let recurrence: Alarm.Schedule.Relative.Recurrence = weekdays.isEmpty ? .never : .weekly(weekdays)
        return .relative(Alarm.Schedule.Relative(time: time, repeats: recurrence))
    }

    /// 0=日, 1=月, ..., 6=土 → `Locale.Weekday`
    private static func weekday(fromIndex index: Int) -> Locale.Weekday? {
        switch index {
        case 0: .sunday
        case 1: .monday
        case 2: .tuesday
        case 3: .wednesday
        case 4: .thursday
        case 5: .friday
        case 6: .saturday
        default: nil
        }
    }
}
