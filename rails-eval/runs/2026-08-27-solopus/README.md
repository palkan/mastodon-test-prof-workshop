# Preliminary report, actualized (2026-08-28)

See the full (AI-generated) report here: [report.md](./report.md). Batch 1 (Grok, Kimi, Luna) details: [../2026-08-27-first-runs/](../2026-08-27-first-runs/).

## Scoreboard

Five models on the test-optimization task, two batches. (Note: we didn't enforce limits.)

All tests were performed locally (manual `miniswen` usage w/ Docker sandboxes). Each batch graded against its own same-session baseline.

| model | reward | speed-up | suite | gates | features (of 9) | steps | cost | tokens in / out | wall time* |
|---|---|---|---|---|---|---|---|---|---|
| grok-4.6 | **0.85** | 3.51x | green | ✗ ✓ | **5** | 138 | $5.52 | 6.9M / 79k | 32.6m+ |
| claude-opus-5 | 0.8375 | **4.45x** | green | **✓ ✓** | 4.75 | 263 | **$17.65** | **21.9M / 173k** | 1h48m+ |
| kimi-k3 | 0.7875 | 3.23x | green | ✓ ✓ | 3.75 | **364** | $10.76 | 21.7M / 168k | **2h24m+** |
| gpt-5.6-sol | 0.65 | 1.78x | green | ✗ ✗ | 4 | 65 | $1.17 | 2.2M / 34k | 19.0m+ |
| gpt-5.6-luna | 0.15 | 1.31x (zeroed) | **6 failures** | ✗ ✗ | 3 | 58 | $0.06 | 1.07M / 19k | 12.8m+ |

\* From step commit timestamps: each phase's commit marks its end, so phase 1's duration is not included and the totals are lower bounds.

### Edit metrics

TtFE=time-to-first-edit (step/%), FtFE (files-to-first-edit, aka discoverability), blast radius (No. of files modified during the session, committed).

| model | step | model steps | TtFE | FtFE | blast radius |
|---|---|---|---|---|---|
| gpt-5.6-luna | 1 | 24 | 12 (50%) | 4 | 2 (2) |
| gpt-5.6-luna | 2 | 15 | 5 (33%) | 6 | 2 (2) |
| gpt-5.6-luna | 3 | 19 | 12 (63%) | 3 | 4 (4) |
| grok-4.6 | 1 | 39 | 22 (56%) | 28 | 5 (5) |
| grok-4.6 | 2 | 44 | 27 (61%) | **39** | **16** (16) |
| grok-4.6 | 3 | 55 | 31 (56%) | **64** | 6 (6) |
| kimi-k3 | 1 | 88 | 15 (17%)† | 12 | 7 (6) |
| kimi-k3 | 2 | 121 | 16 (13%)† | 8 | 10 (10) |
| kimi-k3 | 3 | 155 | 34 (22%)† | 22 | 6 (5) |
| gpt-5.6-sol | 1 | 24 | **4 (17%)** | 3 | 6 (6) |
| gpt-5.6-sol | 2 | 24 | 4 (17%)† | 3 | 11 (11) |
| gpt-5.6-sol | 3 | 17 | 5 (29%)† | 7 | 5 (5) |
| claude-opus-5 | 1 | 72 | 23 (32%) | 15 | 8 (6) |
| claude-opus-5 | 2 | 94 | **35 (37%)** | 17 | 8 (6) |
| claude-opus-5 | 3 | 97 | 17 (18%) | 33 | 8 (6) |

What's there (and not):
- Grok spends ~56–61% of every phase reading and produces what it commits right away
- Opus has longest trajectories and keeps the blas radius small ("intentionally"?)
- Sol edits almost immediately
- Kimi starts writing quickly but its own profilers, not actual code

## Outcome

What worked:

1) Deterministic verification (there's a comparison with LLM-as-a-judge in the first report).
2) The task turned out to be tractable, yet nobody managed to solve it 100% (i.e., fix all the problems present in the codebase).
3) We're truly testing long horizon: agents keep notes in docs, save files to tmp/ and reuse them.
4) Feature-based (golden solution) grading turned out well: even though Opus got the best speed-up, it over-engineered the Sidekiq inline mode challenge (didn't turn fake on by default, used unconventional monkey-patches instead).

Concerns:

1) There's an environment dependency affecting absolute time measurements (see Grok's results). Running on Daytona should solve this.

2) The "memory" problem: good models (Grok, Kimi) remember the original Mastodon codebase. Some of our "tasks" are based on optimizations that had been made in Mastodon and that we reverted; our synthetic regressions were noticed, too ("In upstream, there is no after_create bookmark hook (I believe)"). The question is whether that's good or bad. If a model knows Mastodon, it most likely knows other Ruby code as well — that's rather an advantage ("Ruby ecosystem recall"). But from the task's point of view, it's a cheat sheet. This unfairness is partially addressed by having tasks that were never fixed in the upstream.

Some interesting observations:
- Kimi often generates broken scripts (NoMethodError and the like) — ecosystem-wide recall again
- Kimi reads gem sources like there's no tomorrow
- Only Sol ran RuboCop after edits (it wasn't in the instructions, but others could have figured it out, huh?)
- Only Opus applied the reused encrypted password fix (reduced BCrypt usage)
- Opus and Kimi found the bug with leaking `verbose_query_logs = true`

## Why yet another benchmark if we have DeepSWEBench, TerminalBench, etc.?

We've also asked Claude to _respond_ to Nate ([how is this different from DeepSWE and the rest](https://x.com/nateberkopec/status/2092359650624888901)): the full answer is in the report. The key points (translating from Claude-speak):

- A composite scoring system (rather than binary pass/fail) surfaces model differences better:
  - Luna flopped on this task while usually being good; Grok turned out great; the gap between them became much more pronounced
  - Opus and Grok scored same-ish but the solutions (well, and the costs) highlight the difference: Opus tends to reinvent/patch, Grok follows the best practices
- Multi-step / memory: nobody tests this (according to Claude — worth double-checking)
- Ecosystem-wide recall: this benchmark shows not just language knowledge but ecosystem knowledge (e.g., TestProf: Kimi used it at full throttle, Grok recognized it but didn't bother running the profilers, Luna ignored it)
