import SwiftUI

/// 取り込む音源の「どこを使うか」を決める画面。
///
/// 通知音は 30 秒未満でないと**無音になる**。先頭 30 秒を機械的に切ると、
/// 頭に無音や前奏がある音源では「鳴っているのに聞こえない」アラームになるため、
/// 使う範囲をユーザーに決めてもらう。
///
/// 波形の上ですべてを決める。
/// - **左右のつまみをドラッグ** → その端だけが動く（＝長さが変わる）
/// - それ以外をタップ／ドラッグ → 長さを保ったまま範囲ごと動く
///
/// つまみは選択範囲の**外側**に描く。内側に描くと、範囲が数 pt まで細くなったときに
/// 2 つが重なって前後が分からなくなる。
/// 役割は指を置いた瞬間に決めて離すまで変えない（掴んだものが手の中で入れ替わらないように）。
struct SoundTrimView: View {
    /// 取り込み元（作業用ディレクトリに複製済みのファイル）。
    let source: URL
    /// 保存名の元にする文字列（元のファイル名）。
    let originalName: String
    /// 取り込んだファイル名を返す。キャンセルなら nil。
    let onFinish: (String?) -> Void

    @State private var waveform: AudioWaveform?
    @State private var didFailToLoad = false
    @State private var startTime: TimeInterval = 0
    @State private var length: TimeInterval = SoundLibrary.maxDuration
    @State private var isScrubbing = false
    /// 選ばれたフェードインの長さ。実際に適用されるのは `effectiveFadeIn`。
    @State private var fadeIn: TimeInterval = SoundLibrary.defaultFadeIn
    @State private var errorMessage: String?
    /// いま指が何を動かしているか。指を置いた場所で決まり、離すまで変わらない。
    @State private var dragRole: DragRole?

    private enum DragRole {
        /// 始点のつまみ。
        case startEdge
        /// 終点のつまみ。
        case endEdge
        /// つまみ以外。長さを保ったまま範囲ごと動かす。
        case scrub
    }

    /// VoiceOver で範囲を動かすときの 1 手あたりの秒数。
    private static let accessibilityStep: TimeInterval = 1

    /// つまみの幅。指で掴める大きさを確保する。
    private static let gripWidth: CGFloat = 26
    /// つまみとして扱う判定の余裕。
    private static let gripSlop: CGFloat = 12

    private var duration: TimeInterval { waveform?.duration ?? 0 }

    /// 開始位置として取りうる最大。これ以上進めると範囲が末尾からはみ出す。
    private var maxStart: TimeInterval { max(0, duration - length) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Rule(weight: Theme.ruleBold)

                if didFailToLoad {
                    StatusBlock(
                        title: "この音源は読み込めませんでした",
                        message: "別のファイルを試してください。",
                        accent: Theme.alertRed
                    )
                    .padding(Theme.screenPadding)
                    Spacer(minLength: 0)
                } else if let waveform {
                    content(waveform)
                } else {
                    loading
                }
            }

            if waveform != nil {
                Button("この範囲で追加") { save() }
                    .buttonStyle(BrutalButtonStyle(role: .primary))
            }
        }
        .task { await loadWaveform() }
        .onDisappear { SoundPreviewPlayer.shared.stop() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("使う範囲を選ぶ")
                    .font(Theme.title(28))
                    .foregroundStyle(Theme.ink)
                Text(originalName)
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button("キャンセル") {
                SoundPreviewPlayer.shared.stop()
                onFinish(nil)
            }
            .font(Theme.label(15))
            .foregroundStyle(Theme.blue)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    /// 読み込み中。止まっているのか動いているのか分かるようにしておく。
    private var loading: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Theme.ink)
                Text("波形を読み込んでいます")
                    .font(Theme.label(15))
                    .foregroundStyle(Theme.ink)
            }
            Text("読み込めない形式のときは、そのまま知らせます。")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { Rule() }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func content(_ waveform: AudioWaveform) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                SectionHeading(text: "使う範囲")
                Rule()
                waveformSection(waveform)
                Rule()

                readout
                Rule()

                SectionHeading(text: "立ち上がり")
                Rule()
                fadeSection
                Rule()

                previewButton

                if let errorMessage {
                    StatusBlock(
                        title: "取り込めませんでした",
                        message: errorMessage,
                        accent: Theme.alertRed
                    )
                    .padding(Theme.screenPadding)
                }
            }
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - 波形と範囲選択

    private func waveformSection(_ waveform: AudioWaveform) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 調整の余地が無いのに「つまみで動かせる」と書くと、
            // 反応しない画面＝不具合に見える。状態に合わせて言うことを変える。
            Text(isAdjustable
                 ? "左右の青いつまみをドラッグして範囲を決めます。波形をタップすると、範囲ごとそこへ動きます。"
                 : "この音源は全体をそのまま使います。")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            waveformArea(waveform)

            Text("アラーム音は \(Int(SoundLibrary.maxDuration)) 秒未満にする必要があります。"
                 + "これより長いと、システムが無効な音源として扱って鳴りません。")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.screenPadding)
        .background(Theme.surface)
    }

    private func waveformArea(_ waveform: AudioWaveform) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            Canvas { context, size in
                draw(waveform, in: context, size: size)
            }
            .background(Theme.surface)
            .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.rule) }
            // 掴む場所は左右のつまみだけ。
            // それ以外はどこを触っても、範囲ごとそこへ動く。
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0, duration > 0 else { return }

                        // 役割は指を置いた瞬間に決める。
                        // 途中で切り替わると、掴んだものが手の中で入れ替わってしまう。
                        let role = dragRole ?? self.role(forTouchAt: value.startLocation.x, width: width)
                        dragRole = role

                        let time = min(max(Double(value.location.x / width), 0), 1) * duration
                        switch role {
                        case .startEdge:
                            // 終端は動かさない。始点だけを動かすので長さが変わる。
                            moveStartEdge(to: time)
                        case .endEdge:
                            moveEndEdge(to: time)
                        case .scrub:
                            // 長さを保ったまま範囲ごと動かす。
                            setStart(time)
                        }
                        isScrubbing = true
                    }
                    .onEnded { _ in
                        dragRole = nil
                        isScrubbing = false
                    }
            )
        }
        .frame(height: 150)
        // 指で動かしている手応えを返す（画面を見ながらでも位置が変わったと分かる）。
        .sensoryFeedback(.selection, trigger: Int(startTime + length))
        .accessibilityElement()
        .accessibilityLabel("使う範囲")
        .accessibilityValue("開始 \(timeText(startTime))、長さ \(String(format: "%.1f", length))秒")
        // つまみのドラッグは VoiceOver では扱えないので、
        // 位置は上下スワイプ、長さはカスタム操作で動かせるようにしておく。
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setStart(startTime + Self.accessibilityStep)
            case .decrement: setStart(startTime - Self.accessibilityStep)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "長さを1秒のばす") {
            moveEndEdge(to: startTime + length + Self.accessibilityStep)
        }
        .accessibilityAction(named: "長さを1秒ちぢめる") {
            moveEndEdge(to: startTime + length - Self.accessibilityStep)
        }
    }

    /// つまみを描く位置。選択範囲の**外側**に置く。
    ///
    /// 内側に置くと、範囲が細いときに 2 つが重なって前後が分からなくなる。
    /// 外側なら、範囲が 1pt まで細くなっても左右に並んだままになる。
    private func gripOrigins(width: CGFloat) -> (start: CGFloat, end: CGFloat) {
        let startX = CGFloat(startRatio) * width
        let endX = CGFloat(endRatio) * width
        return (
            start: max(0, startX - Self.gripWidth),
            end: min(width - Self.gripWidth, endX)
        )
    }

    /// 指を置いた位置から、何を動かすつもりなのかを決める。
    ///
    /// 描画位置ではなく**境界線からの距離**で判定する。
    /// つまみは線の外側に描かれるので、線を狙っても外側を狙っても掴めるようにするため。
    private func role(forTouchAt x: CGFloat, width: CGFloat) -> DragRole {
        guard isAdjustable else { return .scrub }

        let startX = CGFloat(startRatio) * width
        let endX = CGFloat(endRatio) * width
        let reach = Self.gripWidth + Self.gripSlop

        let startDistance = abs(x - startX)
        let endDistance = abs(x - endX)
        guard min(startDistance, endDistance) <= reach else { return .scrub }
        // 近いほうを掴んだとみなす。範囲が細くて両方が近いときも取り違えない。
        return startDistance <= endDistance ? .startEdge : .endEdge
    }

    private var startRatio: Double {
        duration > 0 ? min(1, startTime / duration) : 0
    }

    private var endRatio: Double {
        duration > 0 ? min(1, (startTime + length) / duration) : 1
    }

    /// 範囲を変えられるか。1 秒しかない音源などでは動かす余地が無い。
    private var isAdjustable: Bool {
        maxSelectableLength - minSelectableLength > 0.05
    }

    private func draw(_ waveform: AudioWaveform, in context: GraphicsContext, size: CGSize) {
        let count = waveform.samples.count
        guard count > 0, duration > 0 else { return }

        let barWidth = size.width / CGFloat(count)

        // 選択範囲の面。塗りつぶすことで「ここが使われる」と一目で分かるようにする。
        let selection = CGRect(
            x: CGFloat(startRatio) * size.width,
            y: 0,
            width: CGFloat(endRatio - startRatio) * size.width,
            height: size.height
        )
        context.fill(Path(selection), with: .color(Theme.blue.opacity(0.12)))

        // 無音部分の基準線。棒を最低の高さで描くと点線のように途切れて
        // 描画の不具合に見えるので、連続した線を 1 本先に引いておく。
        context.fill(
            Path(CGRect(x: 0, y: size.height / 2 - 0.5, width: size.width, height: 1)),
            with: .color(Theme.muted.opacity(0.35))
        )

        for (index, sample) in waveform.samples.enumerated() {
            let height = CGFloat(sample) * size.height * 0.9
            // 基準線より細いものは線に任せる。
            guard height > 1 else { continue }

            let ratio = Double(index) / Double(count)
            let isSelected = ratio >= startRatio && ratio < endRatio
            // 範囲の外も形は見せる。どこへ動かせばいいか分かるようにするため。
            let rect = CGRect(
                x: CGFloat(index) * barWidth,
                y: (size.height - height) / 2,
                width: max(1, barWidth - 1),
                height: height
            )
            context.fill(
                Path(rect),
                with: .color(isSelected ? Theme.ink : Theme.muted.opacity(0.28))
            )
        }

        // 範囲の境界線。
        let markerWidth: CGFloat = 3
        for ratio in [startRatio, endRatio] {
            let x = min(max(CGFloat(ratio) * size.width - markerWidth / 2, 0),
                        size.width - markerWidth)
            context.fill(
                Path(CGRect(x: x, y: 0, width: markerWidth, height: size.height)),
                with: .color(Theme.blue)
            )
        }

        // 左右のつまみ。掴めると分かる見た目にする。
        guard isAdjustable else { return }
        let origins = gripOrigins(width: size.width)
        for origin in [origins.start, origins.end] {
            context.fill(
                Path(CGRect(x: origin, y: 0, width: Self.gripWidth, height: size.height)),
                with: .color(Theme.blue)
            )
            // 掴む場所であることを示す 2 本の線。
            for offset in [Self.gripWidth / 3, Self.gripWidth * 2 / 3] {
                context.fill(
                    Path(CGRect(
                        x: origin + offset - 1,
                        y: size.height / 2 - 12,
                        width: 2,
                        height: 24
                    )),
                    with: .color(.white)
                )
            }
        }
    }

    // MARK: - 数値表示

    private var readout: some View {
        HStack(spacing: 0) {
            readoutCell(value: timeText(startTime), caption: "開始位置")
            readoutCell(
                value: String(format: "%.1f秒", length),
                caption: "長さ",
                isDivided: true
            )
            readoutCell(value: timeText(duration), caption: "元の長さ", isDivided: true)
        }
        .background(isScrubbing ? Theme.acid : Theme.surface)
        .animation(.snappy(duration: 0.15), value: isScrubbing)
    }

    private func readoutCell(value: String, caption: String, isDivided: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Theme.display(24))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(caption)
                .font(Theme.caption(11))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .overlay(alignment: .leading) {
            if isDivided {
                Rectangle().fill(Theme.ink).frame(width: Theme.rule)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption) \(value)")
    }

    /// 取りうる長さの下限・上限。
    private var minSelectableLength: TimeInterval {
        min(SoundLibrary.minDuration, maxSelectableLength)
    }
    private var maxSelectableLength: TimeInterval {
        min(duration, SoundLibrary.maxDuration)
    }

    // MARK: - 立ち上がり（フェードイン）

    /// 実際に適用されるフェードインの長さ。選んだ値より短くなることがある。
    private var effectiveFadeIn: TimeInterval {
        SoundLibrary.effectiveFadeIn(fadeIn, length: length)
    }

    /// 音の立ち上がりを選ぶ。
    ///
    /// 苦痛の大きさは音量そのものより**変化の急さ**で決まる。
    /// 静寂から爆音へ一息で飛ぶのをやめ、小さい音から上げていく。
    ///
    /// AlarmKit には音量を操作する API が無いので、
    /// 立ち上がりは取り込む波形に焼き込むしかない（`SoundLibrary.importSound`）。
    private var fadeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(SoundLibrary.fadeInOptions, id: \.self) { option in
                    fadeOptionButton(option)
                }
            }

            Text(fadeDescription)
                .font(Theme.caption(12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.screenPadding)
        .background(Theme.surface)
    }

    private func fadeOptionButton(_ option: TimeInterval) -> some View {
        let isSelected = fadeIn == option
        return Button {
            fadeIn = option
            // 選んだ立ち上がりは、聞いて確かめられないと選べない。
            SoundPreviewPlayer.shared.playRange(
                of: source,
                from: startTime,
                duration: length,
                fadeIn: SoundLibrary.effectiveFadeIn(option, length: length)
            )
        } label: {
            Text(fadeLabel(option))
                .font(Theme.label(15))
                .foregroundStyle(isSelected ? .white : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(isSelected ? Theme.blue : Theme.surface)
                .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.rule) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option == 0 ? "フェードなし" : "\(Int(option))秒で立ち上げる")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func fadeLabel(_ option: TimeInterval) -> String {
        option == 0 ? "なし" : "\(Int(option))秒"
    }

    private var fadeDescription: String {
        guard fadeIn > 0 else {
            return "先頭から最大音量で鳴ります。確実に起きたいときはこちら。"
        }
        let applied = effectiveFadeIn
        var text = "\(String(format: "%.1f", applied))秒かけて、"
            + "ようやく聞こえる音量から最大まで上げます。"
        if applied < fadeIn {
            // 選んだとおりにならない場合は、その理由まで言う。
            text += "（選んだ範囲が短いので、長さの半分までに縮めています）"
        }
        text += "アラーム音はシステムがループ再生するので、後半は最大音量のまま残します。"
        return text
    }

    private var previewButton: some View {
        Button {
            SoundPreviewPlayer.shared.playRange(
                of: source,
                from: startTime,
                duration: length,
                fadeIn: effectiveFadeIn
            )
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                Text("選んだ範囲を試聴")
            }
            .font(Theme.label(15))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.ink)
        }
        .buttonStyle(.plain)
    }

    private func timeText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - 操作

    private func setStart(_ value: TimeInterval) {
        startTime = min(max(value, 0), maxStart)
    }

    /// 始点だけを動かす。終点は動かさないので長さが変わる。
    private func moveStartEdge(to value: TimeInterval) {
        let end = startTime + length
        // 長さの下限・上限は、動かさない側（終点）を基準に決まる。
        let lower = max(0, end - maxSelectableLength)
        let upper = end - minSelectableLength
        let newStart = rounded(min(max(value, lower), max(lower, upper)))
        startTime = newStart
        length = end - newStart
    }

    /// 終点だけを動かす。始点は動かさないので長さが変わる。
    private func moveEndEdge(to value: TimeInterval) {
        let lower = startTime + minSelectableLength
        let upper = min(duration, startTime + maxSelectableLength)
        let newEnd = rounded(min(max(value, lower), max(lower, upper)))
        length = newEnd - startTime
    }

    /// 0.1 秒きざみに丸める。
    /// ドラッグで細かすぎる値になっても、表示と実際に切り出される範囲が食い違わないようにする。
    private func rounded(_ value: TimeInterval) -> TimeInterval {
        (value * 10).rounded() / 10
    }

    // MARK: - 処理

    private func loadWaveform() async {
        let url = source
        let loaded = await Task.detached(priority: .userInitiated) {
            AudioWaveform.load(from: url)
        }.value

        guard let loaded else {
            didFailToLoad = true
            return
        }
        waveform = loaded
        // 初期値は先頭から上限まで。上限に満たない音源は全体を使う。
        length = min(loaded.duration, SoundLibrary.maxDuration)
        startTime = 0
    }

    private func save() {
        SoundPreviewPlayer.shared.stop()
        errorMessage = nil
        do {
            let fileName = try SoundLibrary.importSound(
                from: source,
                startTime: startTime,
                duration: length,
                fadeIn: fadeIn,
                name: originalName
            )
            onFinish(fileName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
