# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
"""Compare what MT5 drew (DumpIndicator CSVs, buffers b0..b15) with the Python reference, bar by bar.

    python3 tests/check_parity.py <dump dir>                 (needs numpy and pandas)
    python3 tests/check_parity.py <MT4 dump dir> --mt4       (the MT4 edition, dumps from the MT4 tester)

Each CONFIG is one DumpIndicator run (tag -> reference kwargs). Pass: on every closed bar every buffer is equal
(prices within 1e-9 relative, counts exactly, empty where the reference has nothing)."""
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).parent))
from reference import smc_zones  # noqa: E402

KEYS = ["ob_bull_top", "ob_bull_bot", "ob_bear_top", "ob_bear_bot", "fvg_bull_top", "fvg_bull_bot", "fvg_bear_top",
        "fvg_bear_bot", "struct", "level", "sweep_bull", "sweep_bear", "mitigated", "touched", "active_bull",
        "active_bear"]
CONFIGS = {
    "smc_default": dict(),
    "smc_touch_s5_sess": dict(swing=5, ob_mit=0, fvg_mit=1, use_session=True, sess_start=7, sess_end=16),
    "smc_far_fvg05": dict(swing=2, atr=10, fvg_min=0.5, ob_mit=2, fvg_mit=3, sweep_look=30, sweep_min=0.3),
}


def check(csv: Path, kw: dict, mt4=False) -> tuple[bool, str]:
    d = pd.read_csv(csv)
    if mt4:                            # Dump4 writes the bar time as text (server time, as MT5's epoch seconds)
        d["time"] = (pd.to_datetime(d["time"], format="%Y.%m.%d %H:%M") - pd.Timestamp(0)) // pd.Timedelta(seconds=1)
    t, o, h, l, c = (d[k].to_numpy(float) for k in ("time", "open", "high", "low", "close"))
    ref, zones, breaks, sweeps = smc_zones(t, o, h, l, c, **kw)
    closed = slice(0, len(d) - 1)
    bad, badcols = 0, []
    for j, k in enumerate(KEYS):
        mt, rf = d[f"b{j}"].to_numpy(float)[closed], ref[k][closed]
        # the reference leaves count buffers NaN before the ATR is valid, as MT5 leaves them empty
        same = np.isclose(mt, rf, rtol=1e-9, atol=0, equal_nan=True)
        if not same.all():
            bad += int((~same).sum())
            badcols.append(f"{k}:{int((~same).sum())}")
    nob = sum(z["kind"] == "ob" for z in zones)
    nfv = len(zones) - nob
    nmit = sum(z["end"] is not None for z in zones)
    ok = bad == 0
    return ok, (f"{csv.stem:34} bars {len(d):>6}  OB {nob:>4} FVG {nfv:>4} mitigated {nmit:>4} "
                f"BOS/CHoCH {len(breaks):>4} sweeps {len(sweeps):>4}  "
                f"{'all 16 buffers equal' if ok else 'DIFFER ' + ' '.join(badcols)}")


if __name__ == "__main__":
    mt4 = "--mt4" in sys.argv          # dumps written by tests/mt4/SMCZonesDump.mq4 in the MT4 Strategy Tester
    root = Path([a for a in sys.argv[1:] if a != "--mt4"][0])
    allok, n = True, 0
    for tag, kw in CONFIGS.items():
        for f in sorted(root.glob(f"{tag}_*.csv")):
            ok, msg = check(f, kw, mt4)
            allok &= ok
            n += 1
            print(("PASS " if ok else "FAIL ") + msg)
    print(f"\n{'ALL PASS' if allok and n else 'FAILURES'} ({n} files)")
    sys.exit(0 if allok and n else 1)
