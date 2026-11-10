import Accelerate
import AVFoundation
import Foundation

/// 音源の波形（表示用の振幅の列）。
///
/// 切り出し画面で「どこに音が入っているか」を目で見て決められるようにするためのもの。
/// 再生には使わないので精度は要らない。区間ごとの**最大振幅**だけを取る。
struct AudioWaveform: Sendable {
    /// 0.0〜1.0 に正規化した振幅。左から時間順。
    let samples: [Float]
    let duration: TimeInterval

    /// 表示する棒の本数。増やしても画面上は潰れて見えないのでこの程度で足りる。
    static let resolution = 140

    /// 1 本の棒を作るために読むフレーム数の上限。
    ///
    /// 全フレームを読むと 5 分の曲で 2600 万フレームを走査することになり、
    /// 最適化の効かない Debug ビルドでは数十秒〜数分かかって画面が止まって見える。
    /// 表示用の波形に完全な精度は要らないので、区間ごとに先頭を少しだけ読んで代表させる。
    /// これで読む量はファイルの長さによらず一定になる。
    private static let windowFrames = 2048

    /// 音源を走査して波形を作る。
    ///
    /// - Important: ファイルを読むので、呼び出し側はメインスレッドから外すこと。
    static func load(from url: URL, resolution: Int = resolution) -> AudioWaveform? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }

        let format = file.processingFormat
        let totalFrames = file.length
        guard totalFrames > 0, format.sampleRate > 0, resolution > 0 else { return nil }

        let framesPerBucket = max(1, Int(totalFrames) / resolution)
        let capacity = AVAudioFrameCount(min(framesPerBucket, windowFrames))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }

        var peaks: [Float] = []
        peaks.reserveCapacity(resolution)

        for index in 0..<resolution {
            let position = AVAudioFramePosition(index) * AVAudioFramePosition(framesPerBucket)
            guard position < totalFrames else { break }

            file.framePosition = position
            let readable = AVAudioFrameCount(min(AVAudioFramePosition(capacity), totalFrames - position))
            do {
                try file.read(into: buffer, frameCount: readable)
            } catch {
                break
            }
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }

            // 振幅の最大値。走査は Accelerate に任せる。
            var peak: Float = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                var channelPeak: Float = 0
                vDSP_maxmgv(channels[channel], 1, &channelPeak, vDSP_Length(buffer.frameLength))
                peak = max(peak, channelPeak)
            }
            peaks.append(peak)
        }
        guard !peaks.isEmpty else { return nil }

        // 一番大きいところが画面いっぱいになるように揃える。
        // 小さく録れている音源でも形が読めるようにするため。
        let loudest = peaks.max() ?? 0
        let normalized = loudest > 0 ? peaks.map { $0 / loudest } : peaks

        return AudioWaveform(
            samples: normalized,
            duration: Double(totalFrames) / format.sampleRate
        )
    }
}
