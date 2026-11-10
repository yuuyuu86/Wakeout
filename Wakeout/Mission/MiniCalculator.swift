import SwiftUI

/// 電卓の計算部分。表示と状態遷移だけを持ち、画面には依存しない。
struct CalculatorEngine {
    enum Operation: String {
        case add = "+"
        case subtract = "−"
        case multiply = "×"
        case divide = "÷"

        func apply(_ lhs: Double, _ rhs: Double) -> Double {
            switch self {
            case .add: lhs + rhs
            case .subtract: lhs - rhs
            case .multiply: lhs * rhs
            case .divide: rhs == 0 ? 0 : lhs / rhs
            }
        }
    }

    private(set) var display = "0"
    /// 演算子を待っている左辺。
    private var lhs: Double?
    private var pendingOperation: Operation?
    /// 次の数字入力で表示を置き換えるか（演算子や = の直後）。
    private var replacesDisplay = true

    private var current: Double { Double(display) ?? 0 }

    mutating func input(digit: Int) {
        let text = String(digit)
        if replacesDisplay {
            display = text
            replacesDisplay = false
        } else if display == "0" {
            display = text
        } else if display.count < 12 {
            // 桁数を制限しないと表示が壊れる。
            display += text
        }
    }

    mutating func setOperation(_ operation: Operation) {
        // 演算子を続けて押したときは、計算せずに演算子だけ差し替える。
        if !replacesDisplay { resolve() }
        lhs = current
        pendingOperation = operation
        replacesDisplay = true
    }

    mutating func equals() {
        resolve()
        pendingOperation = nil
        lhs = nil
        replacesDisplay = true
    }

    mutating func clear() {
        display = "0"
        lhs = nil
        pendingOperation = nil
        replacesDisplay = true
    }

    private mutating func resolve() {
        guard let lhs, let pendingOperation else { return }
        display = Self.format(pendingOperation.apply(lhs, current))
    }

    /// 整数なら小数点を出さない。
    private static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(format: "%.4f", value)
    }
}

/// 計算ミッションの上に出す小さな電卓。
///
/// - Note: 暗算という関門は弱くなる。それでも数字を読み取って打ち込む必要はあるので、
///   目と手は使わせられる。使うかどうかはユーザーの選択に任せる。
struct MiniCalculator: View {
    /// 「答えに入れる」で解答欄へ渡す値。
    let onSubmit: (String) -> Void
    let onClose: () -> Void

    @State private var engine = CalculatorEngine()

    /// 1 行ぶんのキー。
    private let rows: [[Key]] = [
        [.digit(7), .digit(8), .digit(9), .operation(.divide)],
        [.digit(4), .digit(5), .digit(6), .operation(.multiply)],
        [.digit(1), .digit(2), .digit(3), .operation(.subtract)],
        [.digit(0), .clear, .equals, .operation(.add)],
    ]

    private enum Key: Hashable {
        case digit(Int)
        case operation(CalculatorEngine.Operation)
        case equals
        case clear

        var label: String {
            switch self {
            case .digit(let value): String(value)
            case .operation(let operation): operation.rawValue
            case .equals: "="
            case .clear: "C"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rule()

            Text(engine.display)
                .font(Theme.display(44))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.surface)

            Rule()

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(row, id: \.self) { key in
                            keyButton(key)
                        }
                    }
                }
            }

            Button("答えに入れる") { onSubmit(engine.display) }
                .font(Theme.label(15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.blue)
                .buttonStyle(.plain)
        }
        .background(Theme.surface)
        .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.ruleBold) }
    }

    private var header: some View {
        HStack {
            Text("電卓")
                .font(Theme.label(13))
                .kerning(1.5)
                .foregroundStyle(.white)
            Spacer()
            Button("閉じる") { onClose() }
                .font(Theme.label(13))
                .foregroundStyle(.white)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.ink)
    }

    private func keyButton(_ key: Key) -> some View {
        Button {
            press(key)
        } label: {
            Text(key.label)
                .font(Theme.label(20))
                .foregroundStyle(foreground(for: key))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(background(for: key))
                .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.rule) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 色の役割はアプリ全体と揃える。青＝操作、赤＝取り消し、白＝面を持たない。
    private func background(for key: Key) -> Color {
        switch key {
        case .operation, .equals: Theme.blue
        case .clear: Theme.alertRed
        case .digit: Theme.surface
        }
    }

    private func foreground(for key: Key) -> Color {
        switch key {
        case .digit: Theme.ink
        default: .white
        }
    }

    private func press(_ key: Key) {
        switch key {
        case .digit(let value): engine.input(digit: value)
        case .operation(let operation): engine.setOperation(operation)
        case .equals: engine.equals()
        case .clear: engine.clear()
        }
    }
}
