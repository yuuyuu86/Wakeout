import Foundation
import WidgetKit

/// SwiftData の変更をウィジェットに反映させる。
///
/// アラームを追加・編集・削除・ON/OFF したタイミングで必ず呼ぶこと。
/// 呼び忘れるとウィジェットの表示だけが古いまま残る。
enum WidgetSync {
    static func publish(_ snapshots: [AlarmSnapshot]) {
        AlarmSnapshotStore.save(snapshots)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
