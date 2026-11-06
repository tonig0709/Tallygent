# Curve chart — build 66

Choose **Curve** in Panel Settings → Large Panel Chart → Chart Style. The
existing Bar and Line modes, their stored values and their defaults stay intact.
This is a local test feature; it does not change the Insights chart or algorithm.

## What the curve means

The 12h/24h graph still shows **remaining quota percent**, not hourly consumption,
tokens or cost. Solid curves interpolate retained observations; dashed curves
estimate missing time between two valid observations in the same confirmed
quota cycle. Dashed points are not new observations and are never written back.

The curve does not cross a refill/reset, changed reset time, account/session,
source, quota pool, duration, invalid receipt, duplicate or reversed timestamp.
Unknown reset/duration cannot authorize a bridge between observed segments.
No curve is extrapolated before the first or after the last retained point.
When no points exist the existing waiting state remains; single points remain
visible as points. Fitting cannot recover the true path through an unobserved
interval, so it is not presented as a measurement or a prediction.

## Algorithm and order of work

1. A first independent Swift/Foundation implementation was completed and passed
   the pure numerical probe **before** GitHub inspiration was researched.
2. Build 66 uses local shape-preserving quintic Bézier pieces. Shared weighted
   harmonic knot slopes are limited to 1.25 times the smaller adjacent secant;
   plateau slopes remain zero. Zero endpoint accelerations give C2 joins, so
   both velocity and acceleration agree between pieces. The six ordered control
   values prevent overshoot or invented quota increases. Retained input knots
   are still interpolated exactly; this is not a global high-order polynomial.
3. A screen-sized display budget bounds work. Redundant flat knots are removed
   without changing solid/estimated provenance. Dense chains are downsampled
   before fitting with largest-triangle bucket selection to retain knees better
   than uniform thinning on irregular time scales; raw history is not changed.
   First and last retained observations remain endpoints. This is a visual
   approximation heuristic, not a global error minimum. Display approximation at a small
   budget is not a claim to pass every omitted observation exactly.
   Drawing samples now follow a bound on each piece's curvature, rather than
   elapsed time. Straight spans need no extra samples, so a short, steep change
   no longer loses its curve while flat hours consume the budget. The chord-error
   target is 0.025 percentage points when the shared sample budget permits, not
   an unconditional error guarantee under extreme display thinning. Stable
   de Casteljau evaluation stays inside the control polygon.
4. Research then compared the approach with the original
   [D3 monotone implementation](https://github.com/d3/d3-shape/blob/main/src/curve/monotone.js),
   [SciPy PCHIP implementation](https://github.com/scipy/scipy/blob/main/scipy/interpolate/_cubic.py),
   and [Apache ECharts LTTB sampling](https://github.com/apache/echarts/blob/master/src/data/DataStore.ts).
   These corroborate local shape constraints and motivate area-preserving
   sampling under a render budget. Tallygent uses actual normalized receipt
   times, not row indices, because its sampling intervals are irregular.

Exact integer-percent plateaus necessarily remain flat. C2 joins and better
tessellation reduce abrupt turns, but do not invent a continuous decline between
equal measurements or smooth away true resets. No new smoothing preference,
runtime dependency, source-data mutation or forecasting behavior is introduced.

The seven-day Token chart has different units and only daily aggregates. Its
Curve mode uses native Charts monotone interpolation and retains the daily
points; it does not send token values through the 0–100% quota fitter and does
not claim to reconstruct intraday consumption.

No third-party runtime, new background task, observation migration or account
permission is needed. Raw exports, depletion estimates, backtests, alerts,
current quota/reset reads, glass rendering, other panel sizes and App appearance
settings keep their existing behavior.

## Mandatory checks

`scripts/check-quota-curve.sh` covers retained-knot fidelity, monotonicity,
0–100% bounds, irregular/extreme times, estimated-gap endpoints, hard boundaries,
invalid/reversed/duplicate timestamps, empty/singleton cases and 20k input rows
under a bounded display budget. Negative controls must fail the same validator.
The smoother also checks matching endpoint velocity/acceleration and a one-second
drop between very long plateaus, which duration-only drawing samples missed.
The time-aware sampling probe includes a sharp-knee fixture missed by uniform
selection, a case distinguishing real time from row index, and a skipped-gap
provenance check. Extreme finite/subnormal intervals must remain bounded.

The existing panel trend, native placed-panel preference/history refresh,
three-language layout, dark/light/opacity render, small/medium isolation,
signature, architectures and exact DMG checks remain mandatory. Curve-specific
images and distinctness checks use non-collinear observations and a known time
gap; two-point or constant interpolation may correctly equal a straight line.
