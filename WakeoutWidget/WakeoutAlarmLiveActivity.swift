import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

/// AlarmKit のアラート UI を成立させるための Live Activity 設定。
///
/// AlarmKit はアラート表示に ActivityKit を使うため、
/// `AlarmAttributes<Metadata>` を扱う `ActivityConfiguration` を持つ
/// Widget Extension がプロジェクトに存在することが必須要件になっている。
/// ここで指定する Metadata の型は、アプリ側でスケジュールするときの型と一致させること。
struct WakeoutAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<WakeoutAlarmMetadata>.self) { context in
            lockScreenView(context.attributes, state: context.state)
                .activityBackgroundTint(Theme.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(Theme.acid)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(for: context.attributes))
                            .font(Theme.label(16))
                            .foregroundStyle(Theme.acid)
                        Text(subtitle(for: context.state))
                            .font(Theme.caption(12))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(Theme.acid)
            } compactTrailing: {
                Text(title(for: context.attributes))
                    .font(Theme.label(13))
                    .lineLimit(1)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(Theme.acid)
            }
        }
    }

    /// ロック画面 / バナー。アプリ内と同じ「黒地 + アシッド」の言語で揃える。
    private func lockScreenView(
        _ attributes: AlarmAttributes<WakeoutAlarmMetadata>,
        state: AlarmPresentationState
    ) -> some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(Theme.acid)
                .frame(width: 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(title(for: attributes))
                    .font(Theme.title(26))
                    .foregroundStyle(Theme.acid)
                    .lineLimit(1)

                Text(subtitle(for: state))
                    .font(Theme.caption(12))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.vertical, 14)

            Spacer(minLength: 0)

            Image(systemName: "alarm.fill")
                .font(.title2)
                .foregroundStyle(Theme.acid)
                .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func title(for attributes: AlarmAttributes<WakeoutAlarmMetadata>) -> String {
        let label = attributes.metadata?.label ?? ""
        return label.isEmpty ? "WAKEOUT" : label
    }

    private func subtitle(for state: AlarmPresentationState) -> String {
        switch state.mode {
        case .alert:
            "ミッションをクリアするまで停止できません"
        case .countdown:
            "カウントダウン中"
        case .paused:
            "一時停止中"
        @unknown default:
            ""
        }
    }
}
