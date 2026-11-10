# Wakeout

iOS 26+ の AlarmKit を使った目覚ましアプリ。**ミッションをクリアするまでアラームが止まらない。**

## 動作確認済みの環境

- Xcode 27.0 beta (`/Applications/Xcode-beta.app`) / iOS 27.0 SDK
- Deployment Target: iOS 26.0
- Swift 6.0（strict concurrency 有効）
- シミュレータ（iPhone 17 Pro / iOS 27）でビルド・起動・アラーム登録まで確認済み

## ソースファイルを追加したとき

`Wakeout.xcodeproj` にファイルを登録しないとビルド対象にならない。
Xcode 上でドラッグしてもよいが、コマンドでも追加できる。

```bash
python3 Tools/add_source.py Wakeout/Mission/NewThing.swift            # アプリ本体へ
python3 Tools/add_source.py Shared/NewShared.swift --target app --target widget
```

pbxproj を直接書き換えるので、**Xcode で設定した署名やケイパビリティを壊さない**。
（以前はプロジェクト全体を生成し直すスクリプトを使っていたが、
実行するたびに `DEVELOPMENT_TEAM` が消えて署名できなくなる問題があった。）

## Xcode で開く前にやること

`.xcodeproj` は生成済みなので、そのまま開けます。

```bash
open -a /Applications/Xcode-beta.app /Users/yuta/Wakeout/Wakeout.xcodeproj
```

実機で動かすには以下 3 つの設定が必要です。

### 1. Bundle ID を自分のものに変える

Project（ターゲットではなく **PROJECT** の Build Settings）に `WAKEOUT_BUNDLE_ID` という
ユーザー定義設定を置いてあります。**ここ 1 箇所を書き換えれば**
アプリ・Widget Extension・App Group の 3 つすべてに反映されます。

| | 値 |
|---|---|
| アプリ | `$(WAKEOUT_BUNDLE_ID)` |
| Widget Extension | `$(WAKEOUT_BUNDLE_ID).WakeoutWidget` |
| App Group | `group.$(WAKEOUT_BUNDLE_ID).shared` |

あわせて `Shared/WakeoutShared.swift` の `appGroupID` も同じ値に書き換えてください
（Swift 側はビルド設定を参照できないため、ここだけ二重管理になっています）。

### 2. 署名チーム

`Wakeout` / `WakeoutWidgetExtension` 両ターゲットの Signing & Capabilities で
Team を選択します（`DEVELOPMENT_TEAM` は未設定にしてあります）。

### 3. App Group を Developer Portal に登録

両ターゲットの Signing & Capabilities に App Groups capability を追加し、
`group.<あなたのBundleID>.shared` を有効にします。entitlements ファイル自体は
`Wakeout/Wakeout.entitlements` と `WakeoutWidget/WakeoutWidget.entitlements` に
用意済みなので、Xcode 上でチェックを入れるだけです。

> App Group が有効になっていないと `WakeoutShared.defaults` が standard に
> フォールバックし、Debug ビルドでは `assertionFailure` で気付けるようにしてあります。

## 構成

```
Shared/                         ← アプリと Widget Extension の両方に所属
  WakeoutShared.swift           App Group 定義 + MissionStore（ミッション状態の共有）
  WakeoutAlarmMetadata.swift    AlarmAttributes に載せる Metadata 型
  MissionGatedStopIntent.swift  停止ボタンの Intent（ミッション判定つき）
  WakeoutShared.swift の SoftWakeStore  先行アラームの ID の共有（SwiftData に持たない）
  WakeoutTheme.swift            配色・文字・余白の定義（Widget と共有）
  AlarmSnapshot.swift           ウィジェットに渡すアラーム情報 + 次回発火時刻の計算

Wakeout/                        ← アプリ本体
  WakeoutApp.swift              @main / SwiftData ModelContainer
  RootView.swift                ミッション未クリア中は全画面を覆う
  DesignSystem/Components.swift 四角いトグル・ホイール・ボタン・状態表示
  Models/AlarmEntry.swift       SwiftData モデル + 次回発火時刻の算出
  Models/MissionDifficulty.swift ミッションの難易度（出題数・各ミッションの手ごわさ）
  Models/WakeLogEntry.swift     起床の記録 + 連続日数の算出
  Models/WakeStats.swift        起床記録の集計（平均起床時刻・7日グラフ用の値）
  Models/WakeRecords.swift      自己ベスト（最速突破・最長連続・通算）の積み上げ
  Models/Achievement.swift      実績 12 種の定義と解除判定
  Models/AppSettings.swift      アプリ全体の設定（通知・画面の明るさなど）
  Alarm/AlarmScheduler.swift    AlarmKit への登録・解除
  Alarm/AlarmReconciler.swift   SwiftData と AlarmKit の食い違いを直す（迷子の登録の掃除も）
  Alarm/AlarmSound.swift        サウンド選択肢
  Alarm/SoftWake.swift          ソフト起床（1 タップで止まる先行アラーム + 起床確定）
  Alarm/SoundLibrary.swift      音源の取り込み（.caf 変換 + Library/Sounds へ保存）
  Alarm/SoundPreviewPlayer.swift 編集画面での試聴
  Alarm/WidgetSync.swift        変更をウィジェットへ反映
  Alarm/BatteryGuard.swift      バッテリー残量の監視とローカル通知
  Alarm/NotificationPermission.swift  ローカル通知の許可判定（2 機能で共用）
  Alarm/BedtimeReminder.swift   就寝リマインダーの予約（次のアラームの N 時間前）
  Alarm/MissingAlarmReminder.swift  明日のアラームが無いときの夜の警告
  Views/AlarmListView.swift     ホーム（次に鳴る時刻・一覧・ON/OFF・スワイプ操作・権限導線）
  Views/AlarmEditView.swift     新規作成 / 編集
  Views/WakeLogView.swift       自己ベスト・実績・起床の統計・記録一覧
  Views/SettingsView.swift      設定（通知・アプリ制限・許可の状態）
  Mission/MissionCoordinator.swift  ミッション状態機械 + stop(id:) 呼び出し
  Mission/MissionView.swift     5 種類のミッションの出題
  Mission/ShakeDetector.swift   CMMotionManager によるシェイク判定
  Mission/ScreenBrightness.swift ミッション中だけ画面を段階的に明るくする
  Mission/StepDetector.swift    CMPedometer による歩数カウント
  Mission/MiniCalculator.swift  計算ミッション用の小さな電卓
  Mission/CelebrationView.swift 突破直後の結果画面（タイム・記録・解除した実績）

WakeoutWidget/                  ← Widget Extension
  WakeoutWidgetBundle.swift
  WakeoutAlarmLiveActivity.swift    Live Activity（AlarmKit のアラート表示に必須）
  NextAlarmWidget.swift             ホーム画面 / ロック画面ウィジェット
```

## ウィジェット

Widget Extension には 2 種類が入っている。

| | 役割 |
|---|---|
| `WakeoutAlarmLiveActivity` | Live Activity。`AlarmAttributes<WakeoutAlarmMetadata>` の `ActivityConfiguration`。**AlarmKit がアラート表示に ActivityKit を使うため、これが無いとアラーム自体が成立しない**（必須要件）。ロック画面・Dynamic Island の鳴動中表示を担当する |
| `NextAlarmWidget` | 次に鳴るアラームを表示。`systemSmall` / `systemMedium`（ホーム画面）、`accessoryRectangular` / `accessoryCircular` / `accessoryInline`（ロック画面） |

### ウィジェットへのデータの渡し方

Widget Extension から SwiftData のストアを直接読むとスキーマを二重管理することになるため、
**表示に必要な最小限だけを App Group の `UserDefaults` に JSON で共有**している。

```
SwiftData (AlarmEntry)
  → AlarmListView の .onChange で検知
  → WidgetSync.publish()  … AlarmSnapshotStore に保存 + reloadAllTimelines()
  → App Group の UserDefaults
  → NextAlarmProvider がタイムライン生成時に読む
```

`AlarmSnapshot` には**計算済みの発火日時ではなく時刻と曜日そのもの**を持たせている。
次に鳴る時刻はタイムライン更新のたびに変わるため、ウィジェット側で計算し直す必要があるから。
`nextFireDate(from:)` は `AlarmSnapshot` に置き、アプリ側の `AlarmEntry` もこれに委譲している（実装は 1 箇所）。

- 追加・編集・削除・ON/OFF はすべて一覧の変化として現れるので、書き出しは `AlarmListView` の 1 箇所に集約している。
- ロック画面のウィジェットは単色でレンダリングされるため、色ではなく文字の大小と配置だけで優先順位を作っている。

## アラーム音の増やし方

音源を増やす経路は 2 つある。

### A. アプリ内で取り込む（実行時・ユーザー操作）

編集画面のサウンド欄 →「音源を追加」→ ファイルを選ぶ →
**切り出し画面（`SoundTrimView`）で使う範囲を決める** → 追加。

操作は波形の上だけで完結する。数値入力もボタンも持たせない。

- **左右のつまみをドラッグ** → その端だけが動く（＝長さが変わる。0.1 秒きざみ）
- **それ以外をタップ／ドラッグ** → 長さを保ったまま範囲ごと動く

つまみは選択範囲の**外側**に描く（`gripOrigins`）。内側に描くと、
5 分の音源で 1 秒を選んだときに範囲が数 pt まで細くなり、2 つが重なって前後が分からなくなる。

掴む判定は描画位置ではなく**境界線からの距離**で行い、近いほうを選ぶ（`role(forTouchAt:)`）。
範囲が細くて両方のつまみが指の下に来ても取り違えない。

役割は**指を置いた瞬間に決めて離すまで変えない**（`dragRole`）。
途中で判定し直すと、掴んだものが手の中で入れ替わる。

ドラッグは VoiceOver では扱えないので、位置は `accessibilityAdjustableAction`、
長さは `accessibilityAction(named:)` で動かせるようにしてある。

範囲が音源と同じ長さになる場合（1 秒の音源など）は開始位置を動かせない。
そのときは説明文を差し替え、微調整ボタンを隠す。動かないものを動かせると書かない。

`SoundLibrary` が次の処理をして `Library/Sounds` に保存する。

- リニア PCM の `.caf` へ変換（元が mp3 / m4a / wav でもよい）
- 選ばれた範囲だけを書き出す（30 秒未満・1 秒以上）
- 選ばれた長さのフェードインを**波形に焼き込む**（後述）
- 同名があれば連番を足す

切り出し画面を挟むのは、**先頭 30 秒が使えるとは限らない**ため。
頭に無音や前奏がある音源を機械的に切ると、鳴っているのに聞こえないアラームになる。

- 波形は `AudioWaveform` が算出する。区間ごとの最大振幅だけを取り、
  ファイル全体をチャンク単位で走査する（長い音源でもメモリを食わない）。
  重いのでメインスレッドから外して呼ぶこと。
- 選ばれたファイルは、まず作業用ディレクトリへ複製する（`stageForTrimming`）。
  ファイル選択画面が渡す URL はセキュリティスコープ付きで有効期間が限られており、
  切り出し画面は解析・試聴・書き出しと何度も読むため。
  取り込み後もキャンセル後も `discardStaged` で消す。

**この 2 つは通知音の要件で、満たさないと無音になる。**
取り込んだ音源は行の右のゴミ箱で削除でき、選択中の音源を消した場合はデフォルトへ戻す。

### B. ビルド時に同梱する（アプリに最初から入れておく）

`.caf` / `.wav` / `.aiff` を `Wakeout/Sounds/` に置き、Xcode の
**Wakeout ターゲット → Build Phases → Copy Bundle Resources** に追加する。
`AlarmSound` がバンドル直下を走査するので、コードの変更は要らない。

**30 秒以上のファイルは使えない。** 通知音の要件で、超えるとシステムが無効な音源として扱い
**アラームが無音になる**。エラーも警告も出ない。

試聴は `AVAudioPlayer` で直接再生していて長さの制限が無いため、
**「試聴では鳴るのにアラームでは鳴らない」**という形で現れる。
`AlarmSound.bundledFileNames()` が長さを検査して選択肢から弾くので、
ピッカーに出てこない音源はこれを疑う。

```bash
afinfo Wakeout/Sounds/foo.wav | grep duration          # 長さを確認
ffmpeg -i in.wav -t 29.5 -c:a pcm_s16le -ar 44100 out.wav   # 切り詰める
```

変換が必要なら `afconvert` を使う。

```bash
afconvert -f caff -d LEI16@44100 input.wav output.caf
```

### 音源の入手先

- **GarageBand / Logic の Apple Loops** — 自分の制作物に組み込むぶんにはロイヤリティフリー
- **Pixabay / Mixkit** — 商用利用可の効果音が多い（各ファイルの規約は要確認）
- **freesound.org** — ファイルごとにライセンスが違うので CC0 のものを選ぶ

> **iOS のシステム標準サウンド（`/System/Library/Audio/UISounds`）をコピーして同梱してはいけない。**
> Apple の素材であり、再配布のライセンスがない。

## スヌーズ・起床記録・統計・難易度・就寝リマインダー・バッテリー警告

### スヌーズ（アラームごとに opt-in）

既定は**無効**。元の仕様が「スヌーズなし」だったため、必要な人だけ有効にできる形にしている。

有効にすると `AlarmConfiguration` に 2 つを渡す。**両方揃わないと再アラートされない。**

| | 役割 |
|---|---|
| `countdownDuration.postAlert` | 再度鳴るまでの時間（9 分） |
| `secondaryButton` + `secondaryButtonBehavior = .countdown` | アラート画面のスヌーズボタン |

`.countdown` を指定するとシステムが自動でカウントダウン状態へ遷移するので、
スヌーズ用のカスタム Intent は要らない。

**スヌーズしても停止にはミッションが必要**という原則は変えていない。
スヌーズは「もう一度鳴らす」だけで、`stopIntent` の判定は素通しされない。

### 起床の記録

ミッションをクリアして停止した瞬間に `WakeLogEntry` を 1 件残す（`MissionCoordinator.completeMission`）。
記録するのは「鳴った時刻・止めた時刻・ミッション種別・誤答回数」。

アラームを削除しても記録は残したいので、`alarmID` は参照ではなく値として持ち、
ラベルも記録時点のものを複製して保存している。

連続日数（`currentStreak`）は「今日または昨日」に記録があるところから遡って数える。
今日の記録がまだ無くても、昨日まで繋がっていれば連続扱いにする（まだ寝ていないだけ、という状況を切らないため）。

### 記録の削除

1 件は左スワイプ、全消去は一覧末尾のボタン（確認あり）。

統計は記録から作られるので、**消せないとテスト用の記録が平均起床時刻と連続日数を永久に歪める**。
統計を入れるなら削除も同時に要る。

### 起床の統計（`WakeStats`）

記録画面の上部に、直近 30 日の集計と直近 7 日のグラフを出す。

- **1 日に複数の記録がある場合は、その日の最初の記録**を「その日の起床」として扱う
  （スヌーズ後にもう一度鳴った分を二重に数えないため）。
- 平均起床時刻は**円周平均**で求める。単純な相加平均だと 23:50 と 00:10 の平均が
  12:00 になってしまうため、1 日を円周とみなして単位ベクトルの平均から角度を戻している。
- グラフは棒の長さではなく**位置**で時刻を表す。起床時刻は量ではないので、
  「毎日どのあたりに揃っているか / ばらついているか」が読める形にした。
  横軸の範囲は表示する 7 日と平均が必ず収まるように取り、最低 2 時間の幅を持たせる。

### 就寝リマインダー（`BedtimeReminder`）

次に鳴るアラームの時刻から目標睡眠時間（既定 8 時間）を引いた時刻に、ローカル通知を出す。
起きられない原因の多くは寝るのが遅いことなので、朝ではなく夜に効かせる機能。

- 予約は**作り直し**で管理する。アラームの変更・ON/OFF・設定変更のたびに `sync` を呼べば、
  古い予約（識別子 `wakeout.bedtime.*`）は消えて新しい予約だけが残る。
- アプリを開かない日が続いても効くよう、**3 回分先まで**予約しておく。
  アプリを開くたびに補充される。
- 同じ朝に複数のアラームが鳴る（2 段構えなど）場合、就寝時刻の通知は 1 件に畳む。
- 既定は OFF。通知の許可は**実際に予約するものがあるときだけ**求める
  （アラームが 1 件も無い状態でいきなり許可ダイアログが出るのを避ける）。
- AlarmKit とは無関係の仕組みなので、この通知が出せなくてもアラーム本体には影響しない。

### 通知の操作は 1 か所に集約する（`LocalNotificationScheduler`）

`UNUserNotificationCenter` を複数の場所から同時に触ってはいけない。

バッテリー警告（メインスレッド）と就寝リマインダー（バックグラウンド）から
並行して呼んだ結果、メインスレッドが `removePendingNotificationRequests` から戻らなくなり、
**アプリが起動直後に白画面のまま固まった**。ログもクラッシュも残らず、
`sample <pid>` でメインスレッドのスタックを見てはじめて分かる種類の止まり方をする。

```
main-thread
 └ AlarmListView.body closure #11
   └ syncBatteryNotification()
     └ BatteryGuard.syncNotification()
       └ cancelPendingNotification()   ← ここから戻らない
```

そのため通知の予約・取り消しはすべて `LocalNotificationScheduler`（actor）を通す。

- actor なので呼び出しが直列化され、同時に触ることがない
- MainActor 隔離ではないのでメインスレッドの外で動く
- 引数は Sendable な値だけ。通知オブジェクトの組み立ても actor の中で行う

`BatteryGuard.syncNotification` が `async` なのはこのため。ビューからは必ず `await` で呼ぶ。

### 設定画面

アプリ全体の振る舞いだけを置く。アラーム 1 件ごとの設定（スヌーズ・難易度）は編集画面側にある。

- 就寝リマインダー（ON/OFF・目標睡眠時間・**次にいつ通知するかの予告**）
- バッテリー警告の ON/OFF
- アラーム / 通知の許可状態と、設定アプリへの導線

「ON にしたのに通知が来ない」の原因（鳴る予定のアラームが無い／通知が拒否されている）を
その場で潰せるよう、予告表示は実際の予約計算（`BedtimeReminder.plans`）と同じ関数を使っている。

### ミッションの難易度

アラームごとに 3 段階。4 種類すべての手ごわさを**一括で**決める。

| | 出題数 | 計算 | シェイク | 記憶 | タイピング | 歩く |
|---|---|---|---|---|---|---|
| やさしい | 1 問 | 1桁 × 1桁 | 8 回 | 4 桁 / 4 秒 | 6 文字 | 15 歩 |
| ふつう | 2 問 | 2桁 × 2桁 | 15 回 | 6 桁 / 3 秒 | 10 文字 | 30 歩 |
| むずかしい | 3 問 | 2桁 × 3桁 | 25 回 | 8 桁 / 3 秒 | 14 文字 | 50 歩 |

**難しさは 1 問の手ごわさではなく出題数で作る。** 1 問だけだと、
寝ぼけたまま偶然当たって二度寝する余地が残る。
種類は 1 問ごとにランダムに引き直すので、計算 → シェイク → タイピングのように
違う感覚を続けて使わされる。

- **記憶** — 数字を数秒見せてから隠し、入力させる。誤答なら別の数字を出し直す
  （同じ数字を見せ直すと覚え直す意味がない）。
- **タイピング** — 表示された英数字をそのまま打たせる。
  シェイクは布団の中で目を閉じたままでもできてしまうのに対し、
  これは目と手と注意を同時に使うので確実に起きる。
  使う文字から `l`/`1`、`o`/`0` は除いてある。読み違えさせるのは難しさではなく嫌がらせになる。
- **歩く** — `CMPedometer` でミッション開始からの歩数を数える。布団の中で完結してしまう
  シェイクと違い、起き上がる動作そのものを要求できる。
  **「モーションとフィットネス」の許可（`NSMotionUsageDescription`）が要る**。
  許可されない端末・シミュレータでは歩数が流れてこないので、
  `isUnavailable` を立てて計算ミッションへ逃がす。
- **計算の電卓** — 計算ミッションのときだけ、上部バナーの右に電卓ボタンが出る。
  暗算という関門は弱くなるが、数字を読み取って打ち込む必要は残る。使うかはユーザーの選択。

「計算だけ難しく」のような個別指定はできない。選択肢を増やすほど編集画面が縦に伸びるため。
出題される種類も選ばせない（ランダム）。何が来るか分からないほうが備えて寝られない。

### バッテリー低下時の警告

「残量少 + 非充電 + 有効なアラームあり」が揃ったときだけ、画面内バナーとローカル通知の両方で知らせる。
通知は 10 分後に配信する（アプリを見ている最中に届いても意味が薄く、離れた後に効かせたいため）。
警告は 1 日 1 回まで。条件が解消されたら予約済みの通知は取り消す。

> **シミュレータでは確認できない。** `UIDevice.batteryLevel` が常に -1（不明）を返すため、
> 誤警告を避けて無効扱いにしている。実機でのみ動作する。

## ホームのヒーローは 3 状態とも同じ高さにする

画面上部の大きなカードには 3 つの状態がある。

| 状態 | 面の色 | 意味 |
|---|---|---|
| 次に鳴るアラームがある | acid（イエロー） | 鳴る予定がある＝作動中の状態 |
| アラームはあるが全部 OFF | ink（黒） | このままでは鳴らない |
| アラームが 1 件も無い | surface（白） | まだ何も無い。中立 |

**3 つとも同じ骨組み（`heroFrame`）を使い、高さを変えない。**
状態が変わるたびにカードが伸び縮みすると、下の一覧ごと動いて目が追えなくなる。
`heroMinHeight` を 3 状態の自然な高さより少し上に取って揃えている
（Theme のフォントは Dynamic Type で変わらない固定サイズなので、この下限で実際に一致する）。

枠を空にしてはいけない。上半分が抜けて、何をする画面なのか分からなくなる。

### アラームのかけ忘れの警告（`MissingAlarmReminder`）

毎晩 21 時に確認し、**翌日の昼までに鳴る予定が 1 件も無ければ**通知する。
寝坊の原因で一番多いのはかけ忘れで、起きられなかった後では手遅れなため。

- 判定の窓を「翌日の**正午**まで」と広く取っているのは、
  遅番・夜勤で朝が遅い人のアラームを「無い」と誤判定しないため。
- 予約は一覧が変わるたび・アプリを開くたびに作り直すので、
  夜までにアラームを入れれば取り消される。

### ソフト起床（`SoftWake`）

**苦痛の最大の原因は、深い睡眠の最中に叩き起こされること。** 同じ 7:00 でも、
浅い睡眠から起きるか深睡眠から引きずり出されるかで体感はまったく違う。

ところが睡眠段階をその場で判定する手段が無い（Apple Watch 無しでは。
HealthKit の `sleepAnalysis` は事後、バックグラウンドでの加速度の常時取得も不可）。
そこで**ユーザーの反応そのものをセンサーにする**。

- 本アラームの 20 分前・10 分前に、**1 タップで止まる先行アラーム**を鳴らす
- 反応できた＝眠りが浅かった → そのまま起きてもらう
- 反応できなかった＝深く眠っている → 本アラームが従来どおり容赦なく鳴る

**取りこぼしても安全側に倒れる**のがこの仕組みの要点。先行アラームの登録に失敗しても、
ログに残して本アラームには触らない。1 回分しか登録しないので、
アプリを何日も開かなければ先行アラームは尽きるが、本アラームは鳴り続ける。

#### 先行アラームの止め方では本アラームは止まらない

**ここを取り違えると寝坊する。** 先行アラームの停止ボタンは、寝ぼけたままでも押せる。
それで本アラームまで消えてしまったら、この機能は寝坊を**増やす**。

本アラームを飛ばすには、ホーム画面に出る「もう起きた」を**長押しで確定**する
（`HoldToConfirmButton`）。起き抜けに認知課題を課すのはソフト起床の趣旨に反するので、
ミッションは出さない。ただし指が触れただけでは通さない。

鳴っている最中の本アラームに対しては確定を**拒否する**（`Refusal.alreadyRinging`）。
通してしまうと「長押しでミッションを回避できる」抜け穴になる。

#### 「今日のぶんだけ飛ばす」の実現

AlarmKit に「次の 1 回だけ飛ばす」API は無い。繰り返しアラームを曜日のまま登録し直すと
**今日の分が復活する**（相対スケジュールは、時刻が過ぎていなければ今日も対象にする）。

そこで次の 1 回だけを日時指定（`.fixed`）で押さえ直す。週の繰り返しへ戻すのは
`AlarmReconciler` の役目で、**飛ばした回を過ぎてから**戻す
（曜日どおりの次回が、押さえてある日時より前にあるなら、それが飛ばした回）。

飛ばした時刻は `AlarmEntry.skippedFireDate` に残す。これが無いと、
一覧・ウィジェット・就寝リマインダーが「もう鳴らない時刻」を次の予定として出し続ける。

#### 先行アラームは SwiftData に持たない

`AlarmEntry` 1 件から派生する一時的な登録なので、ID だけを App Group に置く
（`SoftWakeStore`）。これが無いと 2 つ事故が起きる。

- `MissionCoordinator` が先行アラームの鳴動をミッション待ちと取り違える
  （＝1 タップで止まるはずのアラームでミッション画面が出る）
- `AlarmReconciler` が「アプリが知らない登録」として取り消す

鳴っている最中の先行アラームは、取り消さずストアにも残す。
ストアから落とすと、鳴っている間だけミッション画面が出てしまう。

#### 記録には混ぜるが、速さと正確さには混ぜない

ソフト起床の記録（`WakeLogEntry.isSoftWake`）はミッションを解いていないので
`duration` が 0 になる。そのまま集計に入れると
**「最速 0 秒」「無傷」「全制覇」が 1 度も解かずに成立する**。
`WakeProgress` で弾き、通算回数・連続日数・起床時刻だけに数える。
穏やかに起きた日が「起きていない日」になると、優しい経路を選ぶほど損になるため。

### ミッション中の画面（`ScreenBrightness`）

ミッションの間だけ画面を明るくする。光は覚醒に直接効く。

ただし**一息で最大にはしない**。暗順応した目に 1.0 の白面をぶつけると、
眩しさで目を閉じてしまい、覚醒どころか画面を見られなくなる。
`rampDuration`（20 秒）かけて、今の明るさから最大まで上げる。
上がり方は二次曲線で、はじめをゆるくしてある（目が慣れるほど同じ差が眩しくなくなる）。

`MissionView` の地の色も**同じ時間で** `Theme.dawn`（暖色）から `Theme.acid` へ移す。
光と色を別の速さで動かすとちらついて見えるので、`ScreenBrightness.rampDuration` を共有している。
`dawn` も `acid` と同じく明るい面なので、`ink` の文字を載せたまま読める（約11:1）。

設定（「ミッション中は画面を明るくする」）を OFF にすると、
明るさも色も動かさない。色だけ勝手に動かすことはしない。

**元の明るさに必ず戻すこと。** 戻さないとユーザーは自分で設定を変えるまで眩しいままになる。
`MissionView` の `onDisappear` で戻し（進行中のランプも取り消す）、
二重に呼ばれても最初の値を失わないようにしている。

### 音の立ち上がり（フェードイン）

苦痛の大きさは音量そのものより**変化の急さ**で決まる。静寂から爆音へ一息で飛ばさない。

**AlarmKit には音量を操作する API が無い。** 渡せるのは音源の名前だけなので、
立ち上がりは取り込む波形そのものに焼き込む（`SoundLibrary.importSound(fadeIn:)`）。

- 開始音量は `-40dB`。完全な無音から始めると「鳴っていない」と思われる。
- **dB を直線で上げる**（振幅を直線で上げると、耳には最後だけ急に大きくなるように聞こえる）。
- 長さは切り出し画面で選ぶ（なし / 3 / 8 / 15 秒、既定 8 秒）。
- フェードは**選択範囲の半分まで**に縮める（`maximumFadeIn(forLength:)`）。
  アラーム音はシステムがループ再生するので、全体をフェードに使うと
  最大音量に達した瞬間に先頭の小さい音へ戻ってしまう。必ず後半を最大音量で残す。
- 試聴も同じように立ち上げる（`SoundPreviewPlayer.playRange(fadeIn:)`）。
  再現しないと「試聴では普通なのにアラームでは小さい」という食い違いになる。

## デザインの決まりごと

見た目の好みで色を選ばない。**色には役割が固定**されている（`Shared/WakeoutTheme.swift`）。

| 役割 | 色 | 使う場所 |
|---|---|---|
| 有効／作動中の**状態** | `#E3FF00` acid | ON のカード・行、ミッション画面の地。必ず黒文字（コントラスト比 約17:1） |
| 文字・罫線 | `#0A0A0A` ink | 全テキスト、2pt の罫線 |
| **操作できるもの** | `#0037FF` blue | CTA、選択中の曜日、トグル ON、進捗バー。必ず白文字（約7:1、WCAG AA） |
| ミッション開始直後の地 | `#FFB24D` dawn | `acid` へ移行する途中の色。単体では使わない（黒文字で約11:1） |
| 画面の地 | `#F2F2F0` paper | 背景 |
| エラー | `#D1002E` | 権限エラー、不正解、削除 |

- 状態を**色だけで伝えない**。ON/OFF は必ず文字ラベルも併記する。
- 角丸・影は使わない。構造は 2pt の罫線だけで作る。
- 時刻は `.fontWidth(.compressed)` の極太。`Theme.display(_:)` を通す。

### システム標準 UI を置き換えている箇所

角丸が固定されていたりフォントを差し替えられない標準部品は、自前に置き換えてある。

| 標準 | 置き換え先 | 理由 |
|---|---|---|
| `Toggle` | `SquareToggle` | カプセル型で角丸が固定 |
| `DatePicker(.wheel)` | `SquareTimePicker`（`UIPickerView` ラッパ） | フォントを差し替えられず、選択行が角丸カプセル |
| `Picker(.menu)` | `SquareOptionRow` | メニューが角丸 |
| `.sheet` | `.fullScreenCover` | シートの上端の角丸が固定 |
| `List` + `swipeActions` | `SwipeableRow` | iOS 26 ではアクションボタンが円形で描画され、形を変えられない |
| `Picker(.menu)`（サウンド選択） | `SquareDropdown` | メニューが角丸。既定で折りたたみ、タップで展開する作りにして選択肢が増えても縦に伸びないようにしてある |

`SquareTimePicker` は選択行の角丸ハイライトを消すために `UIPickerView` のサブビュー背景を透明にしている。内部構造に依存する箇所だが、見つからなくても表示が戻るだけで壊れないようにしてある。

なお `alert` と `confirmationDialog` は OS が描画するため角丸のまま。ここは置き換えられない。

## 同じ ID を登録し直すときは、先に取り消す

**AlarmKit は既に登録済みの ID をそのまま登録し直せない。**
編集して保存する・OFF にせず ON にし直す、といった操作は必ずこれに当たる。

拒否されたとき、アプリ側に返るのは `invalidInput`（画面には「com.apple.AlarmKit.Alarm エラー0」）
だけで、理由は分からない。本当の理由は端末のログにしか出ない。

```
リクエストID: Scheduling alarm <alarm-id>
<alarm-id>: Not scheduling an alarm with a duplicate ID
リクエストID: Failed to schedule alarm: AlarmServiceError(code: .invalidInput)
```

そのため `AlarmScheduler.schedule` は、登録済みの ID なら**先に `cancel` してから** `schedule` する。
失敗した場合も 1 度だけ取り消してやり直す（取り消しが行き渡る前に登録し直した場合のため）。

### ただし、鳴っているアラームには触らない

**`.scheduled` 以外の状態（`.alerting` / `.countdown` / `.paused`）のアラームを取り消してはいけない。**
その場で鳴り止むうえ、`schedule` の先頭の `MissionStore.reset` がミッション待ちフラグごと消すため、
**ミッションをやらずにアラームが止まる**——このアプリの前提が壊れる。

停止ボタン → `.foreground(.immediate)` でアプリが前面に出る → `scenePhase` が `.active` →
`AlarmReconciler` が走る、という流れがあるので、鳴っている最中に登録処理が走るのは例外ではなく通常。

`AlarmScheduler.schedule` は状態を見て、鳴っている最中なら**何もせず抜ける**。
`AlarmReconciler` の「無効なのに登録が残っている → 取り消す」「アプリが知らない登録 → 取り消す」も
`isRinging` で避ける
（鳴り終われば次回の実行で取り消される）。

同じ症状を追うときは次のコマンドで見る。`AlarmManager.AlarmError` は
`maximumLimitReached` しか定義されていないので、それ以外は全部この生ログが頼りになる。

```bash
xcrun simctl spawn booted log show --last 30m --predicate 'process == "mobiletimerd"' --style compact | grep -iE "Scheduling alarm|duplicate ID|Failed to schedule"
```

## ミッションが成立する仕組み

1. スケジュール時に `stopIntent: MissionGatedStopIntent(alarmID:)` を渡す。
   同時に App Group の `mission_cleared_<alarmID>` を落とす。
2. アラート画面の停止ボタン → Intent の `perform()`。
   `supportedModes = .foreground(.immediate)` なのでアプリが強制的に前面に出る。
3. `perform()` はクリアフラグが false なら **`stop(id:)` を呼ばない**。
   代わりに `pending_mission_alarm_id` を書く。アラームは鳴り続ける。
4. アプリ側の `MissionCoordinator` がそれを検知して `MissionView` を
   `fullScreenCover` で表示（スワイプで閉じられない）。
5. ミッション成功 → `MissionCoordinator.completeMission()` が
   フラグを立てて `AlarmManager.shared.stop(id:)` を呼び、はじめて停止する。

### アプリを落として逃げられないようにする（`MissionWatchdog`）

停止ボタンを押すと、**アラート自体はその場で消える**（アプリが `stop` を呼ばなくても）。
このときアプリを落とされると、アプリのコードは二度と動かない。
ミッション待ちのフラグを立てただけでは、アプリを開かない限り何も起きない
＝**アプリを落とすだけでミッションを回避できる**。

そこで停止ボタンが押された瞬間（`MissionGatedStopIntent.perform` の未クリア分岐）に、
`.fixed(30 秒後)` の再アラームを AlarmKit へ預ける。
予約を持っているのはシステムなので、アプリを落としても時間が来れば鳴る。

再アラームの停止ボタンにも同じ `MissionGatedStopIntent`（対象は**本来のアラーム ID**）を載せてあるため、
押すたびに見張りが張り直され、ミッションをクリアするまで終わらない。

関連して守るべきこと。

- 見張りが鳴っているときに解かせるのは**本来のアラームのミッション**（`missionTarget(forAlerting:)`）。
  見張りの ID で画面を出すと、停止する相手も起床記録も取り違える。
- ミッションが片付いたら必ず `disarm()`。`cancel` は予約を消すだけなので `stop` も試す
  （見張り自身が鳴っている最中にクリアされることがある）。
- `refresh()` が「登録の無い ID のフラグを捨てる」処理は、**見張りがある間は行わない**。
  停止ボタンを押した後、対象が単発アラームだと AlarmKit 側から消えるため、捨てると逃げ道になる。

### アプリが知らない登録を掃除する

`AlarmReconciler` は SwiftData のアラームを直すだけでなく、
**SwiftData に無いのに AlarmKit 側に残っている登録**も取り消す。
保存の失敗やクラッシュで発生し、一覧に出ないのでユーザーには消す手段が無いまま鳴り続ける。

触ってはいけないものが 2 つある。

- **見張りの再アラーム**（`MissionWatchdog`）は意図的に SwiftData を持たない。
  消すと逃走防止が無効になる。
  そのため `arm()` は**登録する前に** ID を App Group へ書く。
  順番が逆だと、その隙にこの掃除が走って消えてしまう。
- **鳴っている最中のアラーム**は、消すとミッションを通さずに止まる（`isRinging` で避ける）。

さらにミッション待ちの間は掃除自体を行わない。その瞬間だけ現れる登録を巻き込む余地を残さないため。

### ミッション中のアプリ制限（`ScreenTimeGuard`）

ミッションをクリアするまで、選んだアプリを開けなくする。
`ManagedSettings` の遮断は**システム側に残る**ので、アプリを終了しても解除されない。
`MissionWatchdog` と同じく「アプリを落として逃げる」に効く。

**既定では無効。有効化には有料の Apple Developer Program が要る。**

Family Controls の権限は**無料アカウント（Personal Team）には下りない**。
宣言したまま実機へ入れようとすると、プロファイルに権限が無いためインストールに失敗する。
そのため `Wakeout.entitlements` では既定で外し、コメントとして残してある。

有料アカウントで使う場合の手順。

1. `Wakeout.entitlements` の `com.apple.developer.family-controls` のコメントを外す
2. Wakeout ターゲットの Signing & Capabilities で **Family Controls** を追加する
3. App Store で配布する場合は、さらに Apple への申請と承認が要る（Distribution 版の権限）

コード側は権限の有無に関わらずそのままでよい。
`ScreenTimeGuard` は許可が取れなければ何もしないので、権限が無いビルドでも
アラームとミッションの動作には一切影響しない。

> **シミュレータでは確認できない。** `AuthorizationCenter` の許可が通らないため、
> 設定を ON にしても何も制限されない。実機でのみ動作する。

制限の設計で外してはいけない点。

- **全アプリを一括で遮断しない。** Wakeout 自身まで開けなくなると、ミッションを解く手段が消える。
  `FamilyActivityPicker` でユーザーに選ばせ、選ばれたものだけを遮断する。
- **解除の経路を必ず用意する。** 遮断はシステム側に残るので、外し忘れるとユーザーは自力で戻せない。
  ミッション達成時 (`finish`)、ミッション待ちでないと分かったとき (`clearPendingState`)、
  設定を OFF にしたときの 3 か所で必ず `unshield()` する。
  起動のたびに `refresh()` を通るので、異常終了しても次の起動で解除される。

強制終了して再起動しても止まらないよう、復帰トリガーを 2 系統持たせています。

- App Group に残った `pending_mission_alarm_id`
- `AlarmManager.alarmUpdates` / `AlarmManager.alarms` で観測した `.alerting` 状態

どちらも `scenePhase == .active` のたびに再評価されます。

### 停止に失敗したときの逃げ道

`fullScreenCover` はユーザーの操作では閉じられないため、
**ミッションをクリアしたのに停止に失敗すると、そこから出られなくなる**。
`completeMission` はこれを避けるために失敗を 2 つに分ける。

- 対象が `.alerting` **でない**（古い `pending_mission_alarm_id` が残っていた等）
  → 止める相手が居ないだけなので、記録を残して正常に画面を閉じる。
- 対象が本当に鳴っている → クリア済みフラグは**落とさない**。
  こうしておけばアラート画面の停止ボタン（`MissionGatedStopIntent`）が素通しで停止できる。
  画面にはその手順を出す。

そもそも出さないために、`refresh()` は AlarmKit に登録が無い ID のフラグを捨てる。

## 実機での確認手順（推奨順）

1. 数分後の時刻でアラームを作成し、画面を消して待つ。
2. アラートが出たら **停止ボタンを押してもアラームが止まらない**ことを確認。
   → アプリが前面に出てミッション画面が表示される。
3. ミッション画面のままアプリを強制終了 → 再起動しても
   ミッション画面に戻され、アラームが鳴り続けることを確認。
4. ミッションをクリアして停止することを確認。
5. 記録画面（ヘッダーの時計）に 1 件増え、統計とグラフに反映されることを確認。
6. 設定画面（ヘッダーの歯車）で就寝リマインダーを ON にし、
   「次の通知」の予告が出ることを確認。実際の配信は予定時刻まで待つ必要がある。

## 仕様に対する差分・制約

実装するうえで、指示どおりにできなかった点が 3 つあります。

### 1. サウンド選択は「システム標準サウンド一覧」にできない

AlarmKit が受け取れるのは `AlertConfiguration.AlertSound` で、
用意されている API は `.default` と `.named(_:)` の 2 つだけです。
**iOS のシステム標準サウンドを列挙・選択させる API は存在しません。**

そのため音源は次の 2 経路で増やします（詳細は「アラーム音の増やし方」）。

### 2. 停止ボタンのラベル「停止」は iOS 26.1 以降では反映されない

`AlarmPresentation.Alert.stopButton` は iOS 26.1 で deprecated になり、
「このプロパティはもう使われない」と明記されています。停止ボタンはシステムが描画します。
iOS 26.0 でのみ「停止」ラベルが効くよう `#available` で分岐させています
（`Alarm/AlarmScheduler.swift` の `presentation(for:)`）。

### 3. `repeatDays` の永続化はビットマスク

指示の `Set<Int>` をそのまま SwiftData のストアド属性にはせず、
`repeatDaysMask: Int` として保存しています。読み書きは `repeatDays: Set<Int>` を
通すので使い勝手は変わりません。コレクション型を直接永続化するよりマイグレーション耐性が高いためです。

なお、指示のコード片にあった `static var title` / `UUID(uuidString:)!` は
Swift 6 の strict concurrency ではコンパイルが通らない・クラッシュしうるため、
`static let` と `guard let` に変更しています。

## スコープ外（未実装）

指示どおり、以下は実装していません。

- 写真撮影ミッション / Apple Watch 腕振りミッション
- Screen Time API（FamilyControls）による他アプリのロック
- ミッション失敗時のペナルティ演出
- iCloud による複数端末同期
