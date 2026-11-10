import SwiftUI

/// アプリ全体の見た目の定義。
///
/// 色は「役割」で固定する。見た目の好みで使い分けない。
/// - `acid`  : 有効／作動中の**状態**を表す面。必ず `ink` の文字を載せる。
/// - `blue`  : ユーザーが**操作できる**もの（CTA・選択中・進捗）。必ず白文字を載せる。
/// - `ink`   : 文字と罫線。
/// - `dawn`  : ミッションが始まった直後の地。`acid` へ移っていく途中の色でしかない。
///
/// 状態を色だけで伝えないよう、ON/OFF は必ず文字ラベルも併記すること。
enum Theme {

    // MARK: - 色

    /// 有効状態の面。黒文字とのコントラスト比 約17:1。
    static let acid = Color(hex: 0xE3FF00)
    /// 文字・罫線。
    static let ink = Color(hex: 0x0A0A0A)
    /// 操作できるもの。白文字とのコントラスト比 約7:1（WCAG AA 準拠）。
    static let blue = Color(hex: 0x0037FF)
    /// ミッション開始直後の地。`acid` へ移行する途中の色で、これ単体では使わない。
    ///
    /// 起き抜けの目に高色温度の面をぶつけると眩しさが先に立つので、暖色から始める。
    /// `acid` と同じく明るい面なので、`ink` の文字を載せたまま読める
    /// （`ink` とのコントラスト比 約11:1）。
    static let dawn = Color(hex: 0xFFB24D)
    /// 画面の地。
    static let paper = Color(hex: 0xF2F2F0)
    /// カードなどの面。
    static let surface = Color.white
    /// 補足テキスト。paper 上でコントラスト比 約5.8:1。
    static let muted = Color(hex: 0x5E5E5A)
    /// 無効状態の面。
    static let dim = Color(hex: 0xE4E4E1)
    /// エラー。
    static let alertRed = Color(hex: 0xD1002E)

    // MARK: - 線

    /// 標準の罫線幅。ブロックの境界に使う。
    static let rule: CGFloat = 2
    /// 強調したい境界の線幅。
    static let ruleBold: CGFloat = 3

    // MARK: - 余白

    /// 画面端の余白。
    static let screenPadding: CGFloat = 20
    /// カード内側の余白。
    static let cardPadding: CGFloat = 20
    /// セクション間の余白。
    static let sectionGap: CGFloat = 24

    // MARK: - 文字

    /// 時刻表示などの極太コンデンス。
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.compressed)
    }

    /// 画面タイトル。大文字＋字間詰めで使う。
    static func title(_ size: CGFloat = 30) -> Font {
        .system(size: size, weight: .black).width(.compressed)
    }

    /// 見出し・ボタンラベル。
    static func label(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .heavy)
    }

    /// 補足。
    static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .medium)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
