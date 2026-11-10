import SwiftUI

/// 起床の記録。まず「ならしてどうなのか」を統計で見せ、その下に 1 件ずつの記録を並べる。
struct WakeLogView: View {
    @Environment(\.dismiss) private var dismiss

    let entries: [WakeLogEntry]
    let records: WakeRecords
    /// 1 件削除。SwiftData の操作は呼び出し側に任せる。
    let onDelete: (WakeLogEntry) -> Void
    /// 全件削除。
    let onDeleteAll: () -> Void

    /// スワイプで開いている行。同時に開くのは 1 行だけ。
    @State private var openRowID: UUID?
    @State private var showDeleteAllConfirmation = false

    var body: some View {
        ZStack(alignment: .top) {
            Theme.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Rule(weight: Theme.ruleBold)

                if entries.isEmpty {
                    emptyState
                    Spacer(minLength: 0)
                } else {
                    // 集計はここで 1 度だけ行い、各セクションに配る。
                    let stats = WakeStats.make(entries: entries)
                    let achievements = AchievementCatalog.evaluate(entries: entries)

                    ScrollView {
                        VStack(spacing: 0) {
                            if records.currentStreak > 0 {
                                streakCard
                                Rule()
                            }

                            SectionHeading(text: "自己ベスト")
                            Rule()
                            bestRecords
                            Rule()

                            SectionHeading(
                                text: "実績 \(achievements.count(where: \.isUnlocked)) / \(achievements.count)"
                            )
                            Rule()
                            achievementGrid(achievements)
                            Rule()

                            SectionHeading(text: "この\(WakeStats.windowDays)日間")
                            Rule()
                            summary(stats)
                            Rule()

                            SectionHeading(text: "直近\(WakeStats.chartDays)日の起床時刻")
                            Rule()
                            chart(stats)
                            Rule()

                            SectionHeading(text: "すべての記録")
                            Rule()

                            ForEach(entries) { entry in
                                SwipeableRow(
                                    id: entry.id,
                                    trailing: SwipeAction(
                                        title: "削除",
                                        systemImage: "trash",
                                        tint: Theme.alertRed
                                    ) { onDelete(entry) },
                                    openRowID: $openRowID
                                ) {
                                    row(for: entry)
                                }
                                Rule()
                            }

                            Text("左スワイプで 1 件削除。引き切るとそのまま削除されます。")
                                .font(Theme.caption(12))
                                .foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Theme.screenPadding)
                                .padding(.vertical, 16)

                            deleteAllButton
                        }
                        .padding(.bottom, 40)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("起床の記録")
                .font(Theme.title(28))
                .foregroundStyle(Theme.ink)

            Spacer()

            Button("閉じる") { dismiss() }
                .font(Theme.label(15))
                .foregroundStyle(Theme.blue)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    /// 全消去。統計を作り直したいとき（テストで汚したときなど）に使う。
    private var deleteAllButton: some View {
        Button {
            showDeleteAllConfirmation = true
        } label: {
            Text("記録をすべて削除")
                .font(Theme.label(15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.alertRed)
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            "記録をすべて削除しますか？",
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("すべて削除する", role: .destructive) { onDeleteAll() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("\(entries.count) 件の記録と統計が消えます。この操作は取り消せません。")
        }
    }

    private var streakCard: some View {
        HStack(spacing: 8) {
            Text("連続\(records.currentStreak)日")
                .font(Theme.display(32))
                .foregroundStyle(Theme.ink)
            Text("ミッションをクリアして起床しています")
                .font(Theme.caption(12))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.acid)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("記録がまだありません")
                .font(Theme.label(17))
                .foregroundStyle(Theme.ink)
            Text("アラームを止めてミッションをクリアすると、ここに記録されます。")
                .font(Theme.caption(13))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.screenPadding)
    }

    // MARK: - 自己ベスト

    /// 更新を狙える一点もの。平均（この下の統計）とは役割を分けている。
    private var bestRecords: some View {
        HStack(spacing: 0) {
            summaryCell(
                value: WakeRecords.durationText(records.fastestDuration),
                caption: "最速突破",
                isLead: true
            )
            summaryCell(value: "\(records.longestStreak)日", caption: "最長の連続")
            summaryCell(value: "\(records.totalCount)回", caption: "通算の起床")
        }
        .background(Theme.surface)
    }

    // MARK: - 実績

    /// 未解除のものも同じ大きさで並べる。
    ///
    /// 取れたものだけを見せると「あと何があるのか」が分からず、次の目標にならない。
    /// 解除済みはアシッド、未解除はグレーで、色だけでなく日付の有無でも区別している。
    private func achievementGrid(_ achievements: [Achievement]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3),
            spacing: 0
        ) {
            ForEach(achievements) { achievementTile($0) }
        }
        .background(Theme.surface)
    }

    private func achievementTile(_ achievement: Achievement) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(achievement.title)
                .font(Theme.label(15))
                .foregroundStyle(achievement.isUnlocked ? Theme.ink : Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(achievement.requirement)
                .font(Theme.caption(10))
                .foregroundStyle(achievement.isUnlocked ? Theme.ink : Theme.muted)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            if let unlockedAt = achievement.unlockedAt {
                Text(unlockedAt, format: .dateTime.month().day())
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.ink)
            } else {
                Text("未解除")
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .padding(10)
        .background(achievement.isUnlocked ? Theme.acid : Theme.dim)
        .overlay { Rectangle().stroke(Theme.ink, lineWidth: Theme.rule) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(achievement.title)。\(achievement.requirement)。"
                + (achievement.isUnlocked ? "解除済み" : "未解除")
        )
    }

    // MARK: - 統計

    /// 平均起床時刻・記録日数・平均誤答を 3 分割で並べる。
    private func summary(_ stats: WakeStats) -> some View {
        HStack(spacing: 0) {
            summaryCell(
                value: stats.averageMinutes.map(WakeStats.timeText) ?? "--:--",
                caption: "平均起床時刻",
                isLead: true
            )
            summaryCell(value: "\(stats.sampleCount)日", caption: "起床した日数")
            summaryCell(
                value: String(format: "%.1f回", stats.averageWrongAttempts),
                caption: "1回あたり誤答"
            )
        }
        .background(Theme.surface)
    }

    private func summaryCell(value: String, caption: String, isLead: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                // 主役の数字だけ大きくして、視線が最初にここへ来るようにする。
                .font(Theme.display(isLead ? 34 : 26))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(Theme.caption(11))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .overlay(alignment: .leading) {
            if !isLead {
                Rectangle().fill(Theme.ink).frame(width: Theme.rule)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption) \(value)")
    }

    /// 直近 7 日の起床時刻を横軸（時刻）に並べたグラフ。
    ///
    /// 棒の長さではなく**位置**で時刻を表す。起床時刻は量ではないので、
    /// 「毎日どのあたりに揃っているか / ばらついているか」が読める形にしている。
    private func chart(_ stats: WakeStats) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                ForEach(stats.days) { day in
                    chartRow(day: day, stats: stats)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 18)

            axis(stats)
        }
        .background(Theme.surface)
    }

    private func chartRow(day: WakeStats.DayPoint, stats: WakeStats) -> some View {
        HStack(spacing: 10) {
            Text(day.date, format: .dateTime.weekday(.narrow))
                .font(Theme.label(12))
                .foregroundStyle(Theme.muted)
                .frame(width: 16, alignment: .leading)

            GeometryReader { proxy in
                let width = proxy.size.width
                let markerSize: CGFloat = 14

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.dim)
                        .frame(height: 2)
                        .frame(maxHeight: .infinity)

                    // 平均の位置。全行に引くことで縦のガイドになり、
                    // その日が平均より早いか遅いかが一目で分かる。
                    if let average = stats.averageMinutes,
                       let ratio = stats.position(of: average) {
                        Rectangle()
                            .fill(Theme.blue)
                            .frame(width: 2)
                            .offset(x: (width - 2) * ratio)
                    }

                    if let minutes = day.minutes, let ratio = stats.position(of: minutes) {
                        Rectangle()
                            .fill(Theme.ink)
                            .frame(width: markerSize, height: markerSize)
                            .offset(x: (width - markerSize) * ratio)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 16)

            Text(day.minutes.map(WakeStats.timeText) ?? "—")
                .font(Theme.label(12))
                .foregroundStyle(day.minutes == nil ? Theme.muted : Theme.ink)
                .frame(width: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            day.minutes.map { "\(WakeStats.timeText($0)) に起床" } ?? "記録なし"
        )
    }

    private func axis(_ stats: WakeStats) -> some View {
        HStack {
            Text(WakeStats.timeText(stats.windowStart))
            Spacer()
            if let average = stats.averageMinutes {
                HStack(spacing: 5) {
                    Rectangle()
                        .fill(Theme.blue)
                        .frame(width: 2, height: 10)
                    Text("平均 \(WakeStats.timeText(average))")
                }
            }
            Spacer()
            Text(WakeStats.timeText(stats.windowEnd))
        }
        .font(Theme.caption(11))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, Theme.screenPadding)
        .padding(.bottom, 14)
    }

    // MARK: - 1 件ずつの記録

    private func row(for entry: WakeLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.stoppedAt, format: .dateTime.month().day().weekday(.abbreviated))
                    .font(Theme.label(13))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(entry.stoppedAt, format: .dateTime.hour().minute())
                    .font(Theme.display(28))
                    .foregroundStyle(Theme.ink)
            }

            HStack(spacing: 8) {
                Text(entry.alarmLabel.isEmpty ? "ラベルなし" : entry.alarmLabel)
                    .font(Theme.label(14))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(missionKindText(entry.missionKind))
                    .font(Theme.caption(12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.ink)

                if entry.isSoftWake {
                    // ミッションを解いていないので、突破時間は出さない（常に 0 秒になる）。
                    Text("ミッションなし")
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.muted)
                } else if entry.wrongAttempts > 0 {
                    Text("誤答 \(entry.wrongAttempts)回")
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.alertRed)
                }

                if !entry.isSoftWake {
                    Text(durationText(entry.duration))
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.vertical, 14)
    }

    private func missionKindText(_ raw: String) -> String {
        switch raw {
        case "calculation": "計算"
        case "shake": "シェイク"
        case "memory": "記憶"
        case "typing": "タイピング"
        case "walk": "歩く"
        case WakeLogEntry.softWakeKind: "先行で起床"
        default: raw
        }
    }

    private func durationText(_ interval: TimeInterval) -> String {
        "\(WakeRecords.durationText(interval))で停止"
    }
}
