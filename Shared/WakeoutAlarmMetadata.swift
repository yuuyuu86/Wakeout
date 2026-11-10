import AlarmKit
import Foundation

/// AlarmKit の `AlarmAttributes` に載せるアプリ固有のメタデータ。
///
/// Widget Extension 側の `ActivityConfiguration(for:)` と型が一致している必要があるため、
/// Shared に置いて両ターゲットに所属させている。
struct WakeoutAlarmMetadata: AlarmMetadata {
    /// ユーザーが付けたラベル（空文字の場合もある）。
    var label: String

    init(label: String = "") {
        self.label = label
    }
}
