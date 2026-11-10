import CoreMotion
import Foundation
import Observation

/// `CMPedometer` でミッション開始からの歩数を数える。
///
/// 布団の中で完結してしまうシェイクと違い、**歩かないと進まない**。
/// 起き上がる動作そのものを要求できるので、覚醒には最も効く。
///
/// - Important: 歩数の取得には「モーションとフィットネス」の許可が要る
///   （`NSMotionUsageDescription`）。
///   許可されない端末・センサーの無い端末では `isUnavailable` を立て、
///   呼び出し側で別のミッションへ逃がすこと。
///
/// - Important: **シミュレータでは歩数が流れてこない。** 実機でのみ確認できる。
@MainActor
@Observable
final class StepDetector {
    /// ミッション開始からの歩数。
    private(set) var count: Int = 0
    /// 歩数を取得できない場合に true。
    private(set) var isUnavailable: Bool = false

    private let pedometer = CMPedometer()
    private var isRunning = false

    func start() {
        guard CMPedometer.isStepCountingAvailable() else {
            isUnavailable = true
            return
        }
        guard !isRunning else { return }
        isRunning = true

        // 開始時刻を渡すと、その時点からの累計が届く。
        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            guard let self else { return }
            MainActor.assumeIsolated {
                if error != nil {
                    // 許可が下りていない場合もここに来る。
                    self.isUnavailable = true
                    return
                }
                guard let steps = data?.numberOfSteps.intValue else { return }
                self.count = steps
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        pedometer.stopUpdates()
    }

    func reset() {
        count = 0
    }
}
// deinit で stopUpdates() は呼べない
// （nonisolated deinit から non-Sendable な CMPedometer に触れられないため）。
// 停止は MissionView の onDisappear / 出題の切り替えで行う。
