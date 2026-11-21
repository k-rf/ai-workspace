---
name: ghealth-vitals
description: ai-workspace 環境で `ghealth` CLI（Google Health API v4）を使い、心拍数・安静時心拍数・心拍変動（HRV）・血中酸素飽和度（SpO2）・呼吸数・体温（深部体温・睡眠時皮膚温変動）・血糖値・心電図（ECG）・不規則脈波通知（IRN）・体重・体脂肪・身長などのバイタル情報を取得・集計し、エナジースコア（レディネススコア）の推定も行う。ユーザーが体調・今日のコンディションやバイタルデータの確認、エナジースコア／レディネススコアの算出、日次推移のサマリー、Fitbit / Pixel Watch 等の健康指標の取得を依頼したときに使用する。
---
# Google Health Vitals CLI (`ghealth`)

Google Health API v4（40 データ型対応、デフォルト出力は簡略化 JSON）をラップした `ghealth` CLI を使い、バイタル情報を**読み取り専用**で取得・集計するためのスキルです。

## 1. 事前確認：バイナリ・認証・タイムゾーン

1. **バイナリの確認**:
   - Dev Container 環境では `/usr/local/bin/ghealth` に配置されています。
   ```bash
   command -v ghealth && ghealth --version
   ```
2. **認証状態の確認（トークンや秘密情報を出力しない）**:
   ```bash
   ghealth auth status
   ```
   - `"authenticated": true`・`"expired": false`・必要な `"scopes"` が含まれていることを確認します。
   - `ghealth auth status` は `--validate` なしではローカル保存状態のみを確認します。API 呼び出しで認証エラーが出る場合や失効が疑われる場合は `ghealth auth status --validate` で検証し、期限切れなら `ghealth auth refresh` を実行してください。
   - **未認証またはスコープ不足の場合**（ヘッドレス／Dev Container 環境。設定ディレクトリは `~/.config/ghealth/`）:
     - 初回セットアップ手順の確認: `ghealth setup --instructions`
     - 再認証フロー:
       1. `ghealth auth login --non-interactive --scopes-preset readonly` を実行し、出力 JSON の `auth_url` をユーザーへ共有する。
       2. ブラウザで承認後、リダイレクト先 URL から取得した `code` を受け取り、`ghealth auth login --complete <code>` を実行する。
   - **Remote Agents ネットワーク許可ホスト**: Turbo モード以外で実行する場合、`health.googleapis.com`（OAuth 更新・検証には `oauth2.googleapis.com` / `www.googleapis.com`）への送信を許可する必要があります。
3. **【重要】タイムゾーンと日付上限の仕様**:
   - コンテナ環境はデフォルト `UTC`（`TZ` 未設定）です。`ghealth config show` で `timezone` が未設定の場合、`--from today` や裸の `YYYY-MM-DD` は UTC 基準で解釈され、日本時間（JST, UTC+9）と 9 時間ズレます。
   - 日本時間などユーザーのローカル時間基準で取得する場合は、**実行時に `TZ=Asia/Tokyo` を付ける**か、**RFC 3339 オフセット付き時刻**（例：`2026-11-20T00:00:00+09:00`）を指定してください（`ghealth config set timezone ...` をユーザー承認なしに書き換えないでください）。
   - **上限（`--to`）の解釈差**:
     - 裸の日付（`--to 2026-11-20`, `--to today`）: その日の終わりまで **inclusive**（翌日 `00:00` 未満 `<`）に展開されます。
     - 時刻付き RFC 3339（`--to 2026-11-20T23:59:59+09:00`）: **exclusive**（`<`）としてそのままフィルタされます。

## 2. 探索ファースト＆取得方式の選択

データ型 ID・対応操作・フィールド名・フィルタ形式を推測せず、まずローカルスキーマや `--dry-run` で確認します。

```bash
ghealth schema types                    # 全40データ型の一覧と対応操作
ghealth schema type heart-rate          # 指定データ型のフィールド・パラメータ詳細
ghealth schema scopes                   # OAuth スコープ一覧と対応データ型
```

HTTP リクエストや日付・タイムゾーン展開を送信前に確認したい場合は `--dry-run` を付けます。

### コマンド選択の優先順位

1. **日次サマリー型（`daily-*`）を最初に使う**:
   - 複数日のトレンドや体調把握では、まず `daily-resting-heart-rate`・`daily-heart-rate-variability`・`daily-oxygen-saturation`・`daily-respiratory-rate`・`daily-sleep-temperature-derivations` 等を取得します。
2. **高頻度サンプルの集計には `daily-rollup` / `rollup` を使う**:
   - `heart-rate`（最大 1 秒粒度）や `oxygen-saturation`（1 分粒度）を長期間 `list` すると件数が膨大になります。日次・時間別の傾向把握には `daily-rollup` や `rollup --window-size 3600s` を優先してください。
3. **重複排除には `reconcile`、生レコード・ページングには `list` を使う**:
   - `list`: 全データソースの生レコードを返すため、複数デバイス／アプリ由来の重複や未装着区間を含み得ます。デフォルト `--limit 500` で、続きはレスポンスの `nextPageToken` を `--page-token` に渡します。
   - `reconcile`: Google Health API 側でソース優先度解決・重複排除・未装着区間除外を行った統合ストリームを返します。ただし `--limit` / `--page-token` がないため、高頻度データ（`heart-rate` 等）は短期間（1 日など）に絞って実行してください。

### 大容量出力の制御とフォーマット

- `heart-rate list` や `electrocardiogram list`（`waveformSamples` 配列を含む）等は `-o /tmp/ghealth-<type>.json` で `/tmp/` へ書き出し（stdout にはサマリーのみ出力）、`jq` や `uv run python` で必要フィールドだけを抽出してください。
- デフォルトは簡略化 JSON（フラットな時刻・コンパクトなソース表記）です。元の API レスポンスが必要な場合のみ `--raw`、簡易表や CSV が必要な場合は `-f table` / `-f csv` を指定します。

## 3. バイタルデータ型リファレンスと主な操作パターン

### A. 日次バイタルサマリー（優先利用）

| データ型 ID | 内容・主なフィールド | 対応操作 | 必要スコープ（`readonly`） |
| :--- | :--- | :--- | :--- |
| `daily-resting-heart-rate` | 安静時心拍数（`beatsPerMinute`） | `list`, `reconcile` | `health_metrics_and_measurements.readonly` |
| `daily-heart-rate-variability` | 日次 HRV（`averageHeartRateVariabilityMilliseconds`, 深睡眠 RMSSD, 非 REM 心拍） | `list`, `reconcile` | `health_metrics_and_measurements.readonly` |
| `daily-oxygen-saturation` | 日次 SpO2（`averagePercentage`, 信頼区間上下限 `%`） | `list`, `reconcile` | `health_metrics_and_measurements.readonly` |
| `daily-respiratory-rate` | 日次呼吸数（`breathsPerMinute`） | `list`, `reconcile` | `health_metrics_and_measurements.readonly` |
| `daily-sleep-temperature-derivations` | 睡眠時皮膚温と 30 日ベースライン（`nightlyTemperatureCelsius`, `baselineTemperatureCelsius` ℃） | `list`, `reconcile` | `health_metrics_and_measurements.readonly` |
| `daily-heart-rate-zones` | 日次心拍ゾーン定義（`heartRateZones`）※**`reconcile` のみ・`list` 非対応** | `reconcile` | `health_metrics_and_measurements.readonly` |
| `daily-vo2-max` | 日次 VO2 max サマリー | `list`, `reconcile` | `activity_and_fitness.readonly` |

### B. 高頻度・随時計測バイタル（サンプル型）

| データ型 ID | 内容・主なフィールド | 対応操作 | 必要スコープ（`readonly`） |
| :--- | :--- | :--- | :--- |
| `heart-rate` | 心拍数（`beatsPerMinute`, 1 秒粒度あり） | `list`, `rollup`, `daily-rollup`, `reconcile` | `activity_and_fitness.readonly`（※1） |
| `heart-rate-variability` | サンプル HRV（RMSSD / SD `ms`） | `list`, `reconcile` | `activity_and_fitness.readonly`（※1） |
| `oxygen-saturation` | サンプル SpO2（`percentage`, 1 分粒度） | `list`, `reconcile` | `health_metrics_and_measurements.readonly` |
| `respiratory-rate-sleep-summary` | 睡眠ステージ別呼吸数（`fullSleepStats` / `deepSleepStats` / `lightSleepStats` / `remSleepStats`） | `list`, `reconcile` | `health_metrics_and_measurements.readonly` |
| `core-body-temperature` | 深部体温（`temperatureCelsius` ℃, `measurementLocation`） | `list`, `get`, `rollup`, `daily-rollup`, `reconcile` | `health_metrics_and_measurements.readonly` |
| `blood-glucose` | 血糖値（`bloodGlucoseMilligramsPerDeciliter` mg/dL, `mealType`, `measurementTiming`, `specimen`） | `list`, `get`, `rollup`, `daily-rollup`, `reconcile` | `health_metrics_and_measurements.readonly` |

※1 `ghealth` のスコープ定義上 `heart-rate` / `heart-rate-variability` は `activity_and_fitness.readonly` に分類されていますが、Google Health API の Vitals ガイド上は `health_metrics_and_measurements.readonly` とも関連するため、両方付与した認証状態での利用を推奨します。

### C. 心電図・不整脈通知（専用スコープ）

| データ型 ID | 内容・主なフィールド | 対応操作 | 必要スコープ（`readonly`） |
| :--- | :--- | :--- | :--- |
| `electrocardiogram` | 単誘導 ECG（`resultClassification`, `beatsPerMinuteAvg`, `waveformSamples`） | `list` のみ | `ecg.readonly` |
| `irregular-rhythm-notification` | 不規則脈波通知（`alertWindows`, `medicalDeviceInfo`） | `list` のみ | `irn.readonly` |

- `electrocardiogram list` は API 仕様上 **end-time フィルタ非対応のため `--to` が無視**されます。また履歴データは UTC オフセットが欠損する場合があるため、`civilTime` ではなく `physicalTime` を参照してください。波形電圧への換算は `millivolts = sample / millivoltsScalingFactor` です。
- `irregular-rhythm-notification list` は `interval.civil_start_time` 基準でフィルタされます。

### D. 身体計測・関連コンテキスト（バイタル解釈の補助）

| データ型 ID | 内容・主なフィールド | 対応操作 | 必要スコープ（`readonly`） |
| :--- | :--- | :--- | :--- |
| `weight` | 体重（**`weightGrams` グラム単位** → kg 換算は `÷ 1000`） | `list`, `get`, `rollup`, `daily-rollup`, `reconcile`（※2） | `health_metrics_and_measurements.readonly` |
| `body-fat` | 体脂肪率（`percentage` `%`） | `list`, `get`, `rollup`, `daily-rollup`, `reconcile`（※2） | `health_metrics_and_measurements.readonly` |
| `height` | 身長（**`heightMillimeters` mm 単位** → cm 換算は `÷ 10`） | `list`, `get`, `reconcile`（※2） | `health_metrics_and_measurements.readonly` |
| `sleep` | 睡眠セッション（夜間バイタルの背景確認。`--detail` でステージ別内訳、`civil_end_time`＝起床日基準） | `list`, `get`, `reconcile`（※2） | `sleep.readonly` |
| `active-zone-minutes` | アクティブゾーン時間（`sumInFatBurn/Cardio/PeakHeartZone`、前日運動負荷の確認） | `list`, `daily-rollup`, `reconcile` | `activity_and_fitness.readonly` |

※2 書き込み系コマンド（`create` / `update` / `delete`）も存在しますが、本スキルでは使用しません。

### E. エナジースコア（レディネススコア）の推定

- Fitbit / Google Health アプリの「エナジースコア（英語名 Daily Readiness Score）」はアプリ独自指標であり、Google Health API v4 には対応データ型が存在しません。
- ユーザーがエナジースコア／レディネススコアや総合的な今日のコンディション点数を求めた場合は、数式定義を [`references/energy-score.md`](references/energy-score.md)、算出スクリプトを [`scripts/energy-score.py`](scripts/energy-score.py) から参照・実行し、推定値である旨を添えて提示してください。

> [!NOTE]
> `v4beta` のデータ型（例：`skin-temperature-sensors`）は `ghealth` v0.1.0（Google Health API v4 の 40 データ型対象）では未対応です。

### 実践コマンド例（JST 基準）

```bash
# 1. 直近期間の日次バイタルサマリーを取得（reconcile / list）
TZ=Asia/Tokyo ghealth data daily-resting-heart-rate list --from 2026-11-13 --to today
TZ=Asia/Tokyo ghealth data daily-heart-rate-variability list --from 2026-11-13 --to today
TZ=Asia/Tokyo ghealth data daily-oxygen-saturation list --from 2026-11-13 --to today
TZ=Asia/Tokyo ghealth data daily-respiratory-rate list --from 2026-11-13 --to today
TZ=Asia/Tokyo ghealth data daily-sleep-temperature-derivations list --from 2026-11-13 --to today

# 2. 心拍数の日次集計・1時間ごと集計
TZ=Asia/Tokyo ghealth data heart-rate daily-rollup --from 2026-11-13 --to today
TZ=Asia/Tokyo ghealth data heart-rate rollup --from yesterday --to today --window-size 3600s

# 3. 特定日の重複排除済み高頻度心拍（短期間に絞る）と日次心拍ゾーン
TZ=Asia/Tokyo ghealth data heart-rate reconcile --from today --to today -o /tmp/ghealth-hr-today.json
TZ=Asia/Tokyo ghealth data daily-heart-rate-zones reconcile --from 2026-11-13 --to today

# 4. ECG の取得（--to 非対応のため --from のみ。波形配列を除いてサマリー確認）
TZ=Asia/Tokyo ghealth data electrocardiogram list --from 2026-11-01 -o /tmp/ghealth-ecg.json
jq 'del(.. | .waveformSamples?)' /tmp/ghealth-ecg.json

# 5. 不規則脈波通知・体重・睡眠（ステージ詳細付き）・デバイス／設定確認
TZ=Asia/Tokyo ghealth data irregular-rhythm-notification list --from 2026-11-01 --to today
TZ=Asia/Tokyo ghealth data weight list --from 2026-11-01 --to today
TZ=Asia/Tokyo ghealth data sleep list --from yesterday --to today --detail
ghealth user paired-devices list
ghealth user settings get
```

## 4. 値の解釈・単位換算・トラブルシュート

- **単位と JSON 型の注意点**:
  - `weightGrams` はグラム（`kg = weightGrams / 1000`）、`heightMillimeters` はミリメートル（`cm = heightMillimeters / 10`）、温度は摂氏（℃）、血糖値は `mg/dL` です。
  - `beatsPerMinute`・`beatsPerMinuteAvg`・`heightMillimeters` 等の `int64` フィールドは JSON 上で**文字列型**（例: `"72"`）になるため、集計・比較前に必ず数値へパースしてください。
- **結果が空のときの確認ポイント**:
  1. タイムゾーンズレ（`TZ` 未指定で UTC 解釈になっていないか、`ghealth config show` を確認）
  2. スコープ不足やトークン失効（`ghealth auth status --validate`）
  3. ペアリング済みデバイスと対応センサー（`ghealth user paired-devices list`）
  4. 夜間系指標（HRV・SpO2・呼吸数・睡眠時皮膚温変動）は十分な睡眠記録がある日のみ算出される仕様
- **医療情報としての扱い**:
  - 取得した数値の要約・日次推移の整理のみを行い、医学的診断は行わないでください。異常値や ECG の `ATRIAL_FIBRILLATION`・IRN 検出など懸念がある場合は、医療機関への相談を案内してください。
- **公式リファレンス**:
  - Vitals ガイド: https://developers.google.com/health/data-types/vitals
  - OAuth スコープ: https://developers.google.com/health/scopes
  - Reconcile エンドポイント: https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints/reconcile

## 5. 安全ガードレールとプライバシー保護

- **読み取り専用を厳守**: `create`・`update`・`delete`（`weight` / `body-fat` / `height` / `sleep` / `exercise` 等）、`user profile/settings update`、`webhooks` 操作、`config set` による既存設定の無断変更、`auth logout` を実行しないでください。
- **認証情報の秘匿**: `ghealth auth export` や `~/.config/ghealth/credentials.json`・`client_secret.json` の内容を表示・ログ出力・コミットしないでください。
- **個人健康データ（PHI）の保護**: `-o` 等の中間ファイルは `/tmp/` にのみ保存し（リポジトリ配下へ書き出さない・コミットしない）、ユーザーの明示的な指示なく外部ツール（Notion / Linear / Gmail 等）へバイタルデータを送信しないでください。
