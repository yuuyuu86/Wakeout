import SwiftUI

/// 出題されるミッションの種類。
enum MissionKind: CaseIterable {
    case calculation
    case shake
    case memory
    case typing
    case walk

    var headline: String {
        switch self {
        case .calculation: "計算しろ"
        case .shake: "振れ"
        case .memory: "覚えろ"
        case .typing: "打ち込め"
        case .walk: "歩け"
        }
    }

    /// 起床記録に残す識別子。
    var logIdentifier: String {
        switch self {
        case .calculation: "calculation"
        case .shake: "shake"
        case .memory: "memory"
        case .typing: "typing"
        case .walk: "walk"
        }
    }
}

/// 記憶ミッションで出す数字の並び。
enum MemorySequence {
    static func random(length: Int) -> String {
        (0..<max(1, length)).map { _ in String(Int.random(in: 0...9)) }.joined()
    }
}

/// タイピングミッションで打たせる文字列。
enum TypingChallenge {
    /// 使う文字。
    ///
    /// 見間違えやすいもの（l と 1、o と 0）は入れない。
    /// 起き抜けに読み違えて何度も打ち直させるのは、難しさではなく単なる嫌がらせになる。
    private static let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")

    static func random(length: Int) -> String {
        String((0..<max(1, length)).map { _ in alphabet.randomElement() ?? "a" })
    }

    /// 入力が一致しているか。前後の空白と大文字小文字は問わない。
    static func matches(_ input: String, target: String) -> Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target.lowercased()
    }
}

/// 計算問題 1 問ぶん。
struct CalculationProblem {
    let lhs: Int
    let rhs: Int

    var answer: Int { lhs * rhs }
    var text: String { "\(lhs) × \(rhs)" }

    static func random(ranges: (lhs: ClosedRange<Int>, rhs: ClosedRange<Int>)) -> CalculationProblem {
        CalculationProblem(lhs: Int.random(in: ranges.lhs), rhs: Int.random(in: ranges.rhs))
    }
}

/// ミッション画面。クリアするまで閉じられない。
///
/// 起き抜けに見る画面なので、1 画面に 1 つの指示しか置かない。
struct MissionView: View {
    let coordinator: MissionCoordinator
    /// このアラームに設定された難易度。アラームが見つからない場合は `.normal`。
    let difficulty: MissionDifficulty

    @State private var kind: MissionKind = MissionKind.allCases.randomElement() ?? .calculation
    @State private var problem: CalculationProblem
    @State private var input: String = ""
    @State private var showWrongAnswer = false
    /// 起床記録に残すための誤答回数。問題をまたいで積み上げる。
    @State private var wrongAttempts = 0
    /// クリアした問題数。難易度によって必要な数が変わる。
    @State private var clearedRounds = 0
    @State private var shakeDetector = ShakeDetector()
    @State private var stepDetector = StepDetector()
    /// 計算ミッションで電卓を開いているか。
    @State private var showsCalculator = false
    @FocusState private var isInputFocused: Bool

    /// 記憶ミッションの段階。
    private enum MemoryPhase { case showing, answering }
    @State private var memoryPhase: MemoryPhase = .showing
    @State private var memorySequence = ""
    /// 数字を隠すまでの残り秒数。
    @State private var memoryRemaining = 0
    /// 出題し直した回数。これを変えると出題のタスクが走り直す。
    @State private var memoryRound = 0

    @State private var typingTarget: String

    /// 地の色が acid まで移りきったか。`onAppear` で true にしてランプを始める。
    @State private var hasReachedDaylight = false

    /// 段階的に明るくするか。明るさの設定に合わせる
    /// （「最大にしない」と決めた人の画面で、色だけ勝手に動かさない）。
    private var isDawnEnabled: Bool { AppSettings.shared.isMissionBrightnessEnabled }

    init(coordinator: MissionCoordinator, difficulty: MissionDifficulty) {
        self.coordinator = coordinator
        self.difficulty = difficulty
        _problem = State(initialValue: .random(ranges: difficulty.calculationRanges))
        _typingTarget = State(initialValue: TypingChallenge.random(length: difficulty.typingLength))
    }

    private var requiredShakeCount: Int { difficulty.requiredShakeCount }
    private var requiredStepCount: Int { difficulty.requiredStepCount }

    var body: some View {
        ZStack(alignment: .bottom) {
            // 地の色は暖色から始めて acid へ移す。明るさのランプと同じ時間で動かす。
            // 画面の明るさと色が別の速さで動くと、ちらついて見える。
            (hasReachedDaylight || !isDawnEnabled ? Theme.acid : Theme.dawn)
                .ignoresSafeArea()
                .animation(
                    isDawnEnabled ? .linear(duration: ScreenBrightness.rampDuration) : nil,
                    value: hasReachedDaylight
                )

            VStack(alignment: .leading, spacing: 0) {
                banner

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 10) {
                            // 何問目かを先に見せる。あと何回あるのか分からないと集中できない。
                            if difficulty.requiredMissionCount > 1 {
                                Text("\(clearedRounds + 1) / \(difficulty.requiredMissionCount) 問")
                                    .font(Theme.label(14))
                                    .kerning(1)
                                    .foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .overlay {
                                        Rectangle().stroke(Theme.ink, lineWidth: Theme.rule)
                                    }
                            }

                            Text(kind.headline)
                                .font(Theme.title(56))
                                .foregroundStyle(Theme.ink)
                        }

                        switch kind {
                        case .calculation:
                            calculationMission
                        case .shake:
                            shakeMission
                        case .memory:
                            memoryMission
                        case .typing:
                            typingMission
                        case .walk:
                            walkMission
                        }

                        if let errorMessage = coordinator.errorMessage {
                            StatusBlock(
                                title: "停止できませんでした",
                                message: errorMessage,
                                accent: Theme.alertRed
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 28)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }

            VStack(spacing: 0) {
                // 電卓は解答ボタンのすぐ上に出す。問題は上に残したままにしたいので、
                // 全画面では出さない。
                if showsCalculator, kind == .calculation {
                    MiniCalculator(
                        onSubmit: { value in
                            input = value
                            showsCalculator = false
                        },
                        onClose: { showsCalculator = false }
                    )
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, 12)
                    .transition(.opacity)
                }

                if kind != .shake, kind != .walk {
                    Button("解答する") { submitAnswer() }
                        .buttonStyle(BrutalButtonStyle(role: .primary, isEnabled: canSubmit))
                        .disabled(!canSubmit)
                }
            }
            .animation(.snappy(duration: 0.18), value: showsCalculator)
        }
        .interactiveDismissDisabled()
        .onAppear {
            switch kind {
            case .shake:
                shakeDetector.start()
            case .walk:
                stepDetector.start()
            case .memory:
                // 数字を見せている間は入力させない。キーボードは隠しておく。
                break
            case .calculation, .typing:
                isInputFocused = true
            }
            // 起き抜けの覚醒に光が効く。ミッションの間だけ画面を明るくする。
            // 一息で最大にはせず、地の色と合わせて暖色・低輝度から上げていく。
            ScreenBrightness.maximize()
            hasReachedDaylight = true
        }
        .onDisappear {
            shakeDetector.stop()
            stepDetector.stop()
            ScreenBrightness.restore()
        }
        // 記憶ミッションの出題。誤答のたびに memoryRound が変わって出し直す。
        .task(id: memoryRound) {
            guard kind == .memory else { return }
            memoryPhase = .showing
            memorySequence = MemorySequence.random(length: difficulty.memoryDigits)
            input = ""
            memoryRemaining = difficulty.memoryDisplaySeconds

            while memoryRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                memoryRemaining -= 1
            }
            memoryPhase = .answering
            isInputFocused = true
        }
        .onChange(of: shakeDetector.count) { _, newValue in
            if kind == .shake, newValue >= requiredShakeCount {
                shakeDetector.stop()
                clear()
            }
        }
        .onChange(of: stepDetector.count) { _, newValue in
            if kind == .walk, newValue >= requiredStepCount {
                stepDetector.stop()
                clear()
            }
        }
    }

    // MARK: - 上部バナー（なぜこの画面が出ているかを説明する）

    private var banner: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("アラーム作動中")
                    .font(Theme.label(13))
                    .kerning(1.5)
                    .foregroundStyle(Theme.acid)
                Text("クリアするまで停止できません")
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.acid.opacity(0.8))
            }

            Spacer(minLength: 0)

            // 電卓は計算問題のときだけ。他の種類では意味が無い。
            if kind == .calculation {
                Button {
                    isInputFocused = false
                    showsCalculator.toggle()
                } label: {
                    Image(systemName: "plus.forwardslash.minus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(showsCalculator ? Theme.ink : .white)
                        .frame(width: 40, height: 40)
                        .background(showsCalculator ? Theme.acid : Color.clear)
                        .overlay {
                            Rectangle().stroke(Theme.acid, lineWidth: Theme.rule)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsCalculator ? "電卓を閉じる" : "電卓を開く")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 14)
        .background(Theme.ink)
    }

    // MARK: - a. 計算問題

    private var calculationMission: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(problem.text)
                .font(Theme.display(72))
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            answerField(keyboard: .numberPad, placeholder: "答えを入力")

            if showWrongAnswer {
                // 何が起きたかと、次に何をすればよいかを両方書く
                Text("不正解です。新しい問題に切り替えました。もう一度計算してください。")
                    .font(Theme.caption(13))
                    .foregroundStyle(Theme.alertRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 解答ボタンを押せるか。
    private var canSubmit: Bool {
        switch kind {
        case .calculation: Int(input) != nil
        case .memory: memoryPhase == .answering && !input.isEmpty
        case .typing: !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .shake, .walk: false
        }
    }

    private func submitAnswer() {
        switch kind {
        case .calculation:
            guard let value = Int(input) else { return }
            if value == problem.answer {
                clear()
            } else {
                // 失敗時のペナルティは無し。別の問題を出して再挑戦させる。
                fail()
                problem = .random(ranges: difficulty.calculationRanges)
            }

        case .memory:
            guard memoryPhase == .answering else { return }
            if input.trimmingCharacters(in: .whitespacesAndNewlines) == memorySequence {
                clear()
            } else {
                fail()
                // 出し直す。同じ数字をもう一度見せてしまうと覚え直す意味がない。
                memoryRound += 1
            }

        case .typing:
            if TypingChallenge.matches(input, target: typingTarget) {
                clear()
            } else {
                fail()
                typingTarget = TypingChallenge.random(length: difficulty.typingLength)
            }

        case .shake, .walk:
            break
        }
    }

    /// 1 問クリアしたときの処理。必要な数に達していなければ次の問題へ進む。
    private func clear() {
        guard clearedRounds + 1 >= difficulty.requiredMissionCount else {
            clearedRounds += 1
            startNextRound()
            return
        }
        coordinator.completeMission(missionKind: kind.logIdentifier, wrongAttempts: wrongAttempts)
    }

    /// 次の問題を出す。種類も引き直す。
    ///
    /// 同じ種類を続けるより、違う感覚を使わせるほうが覚醒に効く
    /// （計算 → シェイク → タイピングのように切り替わる）。
    private func startNextRound() {
        shakeDetector.stop()
        shakeDetector.reset()
        stepDetector.stop()
        stepDetector.reset()
        showsCalculator = false

        input = ""
        showWrongAnswer = false
        problem = .random(ranges: difficulty.calculationRanges)
        typingTarget = TypingChallenge.random(length: difficulty.typingLength)
        kind = MissionKind.allCases.randomElement() ?? .calculation

        // 記憶ミッションの出題タスクを必ず作り直す。
        // 記憶以外へ切り替えた場合も、前の回のタスクを止めるために変える必要がある。
        memoryRound += 1

        switch kind {
        case .shake:
            shakeDetector.start()
        case .walk:
            stepDetector.start()
        case .calculation, .typing:
            isInputFocused = true
        case .memory:
            // 数字を見せている間は入力させない。
            isInputFocused = false
        }
    }

    private func fail() {
        wrongAttempts += 1
        showWrongAnswer = true
        input = ""
    }

    // MARK: - c. 記憶

    private var memoryMission: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch memoryPhase {
            case .showing:
                Text("この数字を覚えてください")
                    .font(Theme.label(17))
                    .foregroundStyle(Theme.ink)

                Text(memorySequence)
                    .font(Theme.display(72))
                    .kerning(4)
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.identity)

                Text("あと \(memoryRemaining) 秒")
                    .font(Theme.label(15))
                    .foregroundStyle(Theme.muted)

            case .answering:
                Text("さっきの \(difficulty.memoryDigits) 桁を入力してください")
                    .font(Theme.label(17))
                    .foregroundStyle(Theme.ink)

                answerField(keyboard: .numberPad, placeholder: "覚えた数字")

                if showWrongAnswer {
                    Text("違います。新しい数字を出しました。もう一度覚えてください。")
                        .font(Theme.caption(13))
                        .foregroundStyle(Theme.alertRed)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - d. タイピング

    private var typingMission: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("この通りに打ってください")
                .font(Theme.label(17))
                .foregroundStyle(Theme.ink)

            Text(typingTarget)
                .font(Theme.display(56))
                .kerning(2)
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .textSelection(.disabled)

            answerField(keyboard: .asciiCapable, placeholder: "上の文字を入力")

            if showWrongAnswer {
                Text("違います。新しい文字に変えました。もう一度打ってください。")
                    .font(Theme.caption(13))
                    .foregroundStyle(Theme.alertRed)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 入力欄。計算・記憶・タイピングで見た目を揃える。
    private func answerField(keyboard: UIKeyboardType, placeholder: String) -> some View {
        TextField("", text: $input, prompt: Text(placeholder).foregroundStyle(Theme.muted))
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isInputFocused)
            .font(Theme.display(44))
            .foregroundStyle(Theme.ink)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .overlay {
                Rectangle().stroke(
                    showWrongAnswer ? Theme.alertRed : Theme.ink,
                    lineWidth: Theme.ruleBold
                )
            }
    }

    // MARK: - b. シェイク

    private var shakeMission: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("iPhone を \(requiredShakeCount) 回振ってください")
                .font(Theme.label(17))
                .foregroundStyle(Theme.ink)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(shakeDetector.count)")
                    .font(Theme.display(96))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: shakeDetector.count)
                Text("/ \(requiredShakeCount)")
                    .font(Theme.display(36))
                    .foregroundStyle(Theme.muted)
            }

            // 進捗＝システムの状態表示。青（操作・進行の色）で塗る。
            GeometryReader { geometry in
                let ratio = Double(min(shakeDetector.count, requiredShakeCount))
                    / Double(requiredShakeCount)
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.surface)
                    Rectangle()
                        .fill(Theme.blue)
                        .frame(width: geometry.size.width * ratio)
                        .animation(.snappy, value: shakeDetector.count)
                }
                .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.rule) }
            }
            .frame(height: 28)
            .accessibilityLabel("進捗 \(shakeDetector.count) / \(requiredShakeCount)")

            if shakeDetector.isUnavailable {
                StatusBlock(
                    title: "加速度センサーを使えません",
                    message: "この端末ではシェイクを検知できませんでした。計算ミッションに切り替えてください。",
                    accent: Theme.alertRed,
                    action: ("計算ミッションに切り替える", { switchToCalculation() })
                )
            }
        }
    }

    // MARK: - e. 歩く

    private var walkMission: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(requiredStepCount) 歩あるいてください")
                .font(Theme.label(17))
                .foregroundStyle(Theme.ink)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(stepDetector.count)")
                    .font(Theme.display(96))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: stepDetector.count)
                Text("/ \(requiredStepCount) 歩")
                    .font(Theme.display(36))
                    .foregroundStyle(Theme.muted)
            }

            progressBar(
                current: stepDetector.count,
                required: requiredStepCount,
                label: "歩数"
            )

            Text("iPhone を持って歩いてください。歩数は数秒遅れて反映されます。")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.muted)

            if stepDetector.isUnavailable {
                StatusBlock(
                    title: "歩数を取得できません",
                    message: "この端末では歩数を数えられませんでした。"
                        + "「モーションとフィットネス」が許可されているか確認するか、"
                        + "計算ミッションに切り替えてください。",
                    accent: Theme.alertRed,
                    action: ("計算ミッションに切り替える", { switchToCalculation() })
                )
            }
        }
    }

    /// 進捗のバー。シェイクと歩数で共通。
    private func progressBar(current: Int, required: Int, label: String) -> some View {
        GeometryReader { geometry in
            let ratio = Double(min(current, required)) / Double(max(1, required))
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.surface)
                Rectangle()
                    .fill(Theme.blue)
                    .frame(width: geometry.size.width * ratio)
                    .animation(.snappy, value: current)
            }
            .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.rule) }
        }
        .frame(height: 28)
        .accessibilityLabel("\(label)の進捗 \(current) / \(required)")
    }

    /// センサーが使えない端末のための逃げ道。クリア数は据え置いて計算に切り替える。
    private func switchToCalculation() {
        shakeDetector.stop()
        stepDetector.stop()
        problem = .random(ranges: difficulty.calculationRanges)
        input = ""
        showWrongAnswer = false
        kind = .calculation
        memoryRound += 1
        isInputFocused = true
    }
}
