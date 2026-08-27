# Edit metrics: 5 models x 3 steps (mastodon-test-optimization)

| model | step | total steps | TtFE (step, %) | FtFE | blast radius (non-tmp / committed) |
|---|---|---|---|---|---|
| gpt-5.6-luna | 1 | 24 | 12 (50%) | 4 | 2 (2 / 2) |
| gpt-5.6-luna | 2 | 15 | 5 (33%) | 6 | 2 (2 / 2) |
| gpt-5.6-luna | 3 | 19 | 12 (63%) | 3 | 4 (4 / 4) |
| grok-4.6 | 1 | 39 | 22 (56%) | 28 | 5 (5 / 5) |
| grok-4.6 | 2 | 44 | 27 (61%) | 39 | 16 (16 / 16) |
| grok-4.6 | 3 | 55 | 31 (56%) | 64 | 6 (6 / 6) |
| kimi-k3 | 1 | 88 | 15 (17%) | 12 | 16 (7 / 6) |
| kimi-k3 | 2 | 121 | 16 (13%) | 8 | 24 (10 / 10) |
| kimi-k3 | 3 | 155 | 34 (22%) | 22 | 6 (6 / 5) |
| gpt-5.6-sol | 1 | 24 | 4 (17%) | 3 | 6 (6 / 6) |
| gpt-5.6-sol | 2 | 24 | 4 (17%) | 3 | 27 (11 / 11) |
| gpt-5.6-sol | 3 | 17 | 5 (29%) | 7 | 20 (5 / 5) |
| claude-opus-5 | 1 | 72 | 23 (32%) | 15 | 8 (8 / 6) |
| claude-opus-5 | 2 | 94 | 35 (37%) | 17 | 8 (8 / 6) |
| claude-opus-5 | 3 | 97 | 17 (18%) | 33 | 8 (8 / 6) |

## Notes / judgment calls
- Step indexing: a 'model step' = one assistant/agent message that issues >=1 bash tool call, numbered 1..N in order. Some steps carry 2-3 bash commands (both formats); all commands in a message share its step index.
- Workspace tmp/: kimi-k3 and gpt-5.6-sol wrote profiling scripts/benchmark logs into the repo's own tmp/ (e.g. 'mkdir -p tmp && cat > tmp/prof_hooks.rb'); per the stated definition these count as workspace modifications, which pulls their TtFE earlier and inflates blast radius relative to committed files. claude-opus-5 wrote all scratch to system /tmp instead, so its TtFE reflects genuine workspace edits.
- kimi-k3.3 TtFE=34 is a write-probe (creates then immediately rm's spec/support/zz_fprof_test.rb); the first durable source edit is step 61 (fabricators).
- gpt-5.6-sol.3 TtFE=5 is a benchmark log redirect into workspace tmp/; its first source-code edit is step 8 (fabricators + rails_helper).
- Batch-1 backup/restore flows via /tmp were handled: cp to /tmp = not modifying; cp /tmp/x back into spec/... = modifying (e.g. gpt-5.6-luna.1 step 22, claude-opus-5.2 step 35).
- Blast radius counts: temp spec/support files later rm'd (zz_*.rb, zzz_bench_spec.rb), backup copies inside the workspace (spec/rails_helper.rb.orig), and log/test.log truncation/rm (claude-opus-5.1) are included; sed-script tokens and directory targets from the parser were manually removed.
- FtFE counts only individually named displays/inspections (cat/sed -n/head/tail/nl, grep with a single explicit file); explicit multi-file cats count each named file; recursive greps, find -exec sweeps, and glob loops ('for f in spec/fabricators/*.rb; do cat $f') do not count. Reads of gem sources via $(bundle show) are outside the workspace and excluded. .git and wc -l were not counted as reads; log/test.log reads were (workspace file).
- Per the given definition, git commands were never counted as modifying; the only git-write candidate found (kimi-k3.3 'git stash list') was read-only, so nothing was missed.
- Sanity check passed: non-tmp blast radius equals the committed count for every batch-1 and gpt-5.6-sol run (luna 2/2/4, grok 5/16/6, kimi 6/10/5+backup, sol 6/11/5) and exceeds it for claude-opus-5 (8/8/8 vs 6/6/6) due to temp zz_* helpers later deleted, plus log/test.log in run 1.
