import AlarmKit
import FamilyControls
import SwiftUI
import UIKit
import UserNotifications

/// アプリ全体の設定。
///
/// アラーム 1 件ごとの設定（スヌーズ・ミッションの難易度）は編集画面側にあり、
/// ここには「アプリ全体の振る舞い」と「許可の状態」だけを置く。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    /// 就寝リマインダーの予定を計算するために現在のアラーム一覧を受け取る。
    let snapshots: [AlarmSnapshot]

    @State private var settings = AppSettings.shared
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var alarmStatus: AlarmManager.AuthorizationState = .notDetermined
    /// 「今夜 23:00 に通知します」の予告。
    @State private var nextPlan: BedtimeReminder.Plan?
    @State private var isScreenTimeEnabled = ScreenTimeGuard.isEnabled
    @State private var isScreenTimeAuthorized = ScreenTimeGuard.isAuthorized
    @State private var isPickingApps = false
    @State private var appSelection = ScreenTimeGuard.selection

    private var sleepOptions: [SleepOption] {
        AppSettings.sleepHourOptions.map {
            SleepOption(id: String($0), label: AppSettings.sleepHoursText($0))
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Rule(weight: Theme.ruleBold)

                ScrollView {
                    VStack(spacing: 0) {
                        SectionHeading(text: "就寝リマインダー")
                        Rule()
                        bedtimeSection
                        Rule()

                        SectionHeading(text: "アラームのかけ忘れ")
                        Rule()
                        missingAlarmSection
                        Rule()

                        SectionHeading(text: "ミッション中の画面")
                        Rule()
                        brightnessSection
                        Rule()

                        SectionHeading(text: "ミッション中のアプリ制限")
                        Rule()
                        screenTimeSection
                        Rule()

                        SectionHeading(text: "バッテリー警告")
                        Rule()
                        batterySection
                        Rule()

                        SectionHeading(text: "許可の状態")
                        Rule()
                        permissionSection
                        Rule()

                        SectionHeading(text: "このアプリについて")
                        Rule()
                        aboutSection
                        Rule()
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
        }
        .task {
            alarmStatus = AlarmScheduler.authorizationState
            notificationStatus = await NotificationPermission.status()
            refreshPlan()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("設定")
                .font(Theme.title(28))
                .foregroundStyle(Theme.ink)

            Spacer()

            Button("閉じる") { dismiss() }
                .font(Theme.label(15))
                .foregroundStyle(Theme.blue)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - 就寝リマインダー

    private var bedtimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            toggleRow(
                title: "就寝リマインダーを出す",
                isOn: settings.isBedtimeReminderEnabled
            ) { isOn in
                settings.isBedtimeReminderEnabled = isOn
                syncReminder()
            }

            Text("次に鳴るアラームの \(AppSettings.sleepHoursText(settings.sleepHours))前 に通知します。"
                 + "起きられない原因の多くは寝るのが遅いことなので、朝ではなく夜に効かせます。")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if settings.isBedtimeReminderEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("目標睡眠時間")
                        .font(Theme.label(14))
                        .foregroundStyle(Theme.ink)

                    SquareDropdown(
                        options: sleepOptions,
                        selection: Binding(
                            get: { String(settings.sleepHours) },
                            set: { raw in
                                guard let hours = Double(raw) else { return }
                                settings.sleepHours = hours
                                syncReminder()
                            }
                        ),
                        label: \.label
                    )
                }

                statusLine
            }
        }
        .padding(Theme.screenPadding)
        .background(Theme.surface)
    }

    /// 実際に通知が出るのかどうかを、その場で確かめられるようにする。
    /// 「ON にしたのに来ない」の原因（アラームが無い／通知が拒否されている）をここで潰す。
    @ViewBuilder
    private var statusLine: some View {
        if notificationStatus == .denied {
            StatusBlock(
                title: "通知が許可されていません",
                message: "設定アプリ > Wakeout > 通知 を許可すると、就寝リマインダーが届きます。",
                accent: Theme.alertRed,
                action: ("設定を開く", { openSettings() })
            )
        } else if let nextPlan {
            HStack(spacing: 8) {
                Badge(text: "次の通知")
                Text("\(dateText(nextPlan.remindAt))（\(timeText(nextPlan.fireAt)) のアラーム）")
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
        } else {
            Text("鳴る予定のアラームがないため、今は通知しません。")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: - かけ忘れの警告

    private var missingAlarmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            toggleRow(
                title: "明日のアラームが無ければ知らせる",
                isOn: settings.isMissingAlarmWarningEnabled
            ) { isOn in
                settings.isMissingAlarmWarningEnabled = isOn
                syncReminder()
            }

            Text("毎晩 \(MissingAlarmReminder.checkHour) 時に確認し、"
                 + "翌日の昼までに鳴る予定が 1 件も無ければ通知します。"
                 + "起きられなかった後では手遅れなので、まだ間に合ううちに知らせます。")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.screenPadding)
        .background(Theme.surface)
    }

    // MARK: - ミッション中の画面

    private var brightnessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            toggleRow(
                title: "ミッション中は画面を明るくする",
                isOn: settings.isMissionBrightnessEnabled
            ) { settings.isMissionBrightnessEnabled = $0 }

            Text("ミッションの間だけ画面を明るくします。光は覚醒に直接効きます。"
                 + "\(Int(ScreenBrightness.rampDuration))秒かけて、暖色・暗めから最大の明るさまで上げます"
                 + "（いきなり最大にすると眩しさで目を閉じてしまい、かえって覚醒を妨げます）。"
                 + "終わると元の明るさに戻します。")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.screenPadding)
        .background(Theme.surface)
    }

    // MARK: - アプリ制限（スクリーンタイム）

    private var screenTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            toggleRow(
                title: "ミッション中は開けなくする",
                isOn: isScreenTimeEnabled
            ) { isOn in
                setScreenTimeEnabled(isOn)
            }

            Text("ミッションをクリアするまで、選んだアプリを開けなくします。"
                 + "アプリを終了しても解除されません。")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if isScreenTimeEnabled {
                if isScreenTimeAuthorized {
                    Button {
                        isPickingApps = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "app.badge.checkmark")
                            Text(blockedAppsLabel)
                        }
                        .font(Theme.label(15))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.blue)
                        .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.rule) }
                    }
                    .buttonStyle(.plain)

                    if !ScreenTimeGuard.hasSelection {
                        Text("まだ 1 つも選ばれていません。選ぶまでは何も制限されません。")
                            .font(Theme.caption(12))
                            .foregroundStyle(Theme.alertRed)
                    }
                } else {
                    StatusBlock(
                        title: "この端末では利用できません",
                        message: "スクリーンタイムでアプリを制限するには、"
                            + "有料の Apple Developer Program と Family Controls の権限が必要です。"
                            + "無料アカウントのビルドでは有効にできません。"
                            + "権限を追加したビルドなら、下のボタンから許可を求められます。",
                        accent: Theme.alertRed,
                        action: ("許可を求める", { requestScreenTimeAuthorization() })
                    )
                }
            }
        }
        .padding(Theme.screenPadding)
        .background(Theme.surface)
        .familyActivityPicker(isPresented: $isPickingApps, selection: $appSelection)
        .onChange(of: appSelection) { _, newValue in
            ScreenTimeGuard.selection = newValue
        }
    }

    private var blockedAppsLabel: String {
        let count = appSelection.applicationTokens.count
            + appSelection.categoryTokens.count
            + appSelection.webDomainTokens.count
        return count == 0 ? "制限するアプリを選ぶ" : "制限するアプリ（\(count)件）を変更"
    }

    private func setScreenTimeEnabled(_ isOn: Bool) {
        isScreenTimeEnabled = isOn
        ScreenTimeGuard.isEnabled = isOn

        if isOn {
            requestScreenTimeAuthorization()
        } else {
            // OFF にした時点で残っている制限は必ず外す。
            // ここを忘れると、設定を切ったのにアプリが開けないままになる。
            ScreenTimeGuard.unshield()
        }
    }

    private func requestScreenTimeAuthorization() {
        Task {
            isScreenTimeAuthorized = await ScreenTimeGuard.requestAuthorization()
        }
    }

    // MARK: - バッテリー

    private var batterySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            toggleRow(
                title: "残量が少ないときに警告する",
                isOn: settings.isBatteryWarningEnabled
            ) { settings.isBatteryWarningEnabled = $0 }

            Text("残量 20% 未満で充電されていないとき、ホーム画面と通知で知らせます。"
                 + "電源が落ちるとアラームは鳴りません。")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.screenPadding)
        .background(Theme.surface)
    }

    // MARK: - 許可

    private var permissionSection: some View {
        VStack(spacing: 14) {
            permissionRow(
                title: "アラーム",
                isGranted: alarmStatus == .authorized,
                detail: alarmStatus == .authorized
                    ? "アラームを登録できます。"
                    : "許可がないとアラームを作成できません。"
            )

            Rule()

            permissionRow(
                title: "通知",
                isGranted: notificationStatus == .authorized || notificationStatus == .provisional,
                detail: "就寝リマインダーとバッテリー警告に使います。アラーム本体には影響しません。"
            )

            Button("設定アプリを開く") { openSettings() }
                .font(Theme.label(14))
                .foregroundStyle(Theme.blue)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.screenPadding)
        .background(Theme.surface)
    }

    private func permissionRow(title: String, isGranted: Bool, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(Theme.label(15))
                    .foregroundStyle(Theme.ink)
                Spacer()
                // 状態を色だけで示さないよう、必ず文字を持たせる。
                Badge(
                    text: isGranted ? "許可済み" : "未許可",
                    filled: isGranted,
                    tint: isGranted ? Theme.ink : Theme.alertRed
                )
            }
            Text(detail)
                .font(Theme.caption(12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - このアプリについて

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("バージョン")
                    .font(Theme.label(15))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(versionText)
                    .font(Theme.caption(13))
                    .foregroundStyle(Theme.muted)
            }

            Text("Wakeout のアラームは、ミッションをクリアするまで止まりません。"
                 + "アラート画面の停止ボタンを押すとこのアプリが開き、計算かシェイクのどちらかが出ます。")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.screenPadding)
        .background(Theme.surface)
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    // MARK: - 部品

    private func toggleRow(
        title: String,
        isOn: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(Theme.label(15))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            // 状態は色だけでなく文字でも示す
            Text(isOn ? "ON" : "OFF")
                .font(Theme.label(12))
                .kerning(1)
                .foregroundStyle(isOn ? Theme.ink : Theme.muted)
            SquareToggle(isOn: isOn, onChange: onChange)
        }
    }

    // MARK: - 処理

    /// 設定を変えたら、その場で通知の予約を作り直す。
    private func syncReminder() {
        let snapshots = snapshots
        let isEnabled = settings.isBedtimeReminderEnabled
        let hours = settings.sleepHours
        let warnsMissing = settings.isMissingAlarmWarningEnabled

        Task {
            await BedtimeReminder.sync(
                snapshots: snapshots,
                isEnabled: isEnabled,
                sleepHours: hours
            )
            await MissingAlarmReminder.sync(snapshots: snapshots, isEnabled: warnsMissing)
            // 許可ダイアログの結果が反映されてから表示を更新する。
            notificationStatus = await NotificationPermission.status()
            refreshPlan()
        }
    }

    private func refreshPlan() {
        nextPlan = BedtimeReminder
            .plans(snapshots: snapshots, sleepHours: settings.sleepHours)
            .first
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func dateText(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = timeText(date)
        if calendar.isDateInToday(date) { return "今日 \(time)" }
        if calendar.isDateInTomorrow(date) { return "明日 \(time)" }
        return date.formatted(.dateTime.month().day()) + " \(time)"
    }

    private func timeText(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}

/// 目標睡眠時間の選択肢。`SquareDropdown` は ID が String の Identifiable を要求する。
private struct SleepOption: Identifiable {
    let id: String
    let label: String
}
