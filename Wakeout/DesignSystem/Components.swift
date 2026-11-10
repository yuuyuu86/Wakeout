import SwiftUI
import UIKit

// MARK: - 罫線

/// ブロックを区切る水平の罫線。角丸も影も使わず、線だけで構造を作る。
struct Rule: View {
    var weight: CGFloat = Theme.rule

    var body: some View {
        Rectangle()
            .fill(Theme.ink)
            .frame(height: weight)
    }
}

// MARK: - ボタン

/// ボタンの意味。見た目ではなく役割で選ぶ。
enum BrutalRole {
    /// 主操作。青（操作できるものの色）。
    case primary
    /// 副操作。黒地。
    case secondary
    /// 破壊的・注意を要する操作。
    case destructive

    var background: Color {
        switch self {
        case .primary: Theme.blue
        case .secondary: Theme.ink
        case .destructive: Theme.alertRed
        }
    }
}

/// 全幅・角丸なし・押下時に沈むボタン。タップ領域は最低 56pt を確保する。
struct BrutalButtonStyle: ButtonStyle {
    var role: BrutalRole = .primary
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(19))
            .kerning(0.5)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(isEnabled ? role.background : Theme.muted)
            .overlay(alignment: .top) { Rule() }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

// MARK: - 見出し

/// セクションの見出し。大文字＋字間で「区切り」を作る。
struct SectionHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.label(13))
            .kerning(1.5)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 12)
            .background(Theme.paper)
    }
}

// MARK: - バッジ

/// 状態や属性を表す小さな箱。色だけに頼らないよう必ず文字を持つ。
struct Badge: View {
    let text: String
    var filled: Bool = true
    var tint: Color = Theme.ink

    var body: some View {
        Text(text)
            .font(Theme.caption(12))
            .kerning(0.5)
            .foregroundStyle(filled ? .white : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(filled ? tint : .clear)
            .overlay {
                Rectangle().stroke(tint, lineWidth: Theme.rule)
            }
    }
}

// MARK: - トグル

/// 角丸のない ON/OFF スイッチ。
///
/// 標準の `Toggle` はカプセル型で角丸が固定なので、この画面言語には使わない。
/// ON は青（＝操作された状態）。色だけに頼らないよう、呼び出し側で ON/OFF の文字も併記する。
struct SquareToggle: View {
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Button {
            onChange(!isOn)
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Rectangle()
                    .fill(isOn ? Theme.blue : Theme.surface)
                Rectangle()
                    .fill(isOn ? Color.white : Theme.ink)
                    .frame(width: 24, height: 24)
                    .padding(4)
            }
            .frame(width: 60, height: 34)
            .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.rule) }
            // タップ領域は 44pt 以上を確保する
            .frame(minWidth: 60, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: isOn)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "オン" : "オフ")
    }
}

// MARK: - 時刻ピッカー

/// 時・分のホイール。
///
/// 標準の `DatePicker` / SwiftUI の `.wheel` ピッカーは
/// フォントを差し替えられず、選択行のハイライトも角丸カプセルで固定される。
/// この画面言語には合わないので `UIPickerView` を直接ラップし、
/// フォントを揃え、選択帯は自前の四角い枠で描いている。
struct SquareTimePicker: View {
    @Binding var hour: Int
    @Binding var minute: Int

    /// 選択行の高さ。UIPickerView の rowHeight と揃える。
    private let rowHeight: CGFloat = 62

    var body: some View {
        HStack(spacing: 0) {
            NumberWheel(selection: $hour, count: 24, rowHeight: rowHeight)
                .accessibilityLabel("時")
            Text(":")
                .font(Theme.display(46))
                .foregroundStyle(Theme.ink)
            NumberWheel(selection: $minute, count: 60, rowHeight: rowHeight)
                .accessibilityLabel("分")
        }
        .frame(height: 186)
        // 選択行を示す帯。画面幅いっぱいに引くので上下の罫線だけにする
        // （左右に縦線を入れると画面端で切れて見える）。
        .overlay {
            VStack(spacing: 0) {
                Rule()
                Spacer(minLength: 0)
                Rule()
            }
            .frame(height: rowHeight)
            .allowsHitTesting(false)
        }
    }
}

/// `UIPickerView` の薄いラッパ。00〜count-1 をゼロ埋めで表示する。
private struct NumberWheel: UIViewRepresentable {
    @Binding var selection: Int
    let count: Int
    let rowHeight: CGFloat

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        picker.backgroundColor = .clear
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        picker.selectRow(selection, inComponent: 0, animated: false)
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.parent = self
        if picker.selectedRow(inComponent: 0) != selection {
            picker.selectRow(selection, inComponent: 0, animated: false)
        }
        // 選択行の角丸ハイライトはシステムが描画する。
        // 見た目を四角に統一するため背景を透明にする。
        // 内部構造に依存するので、見つからなくても何も壊れないようにしておく。
        for subview in picker.subviews where subview.bounds.height < rowHeight * 1.5 {
            subview.backgroundColor = .clear
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: NumberWheel

        init(_ parent: NumberWheel) { self.parent = parent }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            parent.count
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            parent.rowHeight
        }

        func pickerView(
            _ pickerView: UIPickerView,
            viewForRow row: Int,
            forComponent component: Int,
            reusing view: UIView?
        ) -> UIView {
            let label = view as? UILabel ?? UILabel()
            label.text = String(format: "%02d", row)
            label.textAlignment = .center
            // アプリ内の時刻表示と同じ極太コンデンス
            label.font = .systemFont(ofSize: 46, weight: .black, width: .compressed)
            label.textColor = .black
            return label
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            parent.selection = row
        }

        func pickerView(_ pickerView: UIPickerView, accessibilityLabelForComponent component: Int) -> String? {
            nil
        }
    }
}

// MARK: - スワイプ操作

/// スワイプで現れるアクション 1 つ分。
struct SwipeAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let tint: Color
    let handler: () -> Void
}

/// 左右スワイプでアクションを出せる行。
///
/// 標準の `List` + `swipeActions` は iOS 26 ではボタンが円形で描画され、
/// 形も余白も差し替えられないため、この画面言語には使えない。
/// ここでは行の横移動と四角いアクションを自前で描いている。
///
/// 操作は 2 段階。
/// - 少し引く → アクションが出る。タップで実行。
/// - 大きく引き切る → **指を離した時点でそのまま実行**（フルスワイプ）。
///
/// 縦スクロールと競合しないよう、ジェスチャは
/// **横移動が縦移動を上回ったときだけ**反応させている。
struct SwipeableRow<Content: View>: View {
    let id: UUID
    var leading: SwipeAction?
    var trailing: SwipeAction?
    /// 開いている行の ID。他の行が開いたら自分は閉じる。
    @Binding var openRowID: UUID?
    /// 行本体のタップ。
    ///
    /// 行の中に `Button` を置くとスワイプ中にタップも同時に成立してしまうため、
    /// タップはここで一括して受ける。`onTapGesture` は指が動くと自動的に外れるので、
    /// スワイプとタップが両立してしまうことがない。
    var onTap: (() -> Void)?
    @ViewBuilder var content: Content

    /// アクション 1 つ分の幅。タップ領域として十分な大きさを取る。
    private let actionWidth: CGFloat = 92
    /// これ以上引いたら開いたままにする距離。
    private let openThreshold: CGFloat = 44

    @State private var offset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    @State private var rowWidth: CGFloat = 0
    /// 指を離せばそのまま実行される位置まで引かれているか。
    @State private var willTriggerFullSwipe = false

    private var isOpen: Bool { offset != 0 }

    /// 引き切ったと見なす距離。行幅の約半分。
    private var fullSwipeThreshold: CGFloat {
        max(150, rowWidth * 0.45)
    }

    var body: some View {
        ZStack {
            actionLayer

            content
                .contentShape(Rectangle())
                .onTapGesture {
                    // 開いている間のタップは「閉じる」を優先する
                    if isOpen {
                        close()
                    } else {
                        onTap?()
                    }
                }
                .offset(x: offset)
        }
        .clipped()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 14, coordinateSpace: .local)
                .onChanged { value in
                    // 縦スクロール中は無視する
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    let proposed = dragStartOffset + value.translation.width
                    offset = clamp(proposed)
                    openRowID = id
                    willTriggerFullSwipe = action(for: offset) != nil
                        && abs(offset) >= fullSwipeThreshold
                }
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else {
                        settle(to: dragStartOffset)
                        return
                    }
                    let proposed = clamp(dragStartOffset + value.translation.width)
                    willTriggerFullSwipe = false

                    // 引き切っていたらタップを挟まずそのまま実行する
                    if abs(proposed) >= fullSwipeThreshold, let action = action(for: proposed) {
                        settle(to: 0)
                        action.handler()
                        return
                    }

                    if proposed > openThreshold, leading != nil {
                        settle(to: actionWidth)
                    } else if proposed < -openThreshold, trailing != nil {
                        settle(to: -actionWidth)
                    } else {
                        settle(to: 0)
                    }
                }
        )
        // 引き切った瞬間を指に返す（画面を見ずに操作していても分かるように）
        .sensoryFeedback(.impact(weight: .medium), trigger: willTriggerFullSwipe) { _, new in new }
        .onChange(of: openRowID) { _, newValue in
            if newValue != id, isOpen { close() }
        }
        // スワイプできない環境（VoiceOver 等）でも同じ操作に到達できるようにする
        .accessibilityActions {
            if let leading {
                Button(leading.title) { leading.handler() }
            }
            if let trailing {
                Button(trailing.title) { trailing.handler() }
            }
        }
    }

    // MARK: - 背面のアクション

    private var actionLayer: some View {
        HStack(spacing: 0) {
            if offset > 0, let leading {
                actionButton(leading)
                Spacer(minLength: 0)
            } else if offset < 0, let trailing {
                Spacer(minLength: 0)
                actionButton(trailing)
            }
        }
    }

    private func actionButton(_ action: SwipeAction) -> some View {
        Button {
            close()
            action.handler()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 20, weight: .bold))
                Text(action.title)
                    .font(Theme.caption(12))
            }
            .foregroundStyle(.white)
            // 引くほど広がる。引き切ると行全体を覆い、実行される状態だと分かる。
            .frame(width: max(actionWidth, abs(offset)))
            .frame(maxHeight: .infinity)
            .background(action.tint)
            .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.rule) }
        }
        .buttonStyle(.plain)
    }

    /// 現在の向きに対応するアクション。
    private func action(for value: CGFloat) -> SwipeAction? {
        if value > 0 { return leading }
        if value < 0 { return trailing }
        return nil
    }

    // MARK: - 開閉

    private func clamp(_ value: CGFloat) -> CGFloat {
        // フルスワイプできるよう、行幅いっぱいまで引けるようにする
        let limit = rowWidth > 0 ? rowWidth : actionWidth
        let upper = leading == nil ? 0 : limit
        let lower = trailing == nil ? 0 : -limit
        return min(max(value, lower), upper)
    }

    private func settle(to value: CGFloat) {
        withAnimation(.snappy(duration: 0.2)) { offset = value }
        dragStartOffset = value
        if value == 0, openRowID == id { openRowID = nil }
    }

    private func close() {
        settle(to: 0)
    }
}

// MARK: - 選択肢

/// 単一選択の行。サウンド選択のように選択肢が少ない場面で使う。
/// 標準の Picker（メニュー／角丸）を避け、四角い行として並べる。
struct SquareOptionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Theme.label(15))
                    .foregroundStyle(isSelected ? .white : Theme.ink)
                Spacer(minLength: 8)
                Text(isSelected ? "選択中" : "")
                    .font(Theme.caption(12))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(isSelected ? Theme.blue : Theme.surface)
            .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.rule) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - プルダウン

/// 選択肢が多くて `SquareOptionRow` を並べると画面が縦に伸びすぎる場面で使う。
///
/// 標準の `Picker(.menu)` は角丸のメニューで描画されるためこの画面言語に合わない。
/// ここでは「選択中の値を示す青いボタン」をタップすると、
/// 同じ列にすべての選択肢が展開される作りにしている。
/// 色の役割はそのまま踏襲する： 閉じたボタン＝操作できるもの（青）、
/// 開いた中の選択中の行＝操作できるもの（青）、未選択の行＝面を持たない白地。
struct SquareDropdown<Option: Identifiable>: View where Option.ID == String {
    let options: [Option]
    @Binding var selection: String
    let label: (Option) -> String
    /// 行の右にゴミ箱を出すかどうか。
    var isRemovable: (Option) -> Bool = { _ in false }
    var onRemove: ((Option) -> Void)?
    /// 選択時の追加処理（試聴など）。
    var onSelect: ((Option) -> Void)?

    @State private var isExpanded = false

    private var selectedLabel: String {
        options.first { $0.id == selection }.map(label) ?? selection
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedLabel)
                        .font(Theme.label(15))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(Theme.blue)
                .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.rule) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "タップして閉じる" : "タップして選択肢を開く")

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        row(for: option)
                        if index != options.count - 1 { Rule() }
                    }
                }
                .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.rule) }
                .overlay(alignment: .top) { Rule() }
                // ここで `.move(edge: .top)` を使ってはいけない。
                // 選択肢が自分の枠の外（＝押したボタンより上）から滑り込んでくる。
                // 位置は動かさず、下のマスクで下端から現す。
                .transition(.opacity)
            }
        }
        // 開閉に合わせて伸び縮みする自分の枠でマスクする。
        // 枠の下端が下りていくことで、選択肢がボタンの真下から現れる。
        //
        // 左右と上には枠をはみ出させている。罫線 (`stroke`) は境界の中心に引かれるので、
        // ぴったりのマスクだと外側の 1pt が欠けて線が細く見えるため。
        .mask(alignment: .top) {
            Rectangle()
                .padding(.horizontal, -Theme.rule)
                .padding(.top, -Theme.rule)
        }
    }

    @ViewBuilder
    private func row(for option: Option) -> some View {
        let isSelected = option.id == selection

        HStack(spacing: 0) {
            Button {
                selection = option.id
                onSelect?(option)
                withAnimation(.snappy(duration: 0.18)) { isExpanded = false }
            } label: {
                HStack(spacing: 8) {
                    Text(label(option))
                        .font(Theme.label(15))
                        .foregroundStyle(isSelected ? .white : Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(isSelected ? Theme.blue : Theme.surface)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            if isRemovable(option), let onRemove {
                Button {
                    onRemove(option)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.alertRed)
                        .frame(width: 52, height: 52)
                        .background(Theme.surface)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Theme.ink).frame(width: Theme.rule)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label(option)) を削除")
            }
        }
    }
}

// MARK: - 状態表示

/// 空状態・エラー状態で共通に使う枠。
struct StatusBlock: View {
    let title: String
    let message: String
    var accent: Color = Theme.ink
    var action: (title: String, handler: () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.label(16))
                .foregroundStyle(Theme.ink)

            Text(message)
                .font(Theme.caption(13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if let action {
                Button(action.title, action: action.handler)
                    .font(Theme.label(14))
                    .foregroundStyle(Theme.blue)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .background(Theme.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(accent).frame(width: 6)
        }
        .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.rule) }
    }
}

// MARK: - 長押しで確定

/// 押し続けてはじめて実行されるボタン。
///
/// 寝ぼけたまま偶然押せてしまってはいけない操作に使う。
/// ミッションのような頭を使う課題は課さない（起き抜けの認知課題は苦痛で、
/// ソフト起床の趣旨に反する）が、指が触れただけでは通さない。
///
/// 進捗は面で見せる。あと何秒押し続ければよいか分からないと、途中で指を離してしまう。
struct HoldToConfirmButton: View {
    let title: String
    /// 押し続ける必要のある秒数。
    var duration: TimeInterval = 2.5
    let action: () -> Void

    @State private var progress: Double = 0
    @State private var isHolding = false
    @State private var completion: Task<Void, Never>?
    /// 確定した回数。触覚フィードバックの引き金にする。
    @State private var completedCount = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Theme.surface
                // 進捗の面。acid（＝作動中の状態）なので、文字は黒のまま読める。
                Theme.acid.frame(width: proxy.size.width * progress)

                HStack(spacing: 8) {
                    Image(systemName: isHolding ? "hand.tap.fill" : "hand.tap")
                    Text(isHolding ? "そのまま押し続ける" : title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(Theme.label(15))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
            }
            .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.rule) }
        }
        .frame(height: 64)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginHolding() }
                .onEnded { _ in cancelHolding() }
        )
        .sensoryFeedback(.success, trigger: completedCount)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityHint("\(Int(duration))秒ほど押し続けると実行します。")
        // 長押しは VoiceOver では扱えないので、1 操作で実行できる道も残す。
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { complete() }
    }

    private func beginHolding() {
        guard !isHolding else { return }
        isHolding = true
        withAnimation(.linear(duration: duration)) { progress = 1 }
        completion = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            complete()
        }
    }

    private func cancelHolding() {
        completion?.cancel()
        completion = nil
        guard isHolding else { return }
        isHolding = false
        // 戻りは速くする。途中で離したことが、指を離した瞬間に分かるように。
        withAnimation(.snappy(duration: 0.2)) { progress = 0 }
    }

    private func complete() {
        completion?.cancel()
        completion = nil
        isHolding = false
        progress = 0
        completedCount += 1
        action()
    }
}
