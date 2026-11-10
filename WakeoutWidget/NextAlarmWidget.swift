import SwiftUI
import WidgetKit

// MARK: - タイムライン

struct NextAlarmEntry: TimelineEntry {
    let date: Date
    /// 次に鳴るアラーム。全部 OFF / 未登録なら nil。
    let alarm: AlarmSnapshot?
    let fireDate: Date?

    static let placeholder = NextAlarmEntry(
        date: Date(),
        alarm: AlarmSnapshot(
            id: UUID(),
            hour: 6,
            minute: 30,
            repeatDaysMask: 0b0111110, // 月〜金
            label: "起きる",
            isEnabled: true
        ),
        fireDate: Date().addingTimeInterval(8 * 3600)
    )
}

struct NextAlarmProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextAlarmEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (NextAlarmEntry) -> Void) {
        completion(context.isPreview ? .placeholder : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextAlarmEntry>) -> Void) {
        let entry = currentEntry()

        // 経過時間の表示は `Text(_:style:)` がシステム側で自動更新するため、
        // タイムラインを細かく刻む必要はない。
        // 発火時刻を過ぎたら「次の1件」が変わるので、そこで必ず作り直す。
        let fallback = Date().addingTimeInterval(60 * 60)
        let reloadDate = [entry.fireDate?.addingTimeInterval(60), fallback]
            .compactMap { $0 }
            .min() ?? fallback

        completion(Timeline(entries: [entry], policy: .after(reloadDate)))
    }

    private func currentEntry() -> NextAlarmEntry {
        let now = Date()
        guard let next = AlarmSnapshotStore.load().nextToFire(from: now) else {
            return NextAlarmEntry(date: now, alarm: nil, fireDate: nil)
        }
        return NextAlarmEntry(date: now, alarm: next.alarm, fireDate: next.date)
    }
}

// MARK: - ウィジェット定義

struct NextAlarmWidget: Widget {
    private let kind = "WakeoutNextAlarm"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextAlarmProvider()) { entry in
            NextAlarmWidgetView(entry: entry)
        }
        .configurationDisplayName("次のアラーム")
        .description("次に鳴るアラームの時刻を表示します。")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline,
        ])
    }
}

// MARK: - 表示

struct NextAlarmWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextAlarmEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            inlineView
                .containerBackground(.clear, for: .widget)
        case .accessoryCircular:
            circularView
                .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            rectangularView
                .containerBackground(.clear, for: .widget)
        case .systemMedium:
            mediumView
                .containerBackground(Theme.acid, for: .widget)
        default:
            smallView
                .containerBackground(Theme.acid, for: .widget)
        }
    }

    // MARK: ホーム画面（小）

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("次に鳴る")
                .font(Theme.label(11))
                .kerning(1.2)
                .foregroundStyle(Theme.ink)

            Spacer(minLength: 4)

            if let alarm = entry.alarm {
                Text(alarm.timeText)
                    .font(Theme.display(48))
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text(alarm.repeatText)
                    .font(Theme.caption(12))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            } else {
                Text("なし")
                    .font(Theme.display(40))
                    .foregroundStyle(Theme.ink)
                Text("アラーム未設定")
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.ink.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(entry.alarm == nil ? "WAKEOUT" : "ミッションで解除")
                .font(Theme.caption(10))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Theme.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: ホーム画面（中）

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("次に鳴る")
                    .font(Theme.label(11))
                    .kerning(1.2)
                    .foregroundStyle(Theme.ink)

                Text(entry.alarm?.timeText ?? "--:--")
                    .font(Theme.display(56))
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                if let fireDate = entry.fireDate {
                    Text(fireDate, style: .relative)
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                } else {
                    Text("アラーム未設定")
                        .font(Theme.caption(12))
                        .foregroundStyle(Theme.ink.opacity(0.7))
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                if let alarm = entry.alarm {
                    Text(alarm.label.isEmpty ? "ラベルなし" : alarm.label)
                        .font(Theme.label(14))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.ink)

                    Text(alarm.repeatText)
                        .font(Theme.label(14))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay { Rectangle().stroke(Theme.ink, lineWidth: 2) }
                }
            }
            .frame(width: 130)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: ロック画面

    /// ロック画面のウィジェットは単色でレンダリングされるため、
    /// 色に頼らず文字の大小と配置だけで情報の優先順位を作る。
    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("次のアラーム")
                .font(.system(size: 11, weight: .semibold))
                .widgetAccentable()

            if let alarm = entry.alarm {
                Text(alarm.timeText)
                    .font(.system(size: 24, weight: .black).width(.compressed))
                Text(alarm.repeatText)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            } else {
                Text("未設定")
                    .font(.system(size: 24, weight: .black).width(.compressed))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var circularView: some View {
        VStack(spacing: -2) {
            Image(systemName: "alarm.fill")
                .font(.system(size: 11))
                .widgetAccentable()
            Text(entry.alarm?.timeText ?? "--:--")
                .font(.system(size: 15, weight: .black).width(.compressed))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }

    private var inlineView: some View {
        Text(entry.alarm.map { "\($0.timeText) \($0.repeatText)" } ?? "アラーム未設定")
    }
}
