import Foundation

/// 実績 1 つぶん。
struct Achievement: Identifiable, Equatable {
    let id: String
    /// 表示名。
    let title: String
    /// 解除の条件。**未解除でも必ず見せる**（何をすれば取れるか分からない実績は目標にならない）。
    let requirement: String
    /// 解除した日時。未解除なら nil。
    let unlockedAt: Date?

    var isUnlocked: Bool { unlockedAt != nil }
}

/// 実績の一覧と判定。
///
/// 判定はすべて `WakeProgress` の値だけを見る純粋な関数にしてある。
/// 記録が消えれば実績も消える（別途保存しない）ので、
/// 「記録を全削除したのにバッジだけ残る」という食い違いが起きない。
enum AchievementCatalog {
    /// 判定の中身は状態を持たない純粋な関数なので、`Sendable` にして
    /// 定義そのものを `static let` で共有できるようにしている。
    struct Definition: Sendable {
        let id: String
        let title: String
        let requirement: String
        let isSatisfied: @Sendable (WakeProgress) -> Bool
    }

    /// 「全制覇」の判定に使うミッションの種類。`MissionKind.logIdentifier` と揃える。
    static let allMissionKinds: Set<String> = ["calculation", "shake", "memory", "typing", "walk"]

    /// 3 列で並べる想定で 12 個。
    ///
    /// 数を稼ぐだけのものは入れていない。伸ばす方向を
    /// 「回数」「連続」「早さ」「正確さ」「幅」の 5 つに散らし、
    /// どれか 1 つが苦手でも他で埋められるようにしてある。
    static let all: [Definition] = [
        Definition(id: "first", title: "初日", requirement: "ミッションをクリアして起きる") {
            $0.total >= 1
        },
        Definition(id: "count10", title: "10回", requirement: "通算 10 回起きる") {
            $0.total >= 10
        },
        Definition(id: "count50", title: "50回", requirement: "通算 50 回起きる") {
            $0.total >= 50
        },
        Definition(id: "count100", title: "100回", requirement: "通算 100 回起きる") {
            $0.total >= 100
        },
        Definition(id: "streak3", title: "3日連続", requirement: "3 日続けて起きる") {
            $0.longestStreak >= 3
        },
        Definition(id: "streak7", title: "7日連続", requirement: "7 日続けて起きる") {
            $0.longestStreak >= 7
        },
        Definition(id: "streak30", title: "30日連続", requirement: "30 日続けて起きる") {
            $0.longestStreak >= 30
        },
        Definition(id: "dawn", title: "夜明け前", requirement: "5 時台までに起きる") {
            ($0.earliestMinutes ?? .max) < 6 * 60
        },
        Definition(id: "quick", title: "速攻", requirement: "60 秒以内に突破する") {
            ($0.fastestDuration ?? .greatestFiniteMagnitude) <= 60
        },
        Definition(id: "instant", title: "瞬殺", requirement: "30 秒以内に突破する") {
            ($0.fastestDuration ?? .greatestFiniteMagnitude) <= 30
        },
        Definition(id: "flawless", title: "無傷", requirement: "誤答ゼロで 10 回突破する") {
            $0.flawlessCount >= 10
        },
        Definition(id: "allKinds", title: "全制覇", requirement: "5 種類すべてのミッションを突破する") {
            allMissionKinds.isSubset(of: $0.kinds)
        },
    ]

    /// 記録から実績の解除状況を求める。
    ///
    /// 古い順に 1 件ずつ積み上げ、**条件を初めて満たした記録の時刻**を解除日時にする。
    /// 後から記録を消すと解除日時も繰り上がるが、それは記録が正であるという方針どおり。
    static func evaluate(entries: [WakeLogEntry], calendar: Calendar = .current) -> [Achievement] {
        var progress = WakeProgress()
        var unlockedAt: [String: Date] = [:]

        for entry in entries.sorted(by: { $0.stoppedAt < $1.stoppedAt }) {
            progress.add(entry, calendar: calendar)
            for definition in all where unlockedAt[definition.id] == nil {
                if definition.isSatisfied(progress) {
                    unlockedAt[definition.id] = entry.stoppedAt
                }
            }
        }

        return all.map { definition in
            Achievement(
                id: definition.id,
                title: definition.title,
                requirement: definition.requirement,
                unlockedAt: unlockedAt[definition.id]
            )
        }
    }

    /// `entries` に 1 件加わったことで新しく解除された実績。祝いの画面で使う。
    static func newlyUnlocked(
        before: [WakeLogEntry],
        after: [WakeLogEntry],
        calendar: Calendar = .current
    ) -> [Achievement] {
        let known = Set(
            evaluate(entries: before, calendar: calendar).filter(\.isUnlocked).map(\.id)
        )
        return evaluate(entries: after, calendar: calendar)
            .filter { $0.isUnlocked && !known.contains($0.id) }
    }
}
