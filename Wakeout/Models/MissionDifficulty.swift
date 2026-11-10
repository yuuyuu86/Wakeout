import Foundation

/// ミッションの難易度。計算問題の桁数とシェイクの必要回数を一括で決める。
///
/// 個別に「計算は難しく、シェイクは簡単に」のような組み合わせは選べないようにしてある。
/// 選択肢を増やすほど編集画面が長くなる、という以前の反省を踏まえての判断。
enum MissionDifficulty: Int, CaseIterable, Identifiable {
    case easy = 0
    case normal = 1
    case hard = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .easy: "やさしい"
        case .normal: "ふつう"
        case .hard: "むずかしい"
        }
    }

    /// 計算ミッションの乗数の範囲（左項・右項）。
    var calculationRanges: (lhs: ClosedRange<Int>, rhs: ClosedRange<Int>) {
        switch self {
        case .easy: (2...9, 2...9)
        case .normal: (11...99, 11...99)
        case .hard: (11...99, 100...999)
        }
    }

    /// シェイクミッションで要求する回数。
    var requiredShakeCount: Int {
        switch self {
        case .easy: 8
        case .normal: 15
        case .hard: 25
        }
    }

    /// 記憶ミッションで覚えさせる桁数。
    var memoryDigits: Int {
        switch self {
        case .easy: 4
        case .normal: 6
        case .hard: 8
        }
    }

    /// 記憶ミッションで数字を見せている秒数。
    ///
    /// 桁数が増えるほど見せる時間は短くする。長くすると難易度が上がらない。
    var memoryDisplaySeconds: Int {
        switch self {
        case .easy: 4
        case .normal: 3
        case .hard: 3
        }
    }

    /// タイピングミッションで打たせる文字数。
    var typingLength: Int {
        switch self {
        case .easy: 6
        case .normal: 10
        case .hard: 14
        }
    }

    /// 歩くミッションで要求する歩数。
    ///
    /// 布団から出て往復する程度を想定している。多すぎると諦めて放置されるので、
    /// 「起き上がって歩き出す」ところまでを狙う。
    var requiredStepCount: Int {
        switch self {
        case .easy: 15
        case .normal: 30
        case .hard: 50
        }
    }

    /// 停止までにクリアさせるミッションの数。
    ///
    /// 1 問だと、寝ぼけたまま偶然当たって二度寝する余地が残る。
    /// 1 問を難しくするより、続けて解かせるほうが覚醒には効く。
    var requiredMissionCount: Int {
        switch self {
        case .easy: 1
        case .normal: 2
        case .hard: 3
        }
    }
}
