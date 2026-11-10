import CoreMotion
import Foundation
import Observation

/// `CMMotionManager` の加速度センサーでシェイク回数を数える。
///
/// 判定は「重力を除いた加速度の大きさが `threshold` を超えたら 1 回」。
/// 1 回の振りで複数カウントされないよう、`cooldown` 秒のデバウンスを入れている。
@MainActor
@Observable
final class ShakeDetector {
    /// 現在のカウント。
    private(set) var count: Int = 0
    /// センサーが利用できない場合に true。
    private(set) var isUnavailable: Bool = false

    /// この値を超えた加速度をシェイクとみなす（G 単位。1.0 = 重力加速度）。
    private let threshold: Double = 2.2
    /// 連続カウント防止の待ち時間（秒）。
    private let cooldown: TimeInterval = 0.25

    private let motionManager = CMMotionManager()
    private var lastCountedAt: Date = .distantPast

    func start() {
        guard motionManager.isAccelerometerAvailable else {
            isUnavailable = true
            return
        }
        guard !motionManager.isAccelerometerActive else { return }

        motionManager.accelerometerUpdateInterval = 1.0 / 50.0
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let acceleration = data?.acceleration else { return }
            MainActor.assumeIsolated {
                self.handle(acceleration)
            }
        }
    }

    func stop() {
        motionManager.stopAccelerometerUpdates()
    }

    func reset() {
        count = 0
        lastCountedAt = .distantPast
    }

    private func handle(_ acceleration: CMAcceleration) {
        let magnitude = sqrt(
            acceleration.x * acceleration.x
                + acceleration.y * acceleration.y
                + acceleration.z * acceleration.z
        )

        guard magnitude > threshold else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCountedAt) > cooldown else { return }

        lastCountedAt = now
        count += 1
    }
}
// deinit で stopAccelerometerUpdates() は呼べない
// （nonisolated deinit から non-Sendable な CMMotionManager に触れられないため）。
// センサーの停止は MissionView の onDisappear / クリア時の stop() で行う。
