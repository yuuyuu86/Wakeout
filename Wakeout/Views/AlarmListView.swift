import AlarmKit
import Combine
import SwiftData
import SwiftUI

/// ホーム画面。「次に鳴る時刻」を最優先で見せ、その下に全アラームを並べる。
struct AlarmListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \AlarmEntry.createdAt, order: .reverse) private var alarms: [AlarmEntry]
    @Query(sort: \WakeLogEntry.stoppedAt, order: .reverse) private var wakeLog: [WakeLogEntry]

    @State private var editingTarget: AlarmEntry?
    @State private var authorizationState: AlarmManager.AuthorizationState = .notDetermined
    @State private var showDeniedAlert = false
    /// スワイプで開いている行。同時に開くのは 1 行だけにする。
    @State private var openRowID: UUID?
    /// ON にしたのに登録できなかったときの理由。
    @State private var scheduleErrorMessage: String?
    /// ソフト起床の確定に失敗したときの理由。
    @State private var softWakeErrorMessage: String?
    /// 「あと〇時間」を 1 分ごとに更新するための現在時刻。
    @State private var now = Date()
    @State private var batteryGuard = BatteryGuard()
    @State private var showWakeLog = false
    @State private var showSettings = false
    @State private var settings = AppSettings.shared

    private var records: WakeRecords { WakeRecords.make(entries: wakeLog, now: now) }

    /// バッテリー警告を出す条件。設定で切れていれば出さない。
    private var showsBatteryWarning: Bool {
        settings.isBatteryWarningEnabled && batteryGuard.shouldShowBanner
    }

    private var hasEnabledAlarm: Bool { alarms.contains { $0.isEnabled } }

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// 次に鳴るアラーム。ヒーロー表示に使う。
    private var nextAlarm: (entry: AlarmEntry, date: Date)? {
        alarms
            .compactMap { entry in
                entry.nextFireDate(from: now).map { (entry, $0) }
            }
            .min { $0.1 < $1.1 }
    }

    /// いまソフト起床の窓にいるアラーム（＝先行アラームが鳴ったあと、本アラームの前）。
    ///
    /// 複数あれば最も早く鳴るものを対象にする。
    /// 「もう起きた」で止める相手が 2 つあると、どちらを止めたのか分からなくなる。
    private var softWakeTarget: (entry: AlarmEntry, fireAt: Date)? {
        alarms
            .compactMap { entry in
                SoftWake.fireDateIfInWindow(for: entry, now: now).map { (entry, $0) }
            }
            .min { $0.1 < $1.1 }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.paper.ignoresSafeArea()

            // ヘッダーはスクロールさせない
            // （スクロールさせるとステータスバーの下に文字が潜り込む）。
            VStack(spacing: 0) {
                header
                Rule(weight: Theme.ruleBold)

                ScrollView {
                    VStack(spacing: 0) {
                        if authorizationState == .denied {
                            permissionBlock
                        }

                        if showsBatteryWarning {
                            batteryBlock
                        }

                        // ソフト起床の窓にいる間だけ。起きた直後に最初に目に入る位置に置く。
                        if let softWakeTarget {
                            softWakeCard(entry: softWakeTarget.entry, fireAt: softWakeTarget.fireAt)
                        }

                        // ヒーローの枠は常に埋める。
                        // 空だと画面の上半分が抜け落ちて、何をする画面なのか分からなくなる。
                        if let nextAlarm {
                            heroCard(entry: nextAlarm.entry, fireDate: nextAlarm.date)
                        } else if !alarms.isEmpty {
                            allOffCard
                        } else {
                            emptyHeroCard
                        }

                        // 記録が 1 件でもあれば自己ベストを出す。
                        // ヒーローの直下＝毎回必ず目に入る位置に置くことで、
                        // 「次に鳴る時刻」と「これまでの自分」が一続きに読める。
                        if records.hasAny {
                            recordBand
                        }

                        // 1 件も無いときは見出しごと出さない。
                        // 中身の無いセクションが残ると、読み込みに失敗したように見える。
                        if !alarms.isEmpty {
                            SectionHeading(text: "すべてのアラーム")
                            Rule()

                            ForEach(alarms) { alarm in
                                SwipeableRow(
                                    id: alarm.id,
                                    leading: SwipeAction(
                                        title: "複製",
                                        systemImage: "plus.square.on.square",
                                        tint: Theme.blue
                                    ) { duplicate(alarm) },
                                    trailing: SwipeAction(
                                        title: "削除",
                                        systemImage: "trash",
                                        tint: Theme.alertRed
                                    ) { delete(alarm) },
                                    openRowID: $openRowID,
                                    onTap: { editingTarget = alarm }
                                ) {
                                    AlarmRow(
                                        alarm: alarm,
                                        onToggle: { setEnabled($0, for: alarm) }
                                    )
                                }
                            }

                            Text("左スワイプで削除、右スワイプで複製。引き切るとそのまま実行されます。")
                                .font(Theme.caption(12))
                                .foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Theme.screenPadding)
                                .padding(.vertical, 16)
                        }
                    }
                    // 下部固定 CTA に隠れないぶんの余白
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
            }

            addButton
        }
        // sheet は上端が角丸で固定なので、四角い画面言語に合わせて全画面で出す。
        .fullScreenCover(item: $editingTarget) { alarm in
            AlarmEditView(alarm: alarm)
        }
        .fullScreenCover(isPresented: $showWakeLog) {
            WakeLogView(
                entries: wakeLog,
                records: records,
                onDelete: { deleteWakeLog($0) },
                onDeleteAll: { deleteAllWakeLogs() }
            )
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView(snapshots: alarms.map(\.snapshot))
        }
        .alert(
            "アラームを ON にできませんでした",
            isPresented: Binding(
                get: { scheduleErrorMessage != nil },
                set: { if !$0 { scheduleErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { scheduleErrorMessage = nil }
        } message: {
            Text(scheduleErrorMessage ?? "")
        }
        .alert(
            "本アラームを止められませんでした",
            isPresented: Binding(
                get: { softWakeErrorMessage != nil },
                set: { if !$0 { softWakeErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { softWakeErrorMessage = nil }
        } message: {
            Text(softWakeErrorMessage ?? "")
        }
        .alert("アラームの権限がありません", isPresented: $showDeniedAlert) {
            Button("設定を開く") { openSettings() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("設定アプリ > Wakeout でアラームを許可すると作成できます。")
        }
        .task {
            authorizationState = AlarmScheduler.authorizationState
            await syncBatteryNotification()
        }
        .onReceive(ticker) { now = $0 }
        // 追加・編集・削除・ON/OFF のいずれでもこの一覧は変化するので、
        // 一覧に追随するもの（ウィジェット・就寝リマインダー）はこの 1 箇所に集約する。
        .onChange(of: alarms.map(\.snapshot), initial: true) { _, snapshots in
            WidgetSync.publish(snapshots)
            syncBedtimeReminder(snapshots: snapshots)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await syncBatteryNotification() }
            // 予約は数回分しか入れていないので、開くたびに先の分を補充する。
            syncBedtimeReminder(snapshots: alarms.map(\.snapshot))
        }
    }

    // MARK: - ソフト起床

    /// 先行アラームで目が覚めた人に、本アラームを止める手段を出す。
    ///
    /// **先行アラームの停止ボタンでは本アラームは止まらない。** 寝ぼけたまま
    /// 押せてしまうと、そのまま寝坊するため。止めるにはここを長押しする。
    private func softWakeCard(entry: AlarmEntry, fireAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heroEyebrow("ソフト起床", color: Theme.ink)

            Text("もう起きた？")
                .font(Theme.title(32))
                .foregroundStyle(Theme.ink)

            Text("このまま起きていられるなら、本アラームを止められます。"
                 + "\(timeText(fireAt)) の\(entry.label.isEmpty ? "アラーム" : "「\(entry.label)」")は"
                 + "鳴らなくなります（\(AlarmEntry.countdownText(to: fireAt, from: now))）。")
                .font(Theme.caption(13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HoldToConfirmButton(title: "長押しで本アラームを止める") {
                confirmSoftWake(entry)
            }

            Text("二度寝しそうなら、何もしないでください。時刻どおりに本アラームが鳴ります。")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 本番の acid とは分ける。ここは「まだ本アラームが控えている」状態。
        .background(Theme.dawn)
        .overlay(alignment: .bottom) { Rule(weight: Theme.ruleBold) }
    }

    private func timeText(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private func confirmSoftWake(_ entry: AlarmEntry) {
        Task {
            do {
                try await SoftWake.confirmWakeUp(entry, context: modelContext)
                try? modelContext.save()
            } catch {
                softWakeErrorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - ヘッダー

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WAKEOUT")
                    .font(Theme.title(38))
                    .kerning(-0.5)
                    .foregroundStyle(Theme.ink)
                Text("ミッションをクリアするまで止まらない")
                    .font(Theme.caption(13))
                    .foregroundStyle(Theme.muted)
            }

            Spacer(minLength: 12)

            // 連続日数はここには出さない。
            // ヒーロー直下の帯（recordBand）に最長・最速と揃えて置いてある。
            // 同じ数字を 1 画面に二度出すと、どちらを見ればよいのか分からなくなる。
            HStack(spacing: 8) {
                iconButton(systemImage: "gearshape", label: "設定を開く") {
                    showSettings = true
                }
                iconButton(systemImage: "clock", label: "起床の記録を見る") {
                    showWakeLog = true
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    /// ヘッダーの四角いアイコンボタン。
    private func iconButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.rule) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - ヒーロー（画面上部の大きなカード）

    /// ヒーローの高さの下限。
    ///
    /// 「次に鳴る」「すべて OFF」「まだ無い」の 3 状態で**高さを変えない**ための値。
    /// 状態が変わるたびに上のカードが伸び縮みすると、下の一覧ごと動いて目が追えなくなる。
    /// Theme のフォントは Dynamic Type で変わらない固定サイズなので、
    /// この下限を 3 状態の自然な高さより少し上に取れば、実際の高さは常に一致する。
    private static let heroMinHeight: CGFloat = 236

    /// 3 状態で共通の骨組み。
    /// 「見出し → 大きな文字 → 下端の帯」の構造と余白をここに集約する。
    private func heroFrame<Content: View>(
        background: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, minHeight: Self.heroMinHeight, alignment: .leading)
            .background(background)
            .overlay(alignment: .bottom) { Rule(weight: Theme.ruleBold) }
    }

    /// カード上部の小見出し。
    private func heroEyebrow(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.label(13))
            .kerning(1.5)
            .foregroundStyle(color)
    }

    /// 次に鳴るアラームがあるとき。
    private func heroCard(entry: AlarmEntry, fireDate: Date) -> some View {
        Button {
            editingTarget = entry
        } label: {
            heroFrame(background: Theme.acid) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        heroEyebrow("次に鳴る", color: Theme.ink)
                        Text("・")
                        Text(AlarmEntry.countdownText(to: fireDate, from: now))
                            .font(Theme.label(13))
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.bottom, 4)

                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text(entry.timeText)
                            .font(Theme.display(88))
                            .foregroundStyle(Theme.ink)
                        Text(entry.repeatText)
                            .font(Theme.label(15))
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 0)
                    }

                    Spacer(minLength: 16)

                    HStack(spacing: 0) {
                        Text(entry.label.isEmpty ? "ラベルなし" : entry.label)
                            .font(Theme.label(14))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.ink)

                        Text("解除にミッション")
                            .font(Theme.label(14))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Theme.ink).frame(width: Theme.rule)
                            }
                    }
                    .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.rule) }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("次に鳴るアラーム \(entry.timeText) \(entry.repeatText)。タップで編集")
    }

    /// アラームはあるが全部 OFF のとき。
    ///
    /// 黒い面で「このままでは鳴らない」ことを示す。
    /// イエローは鳴る予定があるときだけの色なので使わない。
    private var allOffCard: some View {
        heroFrame(background: Theme.ink) {
            VStack(alignment: .leading, spacing: 0) {
                heroEyebrow("鳴る予定なし", color: .white.opacity(0.7))
                    .padding(.bottom, 6)

                Text("すべて\nOFF です")
                    .font(Theme.display(44))
                    .foregroundStyle(.white)

                Spacer(minLength: 16)

                // 黒い面の上なので、帯は白地に黒文字で反転させる。
                Text("一覧のスイッチを ON にしてください")
                    .font(Theme.label(14))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("すべてのアラームが OFF です。一覧のスイッチを ON にしてください")
    }

    /// アラームが 1 件も無いとき。
    ///
    /// ヒーローの枠を空けたままにすると画面の上半分が抜けてしまうので、同じ場所を埋める。
    /// 色は面を持たない白。イエローは「これから鳴る」状態のための色なので使わない。
    private var emptyHeroCard: some View {
        Button {
            Task { await startCreating() }
        } label: {
            heroFrame(background: Theme.surface) {
                VStack(alignment: .leading, spacing: 0) {
                    heroEyebrow("はじめよう", color: Theme.muted)
                        .padding(.bottom, 6)

                    Text("アラームを\n登録しよう")
                        .font(Theme.display(44))
                        .foregroundStyle(Theme.ink)

                    Spacer(minLength: 16)

                    Text("ミッションをクリアするまで止まりません")
                        .font(Theme.label(14))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.ink)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("アラームを登録する")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - 自己ベストの帯

    /// ヒーローの直下に置く「連続・最長・最速」。タップで記録画面へ。
    ///
    /// 実績の一覧も記録画面にあるので、ここが唯一の入口ではなく**近道**になる。
    private var recordBand: some View {
        Button {
            showWakeLog = true
        } label: {
            HStack(spacing: 0) {
                recordCell(value: "\(records.currentStreak)日", caption: "連続", isLead: true)
                recordCell(value: "\(records.longestStreak)日", caption: "最長")
                recordCell(
                    value: WakeRecords.durationText(records.fastestDuration),
                    caption: "最速突破"
                )
            }
            .background(Theme.surface)
            .overlay(alignment: .bottom) { Rule() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "連続\(records.currentStreak)日、最長\(records.longestStreak)日、"
                + "最速突破\(WakeRecords.durationText(records.fastestDuration))。タップで記録を見る"
        )
        .accessibilityAddTraits(.isButton)
    }

    private func recordCell(value: String, caption: String, isLead: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(Theme.display(28))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(Theme.caption(11))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .leading) {
            if !isLead {
                Rectangle().fill(Theme.ink).frame(width: Theme.rule)
            }
        }
    }

    // MARK: - 権限

    private var permissionBlock: some View {
        VStack(spacing: 0) {
            StatusBlock(
                title: "アラームの権限がありません",
                message: "このままではアラームが鳴りません。設定アプリで許可してください。",
                accent: Theme.alertRed,
                action: ("設定を開く", { openSettings() })
            )
            .padding(Theme.screenPadding)
        }
        .background(Theme.paper)
    }

    // MARK: - バッテリー警告

    /// - Important: シミュレータは実バッテリーを持たないため、この画面は実機でのみ確認できる。
    private var batteryBlock: some View {
        StatusBlock(
            title: "バッテリー残量が少ないです",
            message: "充電されていません。このままでは朝のアラームが鳴らないおそれがあります。",
            accent: Theme.alertRed
        )
        .padding(Theme.screenPadding)
    }

    // MARK: - 追加 CTA

    private var addButton: some View {
        Button {
            Task { await startCreating() }
        } label: {
            Text("＋  アラームを追加")
        }
        .buttonStyle(BrutalButtonStyle(role: .primary))
    }

    /// 仕様どおり、新規作成ボタンのタップ時に権限をリクエストする。
    private func startCreating() async {
        let state = await AlarmScheduler.requestAuthorizationIfNeeded()
        authorizationState = state

        guard state == .authorized else {
            showDeniedAlert = true
            return
        }

        // ここでは insert しない。
        // 未確定のアラームが SwiftData に居ると、AlarmReconciler が
        // 「有効なのに未登録」と判断して触ってしまうため、確定は保存時に行う。
        editingTarget = AlarmEntry()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - 通知の同期

    /// - Important: 通知の操作は待つ側に回る（`await`）。
    ///   ビューの本体から同期的に呼ぶとメインスレッドを止めてしまう。
    private func syncBatteryNotification() async {
        // 設定で切っている間は、出しっぱなしの予約も取り消したいので
        // 「有効なアラームが無い」のと同じ扱いで渡す。
        await batteryGuard.syncNotification(
            hasEnabledAlarm: settings.isBatteryWarningEnabled && hasEnabledAlarm
        )
    }

    private func syncBedtimeReminder(snapshots: [AlarmSnapshot]) {
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
        }
    }

    // MARK: - 操作

    private func setEnabled(_ isOn: Bool, for alarm: AlarmEntry) {
        alarm.isEnabled = isOn
        try? modelContext.save()
        now = Date()

        Task {
            if isOn {
                do {
                    try await AlarmScheduler.schedule(alarm)
                    // schedule() が lastScheduledAt を更新するので、それも書き込む
                    try? modelContext.save()
                } catch {
                    // 登録に失敗したまま ON に見えていると「鳴るはずが鳴らない」状態になる。
                    // OFF に戻し、理由を伝える。
                    alarm.isEnabled = false
                    try? modelContext.save()
                    scheduleErrorMessage = AlarmScheduler.userFacingMessage(for: error)
                }
            } else {
                AlarmScheduler.cancel(id: alarm.id)
            }
        }
    }

    /// 同じ設定のアラームをもう 1 件作る。
    /// 「平日 6:30 と 6:45 の 2 段構え」のような使い方をすぐできるようにするための操作。
    private func duplicate(_ alarm: AlarmEntry) {
        let copy = AlarmEntry(
            hour: alarm.hour,
            minute: alarm.minute,
            repeatDays: alarm.repeatDays,
            label: alarm.label,
            soundName: alarm.soundName,
            isEnabled: alarm.isEnabled,
            snoozeEnabled: alarm.snoozeEnabled,
            missionDifficulty: alarm.missionDifficulty
        )
        // id / createdAt / lastScheduledAt は複製しない。
        // 別のアラームとして AlarmKit に登録し直す必要があるため。
        modelContext.insert(copy)
        try? modelContext.save()
        now = Date()

        guard copy.isEnabled else { return }
        Task {
            try? await AlarmScheduler.schedule(copy)
            try? modelContext.save()
        }
    }

    // MARK: - 起床記録

    /// 記録を 1 件消す。
    ///
    /// 統計（平均起床時刻・連続日数）はこの記録から作られるので、
    /// テストで作った記録を消せないと、以降ずっと数字が歪んだままになる。
    private func deleteWakeLog(_ entry: WakeLogEntry) {
        modelContext.delete(entry)
        try? modelContext.save()
    }

    private func deleteAllWakeLogs() {
        for entry in wakeLog {
            modelContext.delete(entry)
        }
        try? modelContext.save()
    }

    private func delete(_ alarm: AlarmEntry) {
        // AlarmKit と SwiftData の両方から消す。
        AlarmScheduler.cancel(id: alarm.id)
        modelContext.delete(alarm)
        try? modelContext.save()
    }
}

// MARK: - 行

/// 行の見た目のみを持つ。
///
/// 編集を開くタップは `SwipeableRow` 側で扱う。
/// ここに `Button` を置くと、スワイプ中に Button のタップも同時に成立してしまい、
/// 引き切ったつもりが編集画面が開く、という取り違えが起きるため。
private struct AlarmRow: View {
    @Bindable var alarm: AlarmEntry
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                Text(alarm.timeText)
                    .font(Theme.display(46))
                    .foregroundStyle(alarm.isEnabled ? Theme.ink : Theme.muted)
                    .frame(width: 118, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(alarm.label.isEmpty ? "ラベルなし" : alarm.label)
                        .font(Theme.label(15))
                        .foregroundStyle(alarm.isEnabled ? Theme.ink : Theme.muted)
                        .lineLimit(1)
                    Text(alarm.repeatText)
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.muted)
                }

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(alarm.timeText) \(alarm.repeatText) \(alarm.label)。タップで編集")
            .accessibilityAddTraits(.isButton)

            // 状態は色だけでなく文字でも示す
            Text(alarm.isEnabled ? "ON" : "OFF")
                .font(Theme.label(12))
                .kerning(1)
                .foregroundStyle(alarm.isEnabled ? Theme.ink : Theme.muted)

            SquareToggle(isOn: alarm.isEnabled, onChange: onToggle)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 14)
        .background(alarm.isEnabled ? Theme.acid : Theme.surface)
        // 罫線は行の一部として持たせる（List の区切り線は使わない）
        .overlay(alignment: .bottom) { Rule() }
    }
}
