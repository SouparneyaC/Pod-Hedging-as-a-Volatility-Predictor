# Pod Hedging as a Volatility Predictor

Multi-strategy hedge funds file 13F institutional holdings at the firm level, but
internally trade through semi-autonomous "pods" with independent P&L. Treating the
firm as one monolithic voice discards that internal structure — two pods inside the
same fund can be on opposite sides of the same position in the same quarter, with the
firm-level 13F showing only the net.

This project (case study: D.E. Shaw) builds a scanner that finds those positions —
stocks where the fund's pods are effectively hedging against each other — from
submanager-level 13F detail, and tests whether the resulting internal hedging predicts
elevated volatility once the position becomes public.

## The Friction Index

For a security held by submanagers $i = 1, \dots, n$, each with a quarter-over-quarter
share change $\%\Delta_i$:

$$\text{FrictionIndex}(s) = \max_i(\%\Delta_i) - \min_i(\%\Delta_i)$$

A position only counts as internally hedged when it's genuinely two-sided — at least
one pod buying **and** at least one selling in the same quarter. Pure dispersion among
same-direction pods (everyone buying, just by different amounts) doesn't count. The
hedging score is a step function of the friction magnitude: 100 (≥100% spread), 75
(≥50%), 50 (≥20%, configurable), 25 otherwise.

Three named signal types, on aggregate vs. individual pod change:
- 🔥 **Internal Disagreement** — aggregate change under 10% but hedging spread over
  50%: market indecision hidden behind a stable net position.
- 📈 **Hidden Accumulation** — net buying at the fund level, but one pod aggressively
  exiting (min pod change below -15%).
- 📉 **Contrarian Opportunity** — net selling at the fund level, but one pod
  aggressively buying (max pod change above +15%).

## Validation

For a high-hedging signal, realized volatility 30 days pre- vs. post-disclosure
(annualized, $\sqrt{252}$ scaling) is compared. A genuine pod conflict should show
elevated post-disclosure volatility; a muted response is read as evidence the position
change was orderly (e.g. coordinated profit-taking) rather than a real thesis split
between pods.

## Results

Run against D.E. Shaw's Q1 2024 13F (6,482 positions): 2,847 stocks were held by 2+
submanagers, of which 47 scored as high-hedging and 128 as medium-hedging.

Three named case studies, with real per-ticker figures:

| Ticker | Hedging spread | Net change | Pods (buy/sell) | Total value |
|---|---|---|---|---|
| CELH | 20,674.8% | +1,363.3% | 1 / 1 | $132.1M |
| MCHP | 2,168.3% | +283.9% | 1 / 1 | $79.9M |
| NVDA | 56.7% | -37.9% | 1 / 2 | $2,110.1M |

The CELH finding drew a direct reaction from QuantKiosk's co-founders when shared
in January 2026 — "holy cow incredible" (Jeffrey Ryan), "Wow cool... Super interesting"
(Frederic Boyer) — the platform this project's 13F data comes from.

Full writeup: `Intra-Firm Divergence as a Volatility Predictor.pdf` (original title
kept as published).

## Files

| File | What it does |
|---|---|
| `ingestion.R` | Pulls submanager-level 13F holdings from the QUANTkiosk API |
| `hedging_scanner.R` | Computes the Friction Index and hedging score across all positions; `scan_hedging_opportunities()` is the entry point |
| `hedging_visualizer.R` | Generates the butterfly charts (`create_butterfly_chart()`) showing each pod's position change for one ticker |
| `hedging_comparison_summary.csv`, `hedging_comparison_detailed.csv`, `hedging_presentation_table.csv` | Output data for the three named case-study tickers |
| `butterfly_CELH.png`, `butterfly_MCHP.png`, `butterfly_NVDA.png` | The generated charts |

## Guardrail

The volatility validation here is directional (elevated post-disclosure volatility as
a proxy for "real conflict between pods"), not a backtested P&L series — this is a
research signal, not a live trading strategy.
