import AVFoundation
import Foundation

/// 編集画面でアラーム音を試聴するためのプレイヤー。
///
/// 実際のアラーム再生はシステム（AlarmKit）が行うので、これは選択時の確認専用。
@MainActor
final class SoundPreviewPlayer {
    static let shared = SoundPreviewPlayer()

    private var player: AVAudioPlayer?
    /// 範囲試聴を打ち切るための待機。次の再生や停止で必ず取り消す。
    private var stopTask: Task<Void, Never>?

    private init() {}

    /// 切り出し画面用。ファイルの一部だけを試聴する。
    ///
    /// `AVAudioPlayer` には「ここまでで止める」指定が無いので、
    /// 長さぶん待って自分で止める。
    ///
    /// - Parameter fadeIn: 取り込み時に焼き込むフェードインの秒数。
    ///   試聴でも同じように立ち上げる。ここで再現しないと
    ///   「試聴では普通なのにアラームでは小さい」という食い違いになる。
    func playRange(
        of url: URL,
        from start: TimeInterval,
        duration: TimeInterval,
        fadeIn: TimeInterval = 0
    ) {
        stop()
        guard duration > 0 else { return }

        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.prepareToPlay()
        player.currentTime = min(start, max(0, player.duration))
        if fadeIn > 0 {
            // 書き出し側は dB を直線で上げるが、こちらは `setVolume` の線形変化で近似する。
            // 聞いて確かめるための試聴なので、立ち上がりの体感が合えば十分。
            player.volume = pow(10, SoundLibrary.fadeInStartDecibels / 20)
            player.setVolume(1, fadeDuration: fadeIn)
        }
        player.play()
        self.player = player

        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    /// `AlarmSound.Option.id` を渡す。デフォルト音は試聴できないので何もしない。
    func play(_ identifier: String) {
        stop()
        guard identifier != AlarmSound.defaultIdentifier,
              let url = fileURL(for: identifier) else { return }

        // マナースイッチが入っていても試聴できるようにする
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        player?.play()
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func fileURL(for fileName: String) -> URL? {
        let imported = SoundLibrary.directory.appending(path: fileName)
        if FileManager.default.fileExists(atPath: imported.path) { return imported }

        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext)
    }
}
