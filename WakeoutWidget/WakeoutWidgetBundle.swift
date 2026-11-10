import SwiftUI
import WidgetKit

@main
struct WakeoutWidgetBundle: WidgetBundle {
    var body: some Widget {
        // AlarmKit のアラート表示に必要な Live Activity
        WakeoutAlarmLiveActivity()
        // ホーム画面 / ロック画面ウィジェット
        NextAlarmWidget()
    }
}
