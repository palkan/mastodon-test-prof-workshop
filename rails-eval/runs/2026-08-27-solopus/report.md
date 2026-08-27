# mastodon-test-optimization — run analysis, actualized (2026-08-28)

Five models across two batches: `grok-4.6`, `kimi-k3`, `gpt-5.6-luna` (batch 1, 2026-08-26, see `../2026-08-27-first-runs/`) and `gpt-5.6-sol`, `claude-opus-5` (batch 2, 2026-08-27), each a 3-step run (`run/<model>` branch, three commits on top of `rails-ai-evals`) via miniswen in Docker sandboxes without step/cost limits.

**Verification protocol**: `dip runner rspec --seed 1234`, RSpec example time ("Finished in"), baseline and candidates measured back-to-back in a single sequential session; features verified with runtime probes, never from agent self-reports. Each batch was graded in its own session against its own baseline (batch 1: models 131.6s / requests 168.0s / combined 415.0s; batch 2: 128.5s / 159.9s / 405.0s — ~2.5% between-session drift, the same phenomenon that cost Grok its step-1 gate). Speed-up ratios are same-session and comparable.

**Artifacts**: per-run `agent.{1,2,3}.patch` + cumulative `agent.patch`, `checks.json`, `checks.judge.json`, merged `result.json` (readable by `lemans report`) in `<batch>/<model>/mastodon-test-optimization/`; trajectory analyses for all five models in `analysis/`. Note: `claude-opus-5`'s raw patches exclude `rails-eval/` — the harness accidentally committed the runs folder into its branch (broken `./runs/` gitignore pattern on the host; the in-container mount stub was empty, so the agent never saw it).

## Scoreboard

| model | reward | speed-up | suite | gates | features (of 9) | steps | cost | tokens in / out | wall time* |
|---|---|---|---|---|---|---|---|---|---|
| grok-4.6 | **0.85** | 3.51x | green | ✗ ✓ | **5** | 138 | $5.52 | 6.9M / 79k | 32.6m+ |
| claude-opus-5 | 0.8375 | **4.45x** | green | **✓ ✓** | 4.75 | 263 | **$17.65** | **21.9M / 173k** | 1h48m+ |
| kimi-k3 | 0.7875 | 3.23x | green | ✓ ✓ | 3.75 | **364** | $10.76 | 21.7M / 168k | **2h24m+** |
| gpt-5.6-sol | 0.65 | 1.78x | green | ✗ ✗ | 4 | 65 | $1.17 | 2.2M / 34k | 19.0m+ |
| gpt-5.6-luna | 0.15 | 1.31x (zeroed) | **6 failures** | ✗ ✗ | 3 | 58 | $0.06 | 1.07M / 19k | 12.8m+ |

\* From step-commit timestamps: each commit marks a step's end, so step 1's working time is unknown and totals are lower bounds.

Per-step detail (improvement vs the batch's own baseline):

| model | s1 models | s2 requests | final combined | per-step usage |
|---|---|---|---|---|
| grok-4.6 | 95.5s (27.4%, missed 30% by 2.6pp) | 89.8s (46.6%) | 118.2s | 39/44/55 steps, $0.97/1.50/3.05 |
| claude-opus-5 | **51.5s (59.9%)** | **71.7s (55.2%)** | **91.1s** | 72/94/97 steps, $3.38/**7.01**/**7.26** |
| kimi-k3 | 48.8s (62.9%) | 106.7s (36.5%) | 128.6s | 88/**121**/**155** steps, $1.93/2.59/**6.24** |
| gpt-5.6-sol | 94.4s (26.5%, missed) | 123.7s (22.6%, missed) | 227.0s | 24/24/17 steps, $0.40/0.44/0.32 |
| gpt-5.6-luna | 132.2s (−0.5%, missed) | 163.1s (2.9%, missed) | 318.0s, 6 failures | 24/15/19 steps, ~$0.02 each |

Default limits (100 steps, $5/trial) not enforced. **Claude Opus 5 exceeds the cost limit in two phases** ($7.01, $7.26; $17.65 total — the most expensive run of the five, tagged `over-cost-limit`); Kimi exceeds the step limit in two phases and cost in one. Cost spread across the field: **294x** (Luna $0.06 → Opus $17.65).

## Feature matrix (runtime probes; see `checks.json`)

| Feature | grok | opus | kimi | sol | luna |
|---|---|---|---|---|---|
| Sidekiq inline → fake | ✓ (`:inline_jobs` tags) | ✗ (**deliberately kept inline**, made it cheap instead: webhook guard + premailer scoping) | ✓ | ✓ (`:inline_jobs`, same file set as grok) | ✗ |
| Log level `:fatal` | ✓ (`ENV.fetch(…, 'fatal')`) | ◐ 0.75 (`:warn` via ENV.fetch) | ◐ 0.75 (`:warn`) | ✗ (untouched) | ✗ |
| Paperclip stub | ✗ | ✗ (measured, rejected: processors mutate the record) | ✗ | ✗ | ✗ |
| Redis `flushdb` | ✓ | ✗ (kept `del(keys)`) | ✗ | ✓ | ✓ (scoped) |
| `cache_spec` `before_all` (FPROF factories, base 4139) | ✓ (19) | ✓ (**19**) | ✗ (2075) | ✗ (2075, deferred with rationale) | ✗ (2075) |
| Factory cascades | ✓ | ✓ | ✓ | ✓ | ✓ — the one universal fix |
| `Fabricate.build` restored | ✗ | ✗ | ✗ | ✗ | ✗ — untouched by all five |
| Password/BCrypt | ✗ | ✓ (**Devise::Encryptor digest memoization** — first and only model to score it; probe: 0 BCrypt calls/user) | ✗ | ✗ | ✗ |
| Faker in factories (base 4 calls/user+account) | ✗ (saw it, deferred) | ✓ (0) | ✓ (0) | ✓ (0) | ✓ (0) |
| **Total** | **5** | **4.75** | 3.75 | 4 | 3 |

Sanity: `spec/fabrication` green (115 examples) and spec-diff budget (<5%) passed for all five (sol +36/−25, opus +172/−15).

Beyond the checklist, Opus applied four unscored levers nobody else found: the **`verbose_query_logs` plant itself** (removed the leaked line from `fetch_replies_concern_spec.rb` — the root cause everyone else masked via log level), **YJIT enablement** (runtime `RubyVM::YJIT.enable` after boot), a **premailer interceptor scoped to mailer specs** (~5s of CSS inlining nobody asserts on), and **route-set draw once per group** in `signature_verification_spec`. That's how it posts 4.45x with a "wrong" Sidekiq answer: the checklist measures conformance to our reference solution, and Opus beat the field's speed with different levers — it loses reward points precisely where it solved the same problem another way.

## Fairness

All five graded runs are **fair**. Batch-2 specifics (full analyses in `analysis/{sol,opus}-analysis.md`):

- **claude-opus-5: clean.** The critical question — its branch contains `rails-eval/runs/` with sol's full trajectories — resolves harness-side: inside the container `rails-eval` was an empty mount stub (0 bytes, verified in `ls` output), the agent never ran a single command against it, and the run files were swept in by the host-side commit through a broken `./runs/` gitignore pattern. `.git` unusable (empty), docs/ clean at start, own `/tmp` only. Every touched spec was verified correctness-preserving in-run (it even **ablated its own webhook guard** to prove the effect, and route-drawing changes were tested order-forward and order-reversed). One benign grader-awareness remark: *"extra margin in case grading differs"* — answered with more optimization, not gaming.
- **gpt-5.6-sol: clean.** `rails-eval/` visible but never touched; git probed 4x, blocked, gave up gracefully; no tampering; twice *narrowed* over-broad `:inline_jobs` tags; every reported number matches raw RSpec output. Left its own logs uncleaned in `/tmp` and workspace `tmp/` (feed for the next contamination, if not reset).
- Batch-1 verdicts unchanged (grok/kimi/luna clean; luna's `-maybe-unfair` run contaminated via harness prompt bug — see `../2026-08-27-first-runs/report.md`).
- **Harness regression to fix**: the host-side `rails-eval/.gitignore` pattern `./runs/` does not match (gitignore semantics) — that's how run data landed in `run/claude-opus-5`. Correct it to `runs/`; and note the in-container gitstub mounts (`.git`, `rails-eval`) are doing their isolation job perfectly.

## Insights (batch-2 additions)

- **Opus is the first model to out-diagnose the checklist.** It found the actual `verbose_query_logs` plant (previously found only by Kimi's discarded maybe-unfair run via stackprof) and removed the cause rather than masking it; its 347-line `docs/TESTING_PERFORMANCE.md` reads like a senior engineer's performance handbook — per-change attribution (130→79→71→64→59s), rejected ideas with measurements (GC tuning: "no gain, +300 MB RSS"; paperclip caching: "processors have side effects"; httplog: "does not show up in the profile"), and a productized profiler (`WORKER_PROF`) shipped as a support file.
- **A distinct optimization philosophy split**: Grok/Sol/Kimi switch Sidekiq to fake mode (suppress the work); Opus keeps inline semantics and makes the work cheap (webhook early-exit guard via spec-support prepend, premailer scoping). Both reach large wins; the feature checklist only rewards the first.
- **Sol is Luna's architecture with Grok's playbook — and the same ceiling.** Same lab, same step counts (~24/24/17 vs 24/15/19), but Sol executed the sidekiq-fake + flushdb + cascades + Faker set competently, validated all 3,672 examples directory-by-directory, ran RuboCop on its changed files every attempt (as did Opus — the batch-2 pair splits cleanly from batch 1, where nobody ran it), and honestly reported "28.3% vs 30% target". Without the log-level lever its gates fail exactly like Grok's step 1 did (26.5% / 22.6%) — in this environment, miss the log I/O and the 30% gate is out of reach on config-only changes.
- **Sol built guard-railed benchmark scripts** (`script/benchmark_model_specs` with pinned seed, `--profile`, and path validation that *refuses non-model paths*, negatively tested) — a novel reproducibility artifact no other model produced; it also wired FPROF as an opt-in `rails_helper` hook after reading the test-prof gem source.
- **Cost-performance is now a four-way frontier**: Grok 0.85/$5.52, Opus 0.8375/$17.65, Kimi 0.7875/$10.76, Sol 0.65/$1.17. Opus pays 3.2x Grok's price for a marginally lower reward (but the fastest suite); Sol delivers 76% of Grok's reward for 21% of the price. Luna remains the floor at any price.
- **Opus's steps went where Kimi's did** (263 vs 364: instrumentation, ablation, full blast-radius validation — 6,300+ examples green each phase) but with a far higher hit rate and no broken helper scripts beyond two recovered incidents; Kimi had 8.
- Verification-plan features confirmed portable across sessions: probes and FPROF discriminators produced unambiguous verdicts for both new models with zero probe changes (the 9-feature harness is stable).

## Edit metrics (TtFE / discoverability / blast radius)

Computed uniformly from the trajectories (definitions: TtFE = model-step index of the first workspace-file modification, no wall-clock exists per step; FtFE/discoverability = distinct files individually read before that edit, directory-wide greps excluded; blast radius = distinct workspace files modified during the session — source files incl. later-reverted/deleted ones, with the committed patch's file count in parentheses). Full data: `analysis/edit-metrics.{md,json}`.

| model | step | model steps | TtFE (step, %) | FtFE | blast radius (committed) |
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

† TtFE reached via scratch writes into the *workspace* `tmp/` (profiling scripts, benchmark logs) rather than a source edit — kimi's first durable source edit in step 3 is model step 61, sol's is step 8. Opus routes all scratch to system `/tmp`, so its TtFE reflects genuine source edits. Blast radius here excludes workspace-`tmp/` scratch (kimi wrote up to 24 files incl. scratch, sol up to 27 — see `analysis/edit-metrics.md`).

Readings: **grok is the archetypal read-first editor** — it spends ~56–61% of every phase reading (64 files before its first phase-3 edit) and then lands exactly what it commits (blast = committed everywhere). **Opus deliberates longest in absolute steps** (first edit at step 23/35/17) yet keeps the tightest, constant footprint (8 modified / 6 committed each phase — the deltas are temp probe specs it always deleted). **Sol edits almost immediately** (steps 4–5) off 3–7 file reads. **Luna reads little and edits little** — mid-trajectory single-purpose edits. **Kimi's early TtFE is instrumentation, not impatience**: its first writes are its own profilers; actual source edits come much later.

## Judge vs runtime verification (batch 2)

An independent LLM judge scored all 9 features from `agent.patch` only (no execution; `checks.judge.json` per run):

| model | features judge / runtime | reward judge / runtime | deltas |
|---|---|---|---|
| gpt-5.6-sol | 4.0 / 4.0 | 0.65 / 0.65 | none — exact agreement |
| claude-opus-5 | **5.1 / 4.75** | **0.855 / 0.8375** | sidekiq_fake **+0.35** (judge granted alternative-mechanism credit for the webhook guard + premailer scoping; runtime probe checks the mechanism, `inline? == false`, and scores 0) |

Two findings:

1. **The judge over-credited for the first time.** Batch 1's judge only under-credited (unverifiable semantics → discounts); this one granted partial credit for a legitimate alternative mechanism the probe can't see. Both directions stem from the same root: partial-credit policy where the plan is silent. And it matters — under the judge's policy **Opus (0.855) overtakes Grok (0.85)**; under the runtime policy Grok stays first. The grok/opus ranking is decided by the equivalent-solution grading question, not by measurement.
2. The judge independently flagged what the runtime pass also concluded: Opus fixed an off-checklist planted issue (the `verbose_query_logs` leak) with no credit available — "worth knowing the checklist may be incomplete."

## Suggested improvements (delta over batch 1)

1. **Fix the host-side gitignore** (`./runs/` → `runs/`) so run data never lands in work branches; keep the in-container gitstub mounts as-is (they held).
2. **The checklist under-rewards equivalent solutions.** Opus achieved the best measured speed while scoring 0 on two features it solved differently (inline-but-cheap Sidekiq; kept `del(keys)` it measured as negligible). Consider grading paired features on *outcome probes* (e.g. "fabricating a status runs no wasteful webhook serialization" — true for both fake mode and the guard) instead of mechanism probes, or granting alternative-mechanism credit explicitly.
3. **The 30% step-1 gate remains the sharpest edge**: four of five runs' step-1 outcomes hinge on whether the model found log I/O (find it → 60%+; miss it → ~27%). If the gate's purpose is "made real progress", 25% with margin — or a fractional gate — still looks right.
4. All batch-1 recommendations stand (same-session baselines, sandbox resets, runtime probes, instruction-voice fixes — the updated instructions were **not** used for batch 2, which ran on the same task text as batch 1).
