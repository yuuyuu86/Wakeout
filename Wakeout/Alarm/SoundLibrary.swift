import AVFoundation
import Foundation

/// ユーザーが自分で取り込んだアラーム音の置き場。
///
/// 置き場所は**アプリコンテナの `Library/Sounds`**。
/// 通知音として再生できるのはアプリバンドル内か、このディレクトリの中だけなので、
/// 取り込んだファイルは必ずここへコピーする。
///
/// 取り込み時に以下を満たす形へ変換する。満たさないと無音になる。
/// - 形式: リニア PCM の `.caf`
/// - 長さ: 30 秒以内
enum SoundLibrary {

    enum ImportError: LocalizedError {
        case cannotAccessFile
        case unreadableAudio

        var errorDescription: String? {
            switch self {
            case .cannotAccessFile:
                "ファイルを読み込む権限がありませんでした。"
            case .unreadableAudio:
                "この音源は読み込めませんでした。別のファイルを試してください。"
            }
        }
    }

    /// 通知音として再生できる最大の長さ。これを超えるぶんは切り落とす。
    static let maxDuration: TimeInterval = 30

    /// 切り出しの最小の長さ。これより短いと一瞬すぎて音として成立しない。
    static let minDuration: TimeInterval = 1

    // MARK: - フェードイン

    /// フェードインの開始音量（dB）。
    ///
    /// 完全な無音から立ち上げると「鳴っていない」と思われるので、
    /// 静かな部屋でようやく聞こえる程度から始める。
    static let fadeInStartDecibels: Float = -40

    /// 選べるフェードインの長さ（秒）。0 は「フェードなし」。
    static let fadeInOptions: [TimeInterval] = [0, 3, 8, 15]

    /// 既定のフェードイン。
    ///
    /// 突然の爆音は、音量そのものよりも**変化の急さ**が苦痛になる。
    /// 既定でなだらかに立ち上げ、嫌なら切れるようにしている。
    static let defaultFadeIn: TimeInterval = 8

    /// その長さの音源に許すフェードインの上限。
    ///
    /// 全体をフェードに使うと、最大音量に達した瞬間に先頭へ戻る
    /// （アラーム音はシステムがループ再生する）。必ず後半を最大音量で残し、
    /// 鳴り続けていることが分かるようにする。
    static func maximumFadeIn(forLength length: TimeInterval) -> TimeInterval {
        max(0, length / 2)
    }

    /// 実際に適用するフェードインの長さ。選択値を音源の長さに収める。
    static func effectiveFadeIn(_ requested: TimeInterval, length: TimeInterval) -> TimeInterval {
        min(requested, maximumFadeIn(forLength: length))
    }

    // MARK: - 置き場

    static var directory: URL {
        let base = URL.libraryDirectory.appending(path: "Sounds", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    /// 取り込み済みの音源ファイル名。
    static func installedFileNames() -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "caf" }
            .map(\.lastPathComponent)
            .sorted()
    }

    static func exists(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: fileName).path)
    }

    static func remove(_ fileName: String) {
        try? FileManager.default.removeItem(at: directory.appending(path: fileName))
    }

    // MARK: - 切り出し用の一時コピー

    /// 切り出し画面で扱うための作業用ディレクトリ。
    private static var stagingDirectory: URL {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "SoundStaging", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    /// 選ばれたファイルを作業用ディレクトリへ複製し、その URL を返す。
    ///
    /// ファイル選択画面が渡す URL はセキュリティスコープ付きで、
    /// 有効な間しか読めない。切り出し画面は波形の解析・試聴・書き出しと
    /// 何度もファイルを読むので、先に自分の領域へ写しておく。
    static func stageForTrimming(from source: URL) throws -> URL {
        let needsScope = source.startAccessingSecurityScopedResource()
        defer { if needsScope { source.stopAccessingSecurityScopedResource() } }

        let ext = source.pathExtension.isEmpty ? "audio" : source.pathExtension
        let destination = stagingDirectory
            .appending(path: "\(UUID().uuidString).\(ext)")

        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw ImportError.cannotAccessFile
        }

        // 読めない形式をここで弾く。切り出し画面に入ってから失敗させない。
        guard (try? AVAudioFile(forReading: destination)) != nil else {
            try? FileManager.default.removeItem(at: destination)
            throw ImportError.unreadableAudio
        }
        return destination
    }

    /// 作業用の一時ファイルを消す。取り込みを終えた／やめたときに呼ぶ。
    static func discardStaged(_ url: URL) {
        guard url.path.hasPrefix(stagingDirectory.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 音源の長さ。読めなければ nil。
    static func duration(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0, file.length > 0 else { return nil }
        return Double(file.length) / sampleRate
    }

    // MARK: - 取り込み

    /// 選ばれた音源を `Library/Sounds` に `.caf` として取り込み、保存したファイル名を返す。
    ///
    /// - Parameters:
    ///   - source: 取り込み元。
    ///   - startTime: 切り出しの開始位置（秒）。既定は先頭から。
    ///   - duration: 切り出す長さ（秒）。nil なら上限（30 秒）まで。
    ///   - fadeIn: 先頭を小さい音から立ち上げる秒数。0 なら加工しない。
    ///   - name: 保存名の元にする文字列。nil なら元ファイル名。
    ///
    /// - Note: フェードインは**書き出す波形そのものに焼き込む**。
    ///   AlarmKit に渡せるのは音源の名前だけで、音量を操作する API が無いため、
    ///   ファイル側で用意しておくしかない。
    @discardableResult
    static func importSound(
        from source: URL,
        startTime: TimeInterval = 0,
        duration: TimeInterval? = nil,
        fadeIn: TimeInterval = 0,
        name: String? = nil
    ) throws -> String {
        // ファイル選択画面から渡される URL はセキュリティスコープ付き。
        let needsScope = source.startAccessingSecurityScopedResource()
        defer { if needsScope { source.stopAccessingSecurityScopedResource() } }

        guard let input = try? AVAudioFile(forReading: source) else {
            throw ImportError.unreadableAudio
        }

        let destinationName = uniqueName(
            basedOn: name ?? source.deletingPathExtension().lastPathComponent
        )
        let destination = directory.appending(path: destinationName)

        let format = input.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        guard let output = try? AVAudioFile(forWriting: destination, settings: settings) else {
            throw ImportError.unreadableAudio
        }

        // 切り出し範囲をフレーム位置に直す。
        // 指定が無い／範囲外の場合も無音を書き出さないよう、必ず入力の中に収める。
        let startFrame = max(0, min(input.length, AVAudioFramePosition(startTime * format.sampleRate)))
        let requested = duration.map { AVAudioFramePosition($0 * format.sampleRate) }
            ?? AVAudioFramePosition(maxDuration * format.sampleRate)
        let frameLimit = min(
            input.length - startFrame,
            min(requested, AVAudioFramePosition(maxDuration * format.sampleRate))
        )
        input.framePosition = startFrame

        // フェードは「書き出す長さ」を基準に決める。
        // 選択範囲より長いフェードを指定されても、最大音量の部分が残るようにする。
        let fadeSeconds = effectiveFadeIn(
            fadeIn,
            length: Double(frameLimit) / format.sampleRate
        )
        let fadeFrames = AVAudioFramePosition(fadeSeconds * format.sampleRate)

        let chunkSize: AVAudioFrameCount = 8192
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
            throw ImportError.unreadableAudio
        }

        var written: AVAudioFramePosition = 0
        while written < frameLimit {
            let remaining = frameLimit - written
            let toRead = AVAudioFrameCount(min(AVAudioFramePosition(chunkSize), remaining))
            do {
                try input.read(into: buffer, frameCount: toRead)
            } catch {
                break
            }
            if buffer.frameLength == 0 { break }
            applyFade(to: buffer, startingAt: written, fadeFrames: fadeFrames)
            do {
                try output.write(from: buffer)
            } catch {
                remove(destinationName)
                throw ImportError.unreadableAudio
            }
            written += AVAudioFramePosition(buffer.frameLength)
        }

        guard written > 0 else {
            remove(destinationName)
            throw ImportError.unreadableAudio
        }

        return destinationName
    }

    // MARK: - フェードインの適用

    /// 書き出す直前のバッファに、先頭からの位置に応じたゲインを掛ける。
    ///
    /// - Parameters:
    ///   - offset: このバッファの先頭が、書き出し全体の何フレーム目にあたるか。
    ///   - fadeFrames: フェードに使うフレーム数。0 なら何もしない。
    private static func applyFade(
        to buffer: AVAudioPCMBuffer,
        startingAt offset: AVAudioFramePosition,
        fadeFrames: AVAudioFramePosition
    ) {
        guard fadeFrames > 0, offset < fadeFrames else { return }
        // `AVAudioFile.processingFormat` は float のはずだが、
        // 取れなければ加工だけ諦める（無加工で鳴るほうが、無音になるよりよい）。
        guard let channels = buffer.floatChannelData else { return }

        let channelCount = Int(buffer.format.channelCount)
        for frame in 0..<Int(buffer.frameLength) {
            let gain = fadeGain(atFrame: offset + AVAudioFramePosition(frame), fadeFrames: fadeFrames)
            guard gain < 1 else { break }
            for channel in 0..<channelCount {
                channels[channel][frame] *= gain
            }
        }
    }

    /// 先頭から `frame` 番目のフレームに掛けるゲイン。
    ///
    /// 振幅を直線で上げると、人の耳には「最後だけ急に大きくなる」ように聞こえる。
    /// dB を直線で上げて、体感がなだらかになるようにする。
    private static func fadeGain(
        atFrame frame: AVAudioFramePosition,
        fadeFrames: AVAudioFramePosition
    ) -> Float {
        guard fadeFrames > 0, frame >= 0 else { return 1 }
        guard frame < fadeFrames else { return 1 }
        let progress = Float(frame) / Float(fadeFrames)
        return pow(10, fadeInStartDecibels * (1 - progress) / 20)
    }

    /// 同名のファイルがあっても上書きしないよう、必要なら連番を足す。
    private static func uniqueName(basedOn rawName: String) -> String {
        let cleaned = rawName
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "サウンド" : cleaned

        var candidate = "\(base).caf"
        var index = 2
        while exists(candidate) {
            candidate = "\(base)-\(index).caf"
            index += 1
        }
        return candidate
    }
}
