"""Estimate Fitbit / Google Health Energy Score (Daily Readiness) via ghealth CLI."""

from __future__ import annotations

import argparse
import json
import math
import os
import statistics
import subprocess
from collections import defaultdict
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

TZ_NAME = "Asia/Tokyo"


def fetch_points(data_type: str, op: str, from_date: str, to_date: str) -> list[dict]:
    env = {**os.environ, "TZ": TZ_NAME}
    cmd = ["ghealth", "data", data_type, op, "--from", from_date, "--to", to_date]
    res = subprocess.run(cmd, capture_output=True, text=True, env=env, check=True)
    return json.loads(res.stdout).get("dataPoints", [])


def category(score: int) -> str:
    if score >= 65:
        return "非常に良好"
    return "良好" if score >= 30 else "低"


def main() -> None:
    parser = argparse.ArgumentParser(description="Estimate Energy Score from ghealth data.")
    parser.add_argument("--days", type=int, default=7, help="Number of recent days to output.")
    args = parser.parse_args()

    today = datetime.now(ZoneInfo(TZ_NAME)).date()
    lookback = min(args.days + 30, 89)
    from_str = (today - timedelta(days=lookback)).isoformat()
    to_str = today.isoformat()

    hrv = {
        p["date"]: float(p["averageHeartRateVariabilityMilliseconds"])
        for p in fetch_points("daily-heart-rate-variability", "list", from_str, to_str)
        if float(p.get("averageHeartRateVariabilityMilliseconds", 0)) > 0
    }
    rhr = {
        p["date"]: int(p["beatsPerMinute"])
        for p in fetch_points("daily-resting-heart-rate", "list", from_str, to_str)
        if int(p.get("beatsPerMinute", 0)) > 0
    }
    sleep_min: dict[str, int] = defaultdict(int)
    for p in fetch_points("sleep", "list", from_str, to_str):
        sleep_min[p["end"][:10]] += int(p.get("minutesAsleep", 0))
    azm = {
        p["date"]: int(p.get("sumInFatBurnHeartZone", 0))
        + int(p.get("sumInCardioHeartZone", 0))
        + int(p.get("sumInPeakHeartZone", 0))
        for p in fetch_points("active-zone-minutes", "daily-rollup", from_str, to_str)
    }

    ewma_den = sum(0.6**k for k in range(7))
    for d in sorted(set(hrv) & set(rhr))[-args.days :]:
        dt = datetime.strptime(d, "%Y-%m-%d").date()
        vh = [hrv[s] for k in range(1, 29) if (s := (dt - timedelta(days=k)).isoformat()) in hrv]
        vr = [rhr[s] for k in range(1, 29) if (s := (dt - timedelta(days=k)).isoformat()) in rhr]
        if len(vh) < 7 or len(vr) < 7:
            continue

        zh = (hrv[d] - statistics.mean(vh)) / statistics.stdev(vh)
        zr = -(rhr[d] - statistics.mean(vr)) / statistics.stdev(vr)
        s_ewma = (
            sum(
                (0.6**k) * (sleep_min.get((dt - timedelta(days=k)).isoformat(), 0) / 60.0)
                for k in range(7)
            )
            / ewma_den
        )
        k_hrv = math.floor(math.copysign((abs(zh) / 0.95) ** 1.4, zh))
        s_raw = min(90.0, 65.5 + 10.5 * k_hrv + 2.5 * zr + 1.8 * min(0.0, s_ewma - 6.5))
        prev_azm = azm.get((dt - timedelta(days=1)).isoformat(), 0)

        raw_rounded = round(s_raw)
        capped = prev_azm >= 250 and raw_rounded > 65
        score = max(1, min(100, 65 if capped else raw_rounded))
        cap_note = " [AZM cap]" if capped else ""
        print(
            f"{d}: {score:2d} ({category(score)}) | "
            f"k_HRV={k_hrv:+d} (z={zh:+.2f}), z_RHR={zr:+.2f}, "
            f"S_ewma={s_ewma:.2f}h, prev_AZM={prev_azm}{cap_note}"
        )


if __name__ == "__main__":
    main()
