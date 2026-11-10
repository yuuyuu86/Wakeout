import UIKit

/// ミッションの間だけ画面を明るくする。
///
/// 光は覚醒に直接効く。暗い部屋で暗い画面を見ていると二度寝しやすい。
///
/// ただし**一息で最大にはしない**。暗順応した目に 1.0 の白面をぶつけると、
/// 眩しさで目を閉じてしまい、覚醒どころか画面を見られなくなる。
/// `rampDuration` かけて今の明るさから上げていく（日の出に合わせる）。
///
/// - Important: 元の明るさに**必ず戻す**こと。戻さないと、ユーザーは
///   自分で設定を変えるまで眩しい画面のままになる。
@MainActor
enum ScreenBrightness {

    /// 最大の明るさに到達するまでの時間。
    ///
    /// ミッション画面の地の色もこの時間で暖色から `Theme.acid` へ移す。
    /// 光と色を別の速さで動かすと、ちらついて見える。
    static let rampDuration: TimeInterval = 20

    /// 明るさを変える間隔。これより細かくしても見た目は変わらず、更新だけが増える。
    private static let step: TimeInterval = 1.0 / 20

    /// 変更前の明るさ。変更していなければ nil。
    ///
    /// 二重に呼ばれても最初の値を失わないよう、既に保存済みなら上書きしない。
    private static var saved: CGFloat?

    /// 進行中のランプ。`restore()` と次の `maximize()` で必ず取り消す。
    private static var ramp: Task<Void, Never>?

    /// 今の明るさから最大まで、`rampDuration` かけて上げる。
    static func maximize() {
        guard AppSettings.shared.isMissionBrightnessEnabled else { return }
        guard let screen else { return }

        let from = screen.brightness
        if saved == nil { saved = from }

        // すでに最大なら動かすものが無い。
        guard from < 1 else { return }

        ramp?.cancel()
        ramp = Task {
            let steps = max(1, Int(rampDuration / step))
            for index in 1...steps {
                try? await Task.sleep(for: .seconds(step))
                guard !Task.isCancelled, let screen = self.screen else { return }
                let progress = Double(index) / Double(steps)
                screen.brightness = from + (1 - from) * curve(progress)
            }
        }
    }

    static func restore() {
        ramp?.cancel()
        ramp = nil
        guard let screen, let saved else { return }
        screen.brightness = saved
        self.saved = nil
    }

    /// 明るさの上がり方。
    ///
    /// 直線で上げると序盤がもう眩しい。はじめをゆるく、終盤で一気に上げる
    /// （目が慣れてくるほど、同じ差でも眩しく感じなくなる）。
    private static func curve(_ progress: Double) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        return CGFloat(clamped * clamped)
    }

    /// 表示中の画面。`UIScreen.main` は将来の複数画面構成で意味が曖昧になるため使わない。
    private static var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .screen
    }
}
