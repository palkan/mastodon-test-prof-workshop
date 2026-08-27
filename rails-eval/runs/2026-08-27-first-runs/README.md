# Preliminary report (2026-08-27)

See the full (AI-generated) report here: [report.md](./report.md).

## Scoreboard

We tested three models on the test-optimization task: Luna, Kimi, and Grok. (Note: we didn't enforce limits.)

All tests were performed locally (manual `miniswen` usage w/ Docker sandboxes).

| model | reward | speed-up | suite | gates | features (of 9) | steps | cost | tokens in / out | wall time* |
|---|---|---|---|---|---|---|---|---|---|
| grok-4.6 | **0.85** | **3.51x** | green | ✗ ✓ | **5** | 138 | $5.52 | 6.9M / 79k | 32.6m+ |
| kimi-k3 | 0.79 | 3.23x | green | ✓ ✓ | 3.75 | **364** | **$10.76** | **21.7M / 168k** | **2h24m+** |
| gpt-5.6-luna | 0.15 | 1.31x (zeroed) | **6 failures** | ✗ ✗ | 3 | 58 | $0.06 | 1.07M / 19k | 12.8m+ |

## Outcomes

What worked out:

1) Deterministic verification works well (there's a comparison with LLM-as-a-judge in the full report).
2) The task turned out to be tractable, yet nobody managed to solve it 100% (i.e., fix all the problems present in the codebase).
3) We're truly testing long horizon: agents keep notes in docs, save files to tmp/ and reuse them.

Concerns:

1) There's an environment dependency affecting absolute time measurements (see Grok's results). Running on Daytona should solve this.

2) The "memory" problem: good models (Grok, Kimi) remember the original Mastodon codebase. Some of our "tasks" are based on optimizations that had been made in Mastodon and that we reverted; our synthetic regressions were noticed, too ("In upstream, there is no after_create bookmark hook (I believe)"). The question is whether that's good or bad. If a model knows Mastodon, it most likely knows other Ruby code as well — that's rather an advantage ("Ruby ecosystem recall"). But from the task's point of view, it's a cheat sheet. This unfairness is partially addressed by having tasks that were never fixed in the upstream.

Some interesting observations:
- Kimi often generates broken scripts (NoMethodError and the like) — ecosystem-wide recall again
- Kimi reads gem sources like there's no tomorrow
- Nobody ran RuboCop (it wasn't in the instructions, but they could have figured it out, huh?)

## Why yet another benchmark if we have DeepSWEBench, TerminalBench, etc.?

We've also asked Claude to _respond_ to Nate ([how is this different from DeepSWE and the rest](https://x.com/nateberkopec/status/2092359650624888901)): the full answer is in the report. The key points (translating from Claude-speak):

- A composite scoring system (rather than binary pass/fail) surfaces model differences better: Luna flopped on this task while usually being good; Grok turned out great; the gap between them became much more pronounced
- Multi-step / memory: nobody tests this (according to Claude — worth double-checking)
- Ecosystem-wide recall: this benchmark shows not just language knowledge but ecosystem knowledge (e.g., TestProf: Kimi used it at full throttle, Grok recognized it but didn't bother running the profilers, Luna ignored it)
