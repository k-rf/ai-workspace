# エナジースコア（Daily Readiness Score）推定リファレンス

Fitbit / Google Health アプリに表示される「エナジースコア（英語名 Daily Readiness Score、`1〜100`）」はアプリ側の独自算出指標であり、Google Health API v4（`ghealth` CLI の全 40 データ型）には公開されていません。

本リファレンスは、`ghealth` から読み取り専用で取得できる 4 つのデータ型のみを用いてエナジースコアを再現・推定する計算モデルを定義します（連続 69 日間の実測値で検証：$R^2 = 0.976$、平均絶対誤差 MAE `1.22 点`、LOOCV MAE `1.35 点`、`±2 点`以内一致率 `88%`）。実装は [`../scripts/energy-score.py`](../scripts/energy-score.py) に抽出しています。

> **提示時の注意**: ユーザーへ数値を伝える際は、API 非公開指標を実測キャリブレーション式から算出した**推定値**である旨を明記してください。

---

## 1. 実行方法

スクリプト [`../scripts/energy-score.py`](../scripts/energy-score.py) が `TZ=Asia/Tokyo` で必要な `ghealth` データを読み取り専用で取得し、推定エナジースコアと内訳を算出します。

```bash
uv run python .agents/skills/ghealth-vitals/scripts/energy-score.py          # 直近7日間
uv run python .agents/skills/ghealth-vitals/scripts/energy-score.py --days 1 # 当日のみ
```

---

## 2. 入力データ型と必要取得期間

算出対象日 $t$（起床日、JST `YYYY-MM-DD`）に対し、**前 28 日間（$t-28 \sim t-1$）のベースライン**、**当日含む直近 7 日間（$t-6 \sim t$）の睡眠**、および**前日（$t-1$）の AZM** を使用します。

| データ型 ID | 操作 | 使用フィールドと扱い | 必要スコープ（`readonly`） |
| :--- | :--- | :--- | :--- |
| `daily-heart-rate-variability` | `list` | `date`, `averageHeartRateVariabilityMilliseconds`（数値 `ms`） | `health_metrics_and_measurements.readonly` |
| `daily-resting-heart-rate` | `list` | `date`, `beatsPerMinute`（文字列型 `int64` → 整数へ変換） | `health_metrics_and_measurements.readonly` |
| `sleep` | `list` | `end` の日付（`YYYY-MM-DD`）ごとに `minutesAsleep` を合算し時間単位（`÷ 60`）へ変換 | `sleep.readonly` |
| `active-zone-minutes` | `daily-rollup` | `date`, `sumInFatBurnHeartZone + sumInCardioHeartZone + sumInPeakHeartZone`（※1） | `activity_and_fitness.readonly` |

※1 `ActiveZoneMinutesRollupValue` の `sumInCardioHeartZone`・`sumInPeakHeartZone` は API 側で既に 2 倍換算済みの AZM 値（文字列型 `int64`）として返るため、3 フィールドをそのまま整数加算します（さらに 2 倍しないでください）。`daily-rollup` の取得上限は 1 リクエスト最大 90 日間です。

---

## 3. 算出式

### Step 1: 前 28 日間ベースラインによる正規化

対象日 $t$ の前 28 日間（$t-28 \sim t-1$、当日 $t$ は含めない）の標本平均 $\mu$ と標本標準偏差 $\sigma$（不偏標準偏差、$N-1$ 割り）を計算します。

$$z_{\text{HRV}} = \frac{\text{HRV}_t - \mu_{\text{HRV}, 28\text{d}}}{\sigma_{\text{HRV}, 28\text{d}}}$$

$$z_{\text{RHR}} = -\frac{\text{RHR}_t - \mu_{\text{RHR}, 28\text{d}}}{\sigma_{\text{RHR}, 28\text{d}}} \quad \text{（低いほどプラス）}$$

### Step 2: 直近 7 日間の指数加重平均睡眠時間 $S_{\text{ewma}}$

日次総睡眠時間 $S_d$（時間単位、`minutesAsleep` 合算 `÷ 60`）について、当日 $t$ から 6 日前までの指数加重平均（減衰率 `0.6`）をとります。

$$S_{\text{ewma}} = \frac{\sum_{k=0}^{6} 0.6^k \, S_{t-k}}{\sum_{k=0}^{6} 0.6^k}$$

### Step 3: HRV ティア $k_{\text{HRV}}$（階段関数）

HRV は連続比例ではなく、ベースライン（$z_{\text{HRV}} = 0$）および約 $\pm 0.95\sigma,\ \pm 1.56\sigma,\ -2.18\sigma$ 付近を境に段階状（1 段あたり `10.5 点`）に効きます。

$$k_{\text{HRV}} = \left\lfloor \operatorname{sign}(z_{\text{HRV}}) \cdot \left(\frac{|z_{\text{HRV}}|}{0.95}\right)^{1.4} \right\rfloor$$

- $z_{\text{HRV}} \in [-0.95,\ 0) \implies k_{\text{HRV}} = -1$（ベース `55 点` 帯）
- $z_{\text{HRV}} \in [0,\ +0.95) \implies k_{\text{HRV}} = 0$（ベース `65〜66 点` 帯）
- $z_{\text{HRV}} \in [+0.95,\ +1.56) \implies k_{\text{HRV}} = +1$（ベース `76〜79 点` 帯）
- $z_{\text{HRV}} \ge +1.56 \implies k_{\text{HRV}} \ge +2$（上限 `90 点` 帯）

### Step 4: 総合スコアと前日超高負荷キャップ

$$S_{\text{raw}} = \min\!\left(90,\ 65.5 + 10.5\,k_{\text{HRV}} + 2.5\,z_{\text{RHR}} + 1.8\,\min\!\left(0,\ S_{\text{ewma}} - 6.5\right)\right)$$

前日のアクティブゾーン時間 $\text{AZM}_{t-1} \ge 250$ の場合、翌朝の HRV が高くても「非常に良好」下限の `65 点` で頭打ちになります。

$$\text{Score} = \begin{cases} \min\!\left(65,\ \mathrm{round}(S_{\text{raw}})\right) & (\text{AZM}_{t-1} \ge 250) \\ \mathrm{clamp}\!\left(\mathrm{round}(S_{\text{raw}}),\ 1,\ 100\right) & (\text{それ以外}) \end{cases}$$

### スコア区分

| スコア範囲 | 区分（日本語 UI / 英語 UI） | 解釈の目安 |
| :--- | :--- | :--- |
| `65〜100` | **非常に良好**（High） | 十分に回復しており、高めの運動負荷に適した状態 |
| `30〜64` | **良好**（Moderate） | 標準的な回復状態。通常の活動・中程度の運動向け |
| `1〜29` | **低**（Low） | 疲労・睡眠不足・負荷蓄積が大きい状態。休息や回復優先 |

---

## 4. モデルの精度特性と限界

- **量子化誤差による理論下限（約 `±1 点`）**: `daily-resting-heart-rate` の `beatsPerMinute` が整数値丸めで返るため、`±0.5 bpm` の丸め差だけで計算値に `±0.7 点` 前後の揺らぎが生じます。また $z_{\text{HRV}}$ がティア境界（$0,\ \pm 0.95,\ \pm 1.56$ 付近）ギリギリにある日は、アプリ内部の小数精度との差で 1 段ズレる場合があります。
- **極端な不調領域（`30 点`未満）の非線形性**: $z_{\text{RHR}} < -2.0$ のような大幅な安静時心拍悪化時や、昼夜逆転・大幅な中途覚醒など睡眠構造自体が大きく崩れた日では、実測スコアが本式の推定値より急激に低下する傾向があります。
- **ウォームアップ期間**: 装着開始直後など前 28 日間のデータが揃っていない場合（最低 7 日以上、推奨 28 日間）はベースラインの標準偏差が不安定になるため、参考値として扱ってください。

---

## 5. 公式リファレンス

- Vitals ガイド: https://developers.google.com/health/data-types/vitals
- Sleep ガイド: https://developers.google.com/health/data-types/sleep
- `users.dataTypes.dataPoints` リファレンス: https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints
- `ActiveZoneMinutesRollupValue` リファレンス: https://developers.google.com/health/reference/rest/v4/ActiveZoneMinutesRollupValue
