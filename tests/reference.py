# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
"""Independent Python reference for SMC Zones, bar by bar. Swings, sweeps, BOS/CHoCH, order block and FVG
written as a closed-bar state machine.

Everything at bar i is decided from bars <= i only; the last bar of the array is the forming bar and is never used.
A zone's creation bar and mitigation bar, once set, never change.

Rules (dir +1 = bullish, -1 = bearish):
  ATR       Wilder (RMA) of the true range, seeded with the SMA of the first `atr` values.
  swing     bar p is a swing high (low) if each of the `swing` bars to its left has a strictly lower high (higher low)
            and each of the `swing` bars to its right a high not above (low not below). Known at bar p + swing.
  BOS/CHoCH a close beyond the newest unbroken swing high (low). CHoCH when the previous break went the other way,
            otherwise BOS. The first break ever is a BOS.
  order block  the zone left by a break: org = lowest low (highest high) bar from the broken swing to the break bar.
            If org is a candle against the move (bearish candle for a bullish break), the OB candle is the last of the
            run of against-candles starting at org, else the nearest against-candle among the 3 bars before org, else org.
            Bullish zone: top = high[ob], bot = min(low[ob], low[org]); bearish: top = max(high[ob], high[org]),
            bot = low[ob]. Drawn from the earlier of ob/org.
  FVG       bars i-2, i, gap = low[i] - high[i-2] (bullish) or low[i-2] - high[i] (bearish) >= fvg_min * ATR[i].
  sweep     a bar wicks beyond an unswept swing (confirmed, at most `sweep_look` bars old) by >= sweep_min * ATR and
            closes back inside: the lowest low (highest high) such swing is reported. Every swing wicked through is
            marked taken whether or not the bar closed back inside.
  mitigation (bars after the zone's creation bar), modes: 0 touch (wick reaches the near edge), 1 midpoint (wick reaches
            the middle), 2 far-edge wick, 3 far-edge close. Midpoint is inclusive within a relative 1e-10.
  touch     a bar whose wick reaches the near edge of a live zone that was not inside on the bar before.
  session   optional: zones and sweeps are only created on bars whose open hour (server time) is inside [start, end).
Per bar the order is: mitigation/touch of older zones, sweeps, FVG, break + order block, then the swing `swing` bars back."""
import numpy as np

NAN = np.nan


def true_range(h, l, c):
    tr = h - l
    tr[1:] = np.maximum(tr[1:], np.maximum(np.abs(h[1:] - c[:-1]), np.abs(l[1:] - c[:-1])))
    return tr


def rma(x, n):
    out = np.full(len(x), NAN)
    if len(x) < n:
        return out
    out[n - 1] = x[:n].mean()
    for i in range(n, len(x)):
        out[i] = (out[i - 1] * (n - 1) + x[i]) / n
    return out


def in_session(t, start, end):
    hr = (int(t) // 3600) % 24
    if start == end:
        return True
    return start <= hr < end if start < end else (hr >= start or hr < end)


def mitigated(z, mode, o, h, l, c):
    """Does this bar mitigate zone z?"""
    top, bot = z["top"], z["bot"]
    mid = (top + bot) / 2.0
    tol = abs(mid) * 1e-10        # a wick exactly on the midpoint counts; (top+bot)/2 can be 1 ulp off in decimals
    if z["dir"] > 0:
        return {0: l <= top, 1: l <= mid + tol, 2: l <= bot, 3: c < bot}[mode]
    return {0: h >= bot, 1: h >= mid - tol, 2: h >= top, 3: c > top}[mode]


def smc_zones(t, o, h, l, c, swing=3, atr=14, fvg_min=0.20, ob_mit=3, fvg_mit=2, sweep_look=60, sweep_min=0.10,
              use_session=False, sess_start=7, sess_end=17):
    n = len(c)
    A = rma(true_range(h, l, c), atr)
    nan = lambda: np.full(n, NAN)
    out = {k: nan() for k in ("ob_bull_top", "ob_bull_bot", "ob_bear_top", "ob_bear_bot", "fvg_bull_top", "fvg_bull_bot",
                              "fvg_bear_top", "fvg_bear_bot", "struct", "level", "sweep_bull", "sweep_bear",
                              "mitigated", "touched", "active_bull", "active_bear")}
    zones, swings, breaks, sweeps, live = [], [], [], [], []
    newest = {1: None, -1: None}      # newest swing per side (side +1 = high)
    trend = 0
    swept_at = {1: -1, -1: -1}

    def is_swing(p, side):
        for k in range(1, swing + 1):
            if side > 0 and (h[p - k] >= h[p] or h[p + k] > h[p]):
                return False
            if side < 0 and (l[p - k] <= l[p] or l[p + k] < l[p]):
                return False
        return True

    def far(i, d):
        return l[i] if d > 0 else h[i]

    def near(i, d):
        return h[i] if d > 0 else l[i]

    def against(i, d):
        return c[i] < o[i] if d > 0 else c[i] > o[i]

    for i in range(n - 1):                      # the last bar is still forming
        ok_atr = not np.isnan(A[i]) and A[i] > 0
        if ok_atr:
            a = A[i]
            sess = (not use_session) or in_session(t[i], sess_start, sess_end)
            # 1. older zones: mitigated or touched
            n_mit = n_touch = 0
            for z in live:
                if z["born"] >= i:
                    continue
                mode = ob_mit if z["kind"] == "ob" else fvg_mit
                if mitigated(z, mode, o[i], h[i], l[i], c[i]):
                    z["end"] = i
                    n_mit += 1
                    continue
                d = z["dir"]
                inside = (l[i] <= z["top"]) if d > 0 else (h[i] >= z["bot"])
                if inside and not z["inside"]:
                    z["touches"] += 1
                    n_touch += 1
                z["inside"] = inside
            live[:] = [z for z in live if z["end"] is None]
            out["mitigated"][i], out["touched"][i] = n_mit, n_touch
            # 2. sweeps
            for d in (1, -1):
                side, best = -d, None
                for s in reversed(swings):
                    if i - s["i"] > sweep_look:
                        break
                    if s["side"] != side or s["swept"]:
                        continue
                    if (far(i, d) - (s["p"] - d * sweep_min * a)) * d < 0:
                        s["swept"] = True
                        if (c[i] - s["p"]) * d > 0 and (best is None or s["p"] * d < best["p"] * d):
                            best = s
                if best is not None:
                    swept_at[d] = i
                    if sess:
                        out["sweep_bull" if d > 0 else "sweep_bear"][i] = best["p"]
                        sweeps.append(dict(dir=d, level=best["p"], at=i, frm=best["i"]))
            # 3. fair value gap
            if i >= 2:
                for d in (1, -1):
                    gap = (l[i] - h[i - 2]) if d > 0 else (l[i - 2] - h[i])
                    if gap >= fvg_min * a and sess:
                        top, bot = (l[i], h[i - 2]) if d > 0 else (l[i - 2], h[i])
                        zones.append(dict(kind="fvg", dir=d, top=top, bot=bot, t0=i - 1, born=i, end=None,
                                          touches=0, inside=False))
                        live.append(zones[-1])
                        k = "fvg_bull" if d > 0 else "fvg_bear"
                        out[k + "_top"][i], out[k + "_bot"][i] = top, bot
            # 4. structure break and order block
            for d in (1, -1):
                s = newest[d]
                if s is None or s["broken"] or (c[i] - s["p"]) * d <= 0:
                    continue
                s["broken"] = True
                choch = trend == -d
                trend = d
                org = s["i"]
                for j in range(s["i"], i + 1):
                    if (far(j, d) - far(org, d)) * d < 0:
                        org = j
                ob = -1
                if against(org, d):
                    ob = org
                    while ob + 1 < i and against(ob + 1, d):
                        ob += 1
                else:
                    for j in range(org - 1, max(0, org - 3) - 1, -1):
                        if against(j, d):
                            ob = j
                            break
                if ob < 0:
                    ob = org
                if d > 0:
                    top, bot = h[ob], min(l[ob], l[org])
                else:
                    top, bot = max(h[ob], h[org]), l[ob]
                if sess:
                    zones.append(dict(kind="ob", dir=d, top=top, bot=bot, t0=min(ob, org), born=i, end=None,
                                      touches=0, inside=False))
                    live.append(zones[-1])
                    k = "ob_bull" if d > 0 else "ob_bear"
                    out[k + "_top"][i], out[k + "_bot"][i] = top, bot
                out["struct"][i] = d * (2 if choch else 1)
                out["level"][i] = s["p"]
                breaks.append(dict(dir=d, choch=choch, level=s["p"], frm=s["i"], at=i))
            out["active_bull"][i] = sum(1 for z in live if z["dir"] > 0)
            out["active_bear"][i] = sum(1 for z in live if z["dir"] < 0)
        # 5. the swing `swing` bars back is known from the next bar on
        p = i - swing
        if p >= swing:
            for side in (1, -1):
                if is_swing(p, side):
                    s = dict(i=p, p=h[p] if side > 0 else l[p], side=side, swept=False, broken=False)
                    swings.append(s)
                    newest[side] = s
    return out, zones, breaks, sweeps
