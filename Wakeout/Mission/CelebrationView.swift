import SwiftUI

/// ミッションを突破した 1 回分の結果。祝いの画面に渡す。
struct WakeCelebration: Identifiable, Equatable {
    /// 止めたアラームの ID。
    let id: String
    /// 鳴ってから止めるまでにかかった時間。
    let duration: TimeInterval
    /// これまでの最速を更新したか。
    ///
    /// **初回は更新扱いにしない。** 比べる相手が無いだけなので、
    /// ここで「自己ベスト更新」と出すとその後の本当の更新が安っぽくなる。
    let isFastestRecord: Bool
    let records: WakeRecords
    /// この 1 回で解除された実績の名前。
    let unlockedTitles: [String]
}

/// ミッションを突破した直後に出す画面。
///
/// ミッション画面はアシッドイエローなので、ここは黒で反転させる。
/// 同じ色のまま数字だけ差し替えても「終わった」ことが伝わらない。
///
/// 演出はここにだけ置く。鳴っている最中の画面に楽しい要素を混ぜると、
/// 「クリアするまで止まらない」という関門そのものが緩む。
struct CelebrationView: View {
    let result: WakeCelebration
    let onClose: () -> Void

    /// 表示直後に一度だけ動かすためのフラグ。
    @State private var hasAppeared = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.ink.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    headline
                    breakthroughTime
                    recordRow
                    if !result.unlockedTitles.isEmpty {
                        unlockedBlock
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 56)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)

            Button("閉じる") { onClose() }
                .buttonStyle(BrutalButtonStyle(role: .primary))
        }
        .onAppear {
            withAnimation(.snappy(duration: 0.32)) { hasAppeared = true }
        }
    }

    // MARK: - 見出し

    private var headline: some View {
        Text("起きた")
            .font(Theme.display(96))
            .foregroundStyle(Theme.acid)
            .scaleEffect(hasAppeared ? 1 : 0.86, anchor: .bottomLeading)
            .opacity(hasAppeared ? 1 : 0)
    }

    // MARK: - 突破タイム

    private var breakthroughTime: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(WakeRecords.durationText(result.duration))
                    .font(Theme.display(64))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("で突破")
                    .font(Theme.label(16))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 0)
            }

            if result.isFastestRecord {
                Text("自己ベスト更新")
                    .font(Theme.label(14))
                    .kerning(1.5)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.acid)
            } else if let fastest = result.records.fastestDuration {
                Text("自己ベストは \(WakeRecords.durationText(fastest))")
                    .font(Theme.caption(13))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 記録

    private var recordRow: some View {
        HStack(spacing: 0) {
            recordCell(value: "\(result.records.currentStreak)日", caption: "連続", isLead: true)
            recordCell(value: "\(result.records.longestStreak)日", caption: "最長")
            recordCell(value: "\(result.records.totalCount)回", caption: "通算")
        }
        .overlay { Rectangle().stroke(Color.white, lineWidth: Theme.rule) }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 14)
    }

    private func recordCell(value: String, caption: String, isLead: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Theme.display(34))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(Theme.caption(11))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .overlay(alignment: .leading) {
            if !isLead {
                Rectangle().fill(Color.white).frame(width: Theme.rule)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption) \(value)")
    }

    // MARK: - 解除した実績

    private var unlockedBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("実績を解除")
                .font(Theme.label(13))
                .kerning(1.5)
                .foregroundStyle(.white.opacity(0.7))

            VStack(spacing: 8) {
                ForEach(result.unlockedTitles, id: \.self) { title in
                    Text(title)
                        .font(Theme.label(17))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Theme.acid)
                }
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 14)
    }
}
