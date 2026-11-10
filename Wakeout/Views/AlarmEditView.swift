import SwiftData
import SwiftUI

/// 新規作成 / 編集画面。保存時に AlarmKit へのスケジュールと SwiftData への保存を行う。
struct AlarmEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var alarm: AlarmEntry

    /// まだ SwiftData に載っていなければ新規。
    ///
    /// 呼び出し側で「新規かどうか」を @State で覚えると、
    /// 画面の再構築タイミング次第でズレて既存扱いになることがあった。
    /// 実際に永続化されているかを直接見れば取り違えようがない。
    private var isNew: Bool { alarm.modelContext == nil }

    @State private var hour: Int
    @State private var minute: Int
    @State private var selectedDays: Set<Int>
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var showDeleteConfirmation = false
    @State private var soundOptions: [AlarmSound.Option] = AlarmSound.options()
    @State private var isImportingSound = false
    @State private var soundErrorMessage: String?
    /// 切り出し画面に渡すファイル。非 nil の間だけ画面が出る。
    @State private var trimTarget: TrimTarget?

    init(alarm: AlarmEntry) {
        self.alarm = alarm
        _hour = State(initialValue: alarm.hour)
        _minute = State(initialValue: alarm.minute)
        _selectedDays = State(initialValue: alarm.repeatDays)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.paper.ignoresSafeArea()

            // ヘッダーはスクロールさせない。
            // スクロールさせるとステータスバーの下に文字が潜り込み、
            // キャンセルにもいつでも触れなくなる。
            VStack(spacing: 0) {
                header
                Rule(weight: Theme.ruleBold)

                // 時刻ピッカーもスクロールさせない。
                // ScrollView の中に置くと縦ドラッグを ScrollView に奪われてホイールが回せない。
                // 編集中は常に時刻が見えていてほしいので、固定するのが操作性の面でも都合がよい。
                timeSection
                // 固定の時刻ピッカーとスクロール領域の境目。
                // ヘッダー下と同じ太い罫線にして「ここから先はスクロールする」と分かるようにする。
                Rule(weight: Theme.ruleBold)

                ScrollView {
                    VStack(spacing: 0) {
                        SectionHeading(text: "繰り返し")
                        Rule()
                        weekdaySection
                        Rule()

                        SectionHeading(text: "ラベル")
                        Rule()
                        labelSection
                        Rule()

                        SectionHeading(text: "サウンド")
                        Rule()
                        soundSection
                        Rule()

                        SectionHeading(text: "スヌーズ")
                        Rule()
                        snoozeSection
                        Rule()

                        SectionHeading(text: "ソフト起床")
                        Rule()
                        softWakeSection
                        Rule()

                        SectionHeading(text: "ミッションの難易度")
                        Rule()
                        difficultySection
                        Rule()

                        if let errorMessage {
                            StatusBlock(
                                title: "保存できませんでした",
                                message: errorMessage,
                                accent: Theme.alertRed
                            )
                            .padding(Theme.screenPadding)
                        }

                        if !isNew {
                            deleteSection
                        }
                    }
                    // 下部固定 CTA に隠れないぶんの余白
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
            }

            Button {
                Task { await save() }
            } label: {
                Text(isSaving ? "保存中…" : "保存する")
            }
            .buttonStyle(BrutalButtonStyle(role: .primary, isEnabled: !isSaving))
            .disabled(isSaving)
        }
        .confirmationDialog("このアラームを削除しますか？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("削除する", role: .destructive) { deleteAlarm() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("\(alarm.timeText) のアラームが削除されます。この操作は取り消せません。")
        }
        // 画面を出す指示はこの階層に置く。
        // ScrollView の奥のセクションに付けると、再構築のタイミング次第で
        // 中身の描かれていないカバーが出ることがある。
        .fileImporter(
            isPresented: $isImportingSound,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fullScreenCover(item: $trimTarget) { target in
            SoundTrimView(source: target.url, originalName: target.name) { fileName in
                finishTrimming(target: target, fileName: fileName)
            }
        }
        // 試聴はこの画面の中だけのもの。
        // 保存でもキャンセルでも、閉じた先まで鳴り続けさせない。
        .onDisappear { SoundPreviewPlayer.shared.stop() }
    }

    // MARK: - ヘッダー

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(isNew ? "アラームを追加" : "アラームを編集")
                .font(Theme.title(28))
                .foregroundStyle(Theme.ink)

            Spacer()

            Button("キャンセル") { cancel() }
                .font(Theme.label(15))
                .foregroundStyle(Theme.blue)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - 時刻

    private var timeSection: some View {
        SquareTimePicker(hour: $hour, minute: $minute)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(Theme.acid)
    }

    // MARK: - 曜日

    private var weekdaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    let isSelected = selectedDays.contains(index)
                    Button {
                        if isSelected {
                            selectedDays.remove(index)
                        } else {
                            selectedDays.insert(index)
                        }
                    } label: {
                        Text(AlarmEntry.weekdaySymbols[index])
                            .font(Theme.label(15))
                            // 選択中＝操作された状態なので青。未選択は面を持たない。
                            .foregroundStyle(isSelected ? .white : Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(isSelected ? Theme.blue : Theme.surface)
                            .overlay {
                                Rectangle().stroke(Theme.ink, lineWidth: Theme.rule)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(AlarmEntry.weekdaySymbols[index])曜日")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }

            Text(repeatSummary)
                .font(Theme.caption(12))
                .foregroundStyle(Theme.muted)
        }
        .padding(Theme.screenPadding)
        .background(Theme.surface)
    }

    private var repeatSummary: String {
        let time = String(format: "%02d:%02d", hour, minute)
        if selectedDays.isEmpty {
            return "1回のみ。次に来る \(time) に鳴ります。"
        }
        let days = selectedDays.sorted().map { AlarmEntry.weekdaySymbols[$0] }.joined(separator: "・")
        return "毎週 \(days) の \(time) に鳴ります。"
    }

    // MARK: - ラベル

    private var labelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("起きる", text: $alarm.label)
                .font(Theme.label(17))
                .foregroundStyle(Theme.ink)
                .padding(14)
                .background(Theme.surface)
                .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.rule) }

            Text("アラート画面のタイトルになります。空欄なら「Wakeout」。")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.muted)
        }
        .padding(Theme.screenPadding)
        .background(Theme.surface)
    }

    // MARK: - サウンド

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 音源が増えても縦に伸びすぎないよう、選択肢は普段は畳んでおく。
            SquareDropdown(
                options: soundOptions,
                selection: $alarm.soundName,
                label: { $0.displayName },
                isRemovable: { $0.isRemovable },
                onRemove: { removeSound($0) },
                onSelect: { SoundPreviewPlayer.shared.play($0.id) }
            )

            Button {
                isImportingSound = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("音源を追加")
                }
                .font(Theme.label(15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.ink)
            }
            .buttonStyle(.plain)

            Text("選ぶと試聴します。追加するときに、音源のどこを使うか選べます。")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.muted)

            if let soundErrorMessage {
                Text(soundErrorMessage)
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.alertRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.screenPadding)
        .background(Theme.surface)
    }

    /// 選んだファイルを切り出し画面へ渡す。
    ///
    /// 30 秒に収めるのは通知音の要件だが、頭に無音や前奏がある音源だと
    /// 先頭を機械的に切ると使い物にならない。どこを使うかはユーザーに決めてもらう。
    /// 30 秒未満の音源でも、必要なところだけを切り出せる。
    private func handleImport(_ result: Result<[URL], Error>) {
        soundErrorMessage = nil
        do {
            guard let url = try result.get().first else { return }
            let staged = try SoundLibrary.stageForTrimming(from: url)
            trimTarget = TrimTarget(
                url: staged,
                name: url.deletingPathExtension().lastPathComponent
            )
        } catch {
            soundErrorMessage = "取り込めませんでした: \(error.localizedDescription)"
        }
    }

    private func finishTrimming(target: TrimTarget, fileName: String?) {
        // 一時コピーは取り込み後もキャンセル後も残さない。
        SoundLibrary.discardStaged(target.url)
        trimTarget = nil

        guard let fileName else { return }
        soundOptions = AlarmSound.options()
        alarm.soundName = fileName
        SoundPreviewPlayer.shared.play(fileName)
    }

    private func removeSound(_ option: AlarmSound.Option) {
        SoundPreviewPlayer.shared.stop()
        SoundLibrary.remove(option.id)
        // 消した音源を選択中だったら、無音にならないようデフォルトへ戻す
        if alarm.soundName == option.id {
            alarm.soundName = AlarmSound.defaultIdentifier
        }
        soundOptions = AlarmSound.options()
    }

    // MARK: - スヌーズ

    private var snoozeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("スヌーズを許可する")
                    .font(Theme.label(15))
                    .foregroundStyle(Theme.ink)
                Spacer()
                SquareToggle(isOn: alarm.snoozeEnabled) { alarm.snoozeEnabled = $0 }
            }

            Text(
                alarm.snoozeEnabled
                    ? "アラート画面に「スヌーズ」ボタンが出ます。押すと \(Int(AlarmScheduler.snoozeDuration / 60)) 分後にもう一度鳴ります。停止にはミッションが必要です。"
                    : "スヌーズボタンを出しません。停止するにはミッションのクリアが必要です。"
            )
            .font(Theme.caption(12))
            .foregroundStyle(Theme.muted)
        }
        .padding(Theme.screenPadding)
        .background(Theme.surface)
    }

    // MARK: - ソフト起床

    /// 本アラームの前に、1 タップで止まる先行アラームを鳴らすかどうか。
    ///
    /// 深い眠りから叩き起こされるのが苦痛の最大の原因だが、睡眠段階は測れない。
    /// 代わりに**反応できたかどうか**で浅い眠りを当てにいく仕組みなので、
    /// 「鳴る回数が増える」ことも含めて素直に書いておく。
    private var softWakeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("先に起こしてみる")
                    .font(Theme.label(15))
                    .foregroundStyle(Theme.ink)
                Spacer()
                SquareToggle(isOn: alarm.softWakeEnabled) { alarm.softWakeEnabled = $0 }
            }

            Text(
                alarm.softWakeEnabled
                    ? "本アラームの \(softWakeLeadText)前に、ミッション無しで"
                        + "1 タップで止まる先行アラームが鳴ります。"
                        + "それで起きられたら、ホーム画面の「もう起きた」を長押しすると"
                        + "本アラームを止められます。"
                        + "眠りが深くて反応できなければ、本アラームが時刻どおりに鳴ります。"
                        + "先行アラームも同じサウンドで鳴るので、"
                        + "立ち上がりの穏やかな音源にしておくと効きます。"
                    : "先行アラームを鳴らしません。設定した時刻に本アラームだけが鳴ります。"
            )
            .font(Theme.caption(12))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.screenPadding)
        .background(Theme.surface)
    }

    /// 「20分・10分」のような先行アラームの時刻表記。
    private var softWakeLeadText: String {
        SoftWake.leadOffsets
            .sorted(by: >)
            .map { "\(Int($0 / 60))分" }
            .joined(separator: "・")
    }

    // MARK: - ミッション難易度

    private var difficultySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(MissionDifficulty.allCases) { level in
                    let isSelected = alarm.missionDifficulty == level
                    Button {
                        alarm.missionDifficulty = level
                    } label: {
                        Text(level.displayName)
                            .font(Theme.label(14))
                            .foregroundStyle(isSelected ? .white : Theme.ink)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(isSelected ? Theme.blue : Theme.surface)
                            .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.rule) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }

            Text(difficultyDescription)
                .font(Theme.caption(12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.screenPadding)
        .background(Theme.surface)
    }

    private var difficultyDescription: String {
        let d = alarm.missionDifficulty
        let ranges = d.calculationRanges
        return """
        停止まで \(d.requiredMissionCount) 問。種類は毎回ランダムに変わります。
        計算: \(ranges.lhs.lowerBound)〜\(ranges.lhs.upperBound) × \(ranges.rhs.lowerBound)〜\(ranges.rhs.upperBound) / \
        シェイク: \(d.requiredShakeCount) 回 / \
        記憶: \(d.memoryDigits) 桁 / タイピング: \(d.typingLength) 文字
        """
    }

    // MARK: - 削除

    private var deleteSection: some View {
        Button {
            showDeleteConfirmation = true
        } label: {
            Text("このアラームを削除")
                .font(Theme.label(15))
                .foregroundStyle(Theme.alertRed)
                .frame(maxWidth: .infinity, minHeight: 52)
                .overlay { Rectangle().stroke(Theme.alertRed, lineWidth: Theme.rule) }
        }
        .buttonStyle(.plain)
        .padding(Theme.screenPadding)
    }

    private func deleteAlarm() {
        AlarmScheduler.cancel(id: alarm.id)
        modelContext.delete(alarm)
        try? modelContext.save()
        dismiss()
    }

    // MARK: - 保存 / キャンセル

    private func cancel() {
        SoundPreviewPlayer.shared.stop()
        // 新規は保存時まで insert していないので、破棄は何もしなくてよい。
        dismiss()
    }

    private func save() async {
        // 画面を離れる操作なので、試聴はここで止める。
        SoundPreviewPlayer.shared.stop()
        isSaving = true
        defer { isSaving = false }

        alarm.hour = hour
        alarm.minute = minute
        alarm.repeatDays = selectedDays

        // 新規はここではじめて SwiftData に載せる
        if alarm.modelContext == nil {
            modelContext.insert(alarm)
        }

        do {
            try modelContext.save()
        } catch {
            errorMessage = "端末への保存に失敗しました。もう一度お試しください。（\(error.localizedDescription)）"
            return
        }

        guard alarm.isEnabled else {
            dismiss()
            return
        }

        do {
            try await AlarmScheduler.schedule(alarm)
            // schedule() が lastScheduledAt を更新するので、それも書き込む
            try? modelContext.save()
            dismiss()
        } catch {
            errorMessage = AlarmScheduler.userFacingMessage(for: error)
        }
    }
}

/// 切り出し画面へ渡す 1 件分。`fullScreenCover(item:)` に載せるため Identifiable。
struct TrimTarget: Identifiable, Equatable {
    /// 作業用ディレクトリに複製済みのファイル。
    let url: URL
    /// 元のファイル名（保存名の元にする）。
    let name: String

    var id: URL { url }
}
