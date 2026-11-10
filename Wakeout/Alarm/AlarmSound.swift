import ActivityKit
import AVFoundation
import Foundation

/// アラーム音の選択肢。
///
/// - Important: AlarmKit が受け取れるのは `AlertConfiguration.AlertSound` で、
///   用意されている API は `.default` と `.named(_:)` の 2 つだけ。
///   `.named(_:)` が探しに行くのは **アプリバンドル内**か **`Library/Sounds`** で、
///   **iOS のシステム標準サウンドを列挙・選択させる API は存在しない**。
///
///   そのため音源の入手経路は次の 2 つになる。
///   1. ビルド時に同梱する（Wakeout ターゲットの Copy Bundle Resources に追加）
///   2. アプリ内で取り込む（`SoundLibrary` が `Library/Sounds` にコピーする）
enum AlarmSound {
    /// `soundName` に保存される「デフォルト音」を表す予約語。
    static let defaultIdentifier = "__default__"

    struct Option: Identifiable, Hashable {
        /// `AlarmEntry.soundName` に保存される値。
        let id: String
        let displayName: String
        /// ユーザーが取り込んだ音源かどうか（＝アプリ内から削除できるか）。
        let isRemovable: Bool
    }

    /// ピッカーに出す選択肢。デフォルト + バンドル同梱 + 取り込み済み。
    static func options() -> [Option] {
        var result = [Option(id: defaultIdentifier, displayName: "デフォルト", isRemovable: false)]

        result += bundledFileNames().map {
            Option(id: $0, displayName: displayName(fromFileName: $0), isRemovable: false)
        }

        result += SoundLibrary.installedFileNames().map {
            Option(id: $0, displayName: displayName(fromFileName: $0), isRemovable: true)
        }

        return result
    }

    /// `AlarmManager.AlarmConfiguration(sound:)` に渡す値へ変換する。
    ///
    /// 参照先が消えている場合（取り込んだ音源を削除した後など）は
    /// 無音にならないようデフォルトへ落とす。
    static func alertSound(for identifier: String) -> AlertConfiguration.AlertSound {
        guard identifier != defaultIdentifier else { return .default }
        guard bundledFileNames().contains(identifier) || SoundLibrary.exists(identifier) else {
            return .default
        }
        return .named(identifier)
    }

    /// その音源がまだ存在するか。編集画面で「消えた音源」を選択中に見せないために使う。
    static func isAvailable(_ identifier: String) -> Bool {
        identifier == defaultIdentifier
            || bundledFileNames().contains(identifier)
            || SoundLibrary.exists(identifier)
    }

    private static func displayName(fromFileName fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }

    /// 通知音として認められる長さの上限。
    ///
    /// これを超えるファイルを `.named(_:)` に渡すとシステムが無効な音源として扱い、
    /// **アラームが無音になる**。エラーも警告も出ないので、選択肢の段階で弾く。
    static let maximumDuration: TimeInterval = 30

    /// バンドル直下の、アラーム音として実際に使えるファイル名を列挙する。
    ///
    /// - Note: 試聴（`AVAudioPlayer`）には長さの制限が無いため、
    ///   ここで弾かないと「試聴では鳴るのにアラームでは鳴らない」という
    ///   原因の分かりにくい不具合になる。
    private static func bundledFileNames() -> [String] {
        let extensions = ["caf", "wav", "aiff", "aif"]
        guard let resourceURL = Bundle.main.resourceURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: resourceURL,
                includingPropertiesForKeys: nil
              ) else {
            return []
        }
        return contents
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .filter(isUsableAsAlertSound)
            .map(\.lastPathComponent)
            .sorted()
    }

    /// 通知音の要件（30 秒未満・読み取り可能）を満たすか。
    private static func isUsableAsAlertSound(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return false }
        let duration = Double(file.length) / sampleRate
        return duration > 0 && duration < maximumDuration
    }
}
