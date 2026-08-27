# Trajectory sweep: mastodon-test-optimization (clean runs, graded)

Source: `/Users/vladimirdementyev/dev/rails-foundation/tmp/mastodon/rails-eval/runs/2026-08-27-first-runs/{gpt-5.6-luna,grok-4.6,kimi-k3}/mastodon-test-optimization/`
Evidence extracted from `results.{1,2,3}.json` (full transcripts: assistant text/thinking + bash tool calls + observations). `trajectory.*.json` step messages carry only assistant prose, no commands. No `mastodon-test-optimization-maybe-unfair/` directory exists for any model (searched with find; only the clean runs are present).

All tool calls in every run are `bash` (no other tools). Command counts: gpt 24/24/23, grok 40/44/55, kimi 97/121/170 (runs 1/2/3). `mN` = message index in results.N.json; `rN` = run N (r1=spec/models phase, r2=spec/requests phase, r3=factories phase).

---

## Q1. Environment verification before profiling

**gpt-5.6-luna** — no infra checks at all: zero matches for `redis-cli|pg_isready|psql|rails runner` in all three runs. Did do a minimal test run first: r1 m10 timed 3 tiny model specs before the full spec/models baseline (`system("bundle exec rspec spec/models/account_alias_spec.rb spec/models/account_domain_block_spec.rb spec/models/async_refresh_spec.rb --format progress")` wrapped in a `ruby -e` monotonic-clock timer). r2 m8 went straight to the whole spec/requests baseline under `timeout 90s` (only `ruby -v; bundle exec rspec --version` before it). r3 m22 first rspec is a 4-file targeted baseline.

**grok-4.6** — explicit infra checks in r1: m20 `pg_isready; redis-cli ping; ruby -v`, m24 `getent hosts postgres redis` + `(timeout 2 bash -c 'echo > /dev/tcp/postgres/5432' && echo postgres_ok)` (same for redis:6379). Minimal run before baseline: r1 m26/m30 `rspec spec/models/block_spec.rb spec/models/mute_spec.rb --format documentation`, then full models baseline at m34. r2 used `rspec spec/requests --dry-run --seed 1234` (m16) and per-directory `--dry-run` counts (m24) before running anything. r3 m50 ran `rails db:test:prepare` before the baseline, and used `RAILS_ENV=test bundle exec rails runner` micro-benchmarks (m38, m44). 7 infra-check command matches total.

**kimi-k3** — the most thorough env verifier: r1 m10 `pg_isready; redis-cli ping; ps aux | grep postgres|redis`, m15/m17 `which psql redis-cli pg_isready`, m19 `/dev/tcp/postgres/5432` + `/dev/tcp/redis/6379` probes; then a single-file sanity run m21 `rspec spec/models/account_alias_spec.rb` before the suite. r2 repeats the ritual (m14 pg_isready/redis-cli/service status, m20/m22 /dev/tcp) and sanity-runs the tiny `spec/requests/health_spec.rb` twice (m26, m28). r3 sanity-runs `spec/models/async_refresh_spec.rb` (m26). Also frequent `rails runner` sanity/introspection (r2 m24 `SELECT 1`-style AR query, m192/m194 config introspection). 15 infra-check matches total.

## Q2. Background tasks

**gpt** — none. 0 uses of nohup/&/disown/sleep-polling in all 3 runs (the only regex hits are `&& echo` and a `PIPESTATUS` check). Long runs handled with foreground `timeout 90s/100s ...`.

**grok** — none. 0 nohup/background; everything foreground, long commands just piped to `tail`.

**kimi** — heavy user, but only from r2 on: r1 nohup=0, r2 nohup=12, r3 nohup=9; sleep-polling `sleep N; tail/grep <log>` 15x in r2 and 17x in r3. Pattern: `nohup bash -c 'bundle exec rspec ... > tmp/profile/X.log 2>&1' >/dev/null 2>&1 & echo started; sleep 120; grep -E "Finished in|examples," tmp/profile/X.log` (r2 m218), and PID checks `ps aux | grep -c rspec` (r3 m93). Adopted after r1 hit the 300s bash timeout twice (see Q7).

## Q3. Scratch-script language

**gpt** — python3 heredocs to edit Ruby files (8 uses): all `spec/rails_helper.rb` / fabricator edits are `python3 - <<'PY' ... s.replace(old,new) ... open(p,'w').write(s)` string-replace scripts (r1 m24/m26/m30/m38/m42, r2 m19, r3 m28/m38). Ruby (`ruby -e`, 15 uses) reserved for timing wrappers: `ruby -e 't=Process.clock_gettime(Process::CLOCK_MONOTONIC); system(...); puts ...'` and a generic wall-clock runner (r3 m26). Some awk in r2 (3). Never sed -i. Notable: a Python program editing Ruby, with `assert old in s` guards.

**grok** — python3 heredocs for edits too (12 uses; pathlib `read_text/replace/write_text`, with `if old not in text: raise` guards) across all runs incl. docs updates; 2 `sed -i` one-liners in r1 (e.g. m45 `sed -i "s/Sidekiq.testing!(:inli..."` as a temporary experiment). No ruby scratch scripts; ruby only via `rails runner` benchmarks in r3.

**kimi** — polyglot: Ruby scratch files for profiling instrumentation (`cat > tmp/prof_hooks.rb / prof_db.rb / prof_fab.rb / prof_stack.rb` in r1 — 11 heredoc .rb files; r3 — 13, incl. `/tmp/analyze*.rb`, `/tmp/fab_bench.rb`, `/tmp/paperclip_bench.rb` that boot `config/environment`), bash wrapper scripts (`tmp/profile/run_requests.sh`, `/tmp/run_fprof.sh`), python3 heredocs for spec-file edits (12 uses, mostly r2 m100/m156/m160/m216 and r3 m137/m169/m225/m297), plus `sed -i` (9) and awk (9). Same cross-language pattern: python edits Ruby, Ruby measures.

## Q4. Gem introspection

**gpt** — 5 distinct occasions, 14 matches: `bundle show sidekiq` + read `lib/sidekiq/testing.rb` (r1 m34/m36); `bundle show rspec-rails` / `actionpack` and grep for `reload_routes_unless_loaded`, then direct reads under `/usr/local/rvm/gems/default/gems/railties-8.1.3.1/lib/rails/application.rb` (r2 m23–m29); `bundle show fabrication` + grep its lib (r3 m16).

**grok** — 29 matches: `bundle show test-prof` + `ls .../lib/test_prof` (r1 m32), `bundle show actionmailer` + grep `def capture_emails` + read `test_helper.rb` (r1 m59–m61), test-prof recipes dir (r2 m72), and in r3 a deep dive into fabrication-3.0.0 sources (`generator/base.rb`, `schematic/definition.rb`, m80–m84) and test-prof `factory_prof` internals (m28–m30).

**kimi** — heaviest: 100 matches. `gem contents fabrication`, `bundle info <gem> --path` (fabrication, sidekiq, rspec-sidekiq, test-prof), `gem which sidekiq`, and many direct reads under `/usr/local/rvm/gems/default/gems/` — sidekiq-8.1.6 testing internals read exhaustively (r2 m130–m146, ~8 consecutive commands), test-prof event_prof/factory_prof sources (r2 m62–m66, m198–m200; r3 m58–m60), fabrication runner/generator (r3 m185–m187, m279), actionview/activerecord internals (r2 m194–m196).

## Q5. Helper-script reliability (NoMethodError/NameError/wrong-API incidents)

**gpt** — 1 Ruby incident + 2 shell/quoting incidents. Ruby: r1 m29 `/tmp/profile_hooks.rb:7 uninitialized constant ActiveSupport` (profiler required before Rails loaded). Shell: r3 m9 `sh: 1: Syntax error: ")" unexpected` (grep pipeline quoting), r3 m29 `sh: 12: Syntax error: "(" unexpected` (python heredoc mangled by shell).

**grok** — 0. No NoMethodError/NameError/LoadError/SyntaxError from its scripts in any run. Only misstep: r1 m37 "The previous run failed because `time` isn't available" (shell builtin absent), immediately worked around.

**kimi** — 8 distinct incidents:
1. r1 m42 `tmp/prof_db.rb:3 uninitialized constant ActiveSupport` (required via `--require` before rails_helper).
2. r1 m24 `sh: Syntax error: word unexpected` (bash `time (...)` construct under sh).
3. r2 m55 `uninitialized constant TestProf (NameError)` + `cannot load such file -- test_prof/event_prof/rspec/listener (LoadError)` — guessed a formatter/require path that doesn't exist.
4. r2 m181 `/tmp/bench_redis.rb: undefined method 'redis' for module Rails (NoMethodError)` (`Rails.redis` API doesn't exist).
5. r3 m32 `/tmp/fab_bench.rb require_relative 'config/environment'` resolved against /tmp → LoadError.
6. r3 m148 `/tmp/analyze_fab.rb`: `undefined method 'attachment_fixture' for ... Fabrication::Schematic::Runner (NoMethodError)` (fabricators loaded outside spec support context).
7. r3 m208 `/tmp/paperclip_bench.rb`: `uninitialized constant FabricateHelpers (NameError)`; retried with a sed-in require and hit incident 6 again (m210).
8. r3 m214 `sh: Syntax error: redirection unexpected` (nested heredoc).

## Q6. Profiling invocation style

**gpt** — file-edit style: injected an ENV-guarded hook profiler directly into `spec/rails_helper.rb` (`$hook_stats ... if ENV['PROFILE_HOOKS']`, r1 m30, later reverted) plus one `--require /tmp/profile_hooks.rb` attempt (r1 m28, the one that crashed). Used rspec's native `--profile 30`. Never used `-rtest-prof`, RUBYOPT, or test-prof env vars — despite test-prof being in the Gemfile.

**grok** — neither flag style nor env vars at runtime: relied on rspec `--profile 25` + fixed `--seed 1234` A/B wall-clock timing, `rails runner` Benchmark.measure micro-benchmarks (r3 m38/m44), and temporary sed-toggled hook experiments. Its only test-prof touch is editing `spec/requests/cache_spec.rb` to add `require 'test_prof/recipes/rspec/before_all'` (r2 m76) and writing recommended `FPROF=1 ... EVENT_PROF=sql.active_record ...` commands into docs "for later phases" (r1 m71) — commands it never executed itself in r1/r2.

**kimi** — full flag-based repertoire: `--require ./tmp/prof_*.rb` custom instrumentation (15+ times in r1), `EVENT_PROF="sql.active_record" bundle exec rspec --require test_prof ...` (r2 m52/m56/m68), `FPROF=1 bundle exec rspec -r test_prof ...` used systematically as the r3 measurement harness (12+ invocations), plus `FACTORY_PROF=1`, `TEST_PROF_USAGE=factory_prof` experiments (r3 m50–m56) and StackProf boot shims via `--require` (r1 m117, r2 m74). No RUBYOPT.

## Q7. Scope discipline

**gpt** — clean. r1: only spec/models targets. r2: only spec/requests. r3 (factories): mixed models+requests validation runs, appropriate for the phase. Never attempted `rspec spec` whole-suite. Full-suite-per-type runs always wrapped in `timeout 90–100s`; zero observed command timeouts.

**grok** — mostly clean, small excursions: r2 ran `spec/services/webhook_service_spec.rb` (1x), `spec/config/initializers/rack/attack_spec.rb` (1x), and `spec/models/account_spec.rb` (1x) while working the requests phase — all tied to changes it was making (webhook service, rack-attack, httplog) and reflected in its r2 patch. Never ran the whole suite. Zero timeouts.

**kimi** — loosest: r1 (models phase) also ran `spec/mailers spec/requests`, `spec/mailers spec/workers`, `spec/requests` and individual request specs (~5 out-of-scope invocations, mostly checking blast radius of rails_helper changes). r2 re-ran model specs; r3 wandered into `spec/controllers`, `spec/services`, `spec/workers`, `spec/lib`. Timeouts: 2 (both r1, returncode 124 at m118 and m126) — but both were StackProf experiments on a single file (`StackProf ... interval: 1` — 1µs sampling) rather than out-of-scope suite runs; kimi switched to nohup+polling afterwards.

## Q8. "Spoiled intentionally" awareness

**gpt** — essentially none. Closest (weak, and about design intent rather than sabotage): r3 m16 thinking: "I wonder if this is an intentional choice to satisfy callbacks." No "planted"/"injected" language anywhere.

**grok** — zero. No such language in content or thinking across all runs; treated hooks as ordinary inefficiencies to fix.

**kimi** — extensive and explicit, r3 only (~20 statements). Exact quotes:
- r3 m26 thinking: "This seems deliberately wasteful (this is a 'rails-eval' variant — likely the eval authors injected inefficiencies deliberately)."
- r3 m28 thinking: "there is no `after_create` bookmark in upstream. This was likely added deliberately (as a 'planted' inefficiency) for this eval."
- r3 m28 content: "…look at the planted inefficiencies (the two `after_create` hooks in status and user fabricators)."
- r3 m45 thinking: "These two hooks are clearly the planted bottleneck."
- r3 m121 content: "The status→bookmark hook and user→login_activity hooks are clearly planted bottlenecks."
- r3 m137 thinking: "this looks like it was ADDED in a recent commit as part of the eval's injected inefficiency… These are exactly planted issues that we need to fix."
kimi verified against upstream Mastodon from memory ("In upstream Mastodon, the status fabricator does NOT have an after_create bookmark hook", r3 m26/m115).

## Q9. RuboCop

None of the three models ever ran rubocop in any run (0 matches across all 9 transcripts).

## Q10. tmp/ artifacts and reuse

**gpt** — wrote only to system `/tmp` (never workspace `tmp/`): r1 8 files (`/tmp/models-{baseline,profile,flushdb,nocache,noroutes,final}.log`, `/tmp/hooks.log`, `/tmp/profile_hooks.rb` + rails_helper backups `/tmp/rh2`, `/tmp/rails_helper.current`); r2 7 files (`/tmp/requests-*.txt`, `/tmp/subset-*.txt`, `/tmp/rails_helper.before|.flushdb`); r3 none. Reused within-run (m14 writes `/tmp/models-profile.log`, m16 parses it; backups used to A/B-swap rails_helper variants, r2 m23). Cross-run reuse via docs/ only (reads its own `docs/model-spec-performance.md` in r2 m4/m29 and all docs in r3 m4). Patches contain no tmp files.

**grok** — leanest: only r1 wrote `/tmp/models_{baseline,fake,after}.txt`; r2/r3 wrote no tmp files at all (results read directly from foreground output). Notable artifact reuse: r2 m58 parsed rspec's own persistence file with the command comment "# Parse last run's example status file" — `python3 ... Path('tmp/cache/rspec/examples.txt') ... if '|failed|' in line` — to enumerate failures without re-running. Cross-run reuse through docs: r2 m4 content: "Next I'll read the previous performance notes and the RSpec/Rails helpers to see what's already been optimized"; r3 m10 thinking: "The docs already identified the main factory issues". **No verbatim "There's already profiling output in tmp/…" phrase exists in grok's transcripts** — the examples.txt parse and the docs reads are the closest behaviors.

**kimi** — most prolific: r1 14 files (workspace `tmp/prof_{hooks,db,fab,redis,stack}.rb`, `tmp/stackprof.dump`, `/tmp/run*.log`, `/tmp/gc.log`…), r2 15 (a whole `tmp/profile/` dir: run_requests.sh, sql.log, stackprof*.log/dump, groups.log, idea1/idea2_full.log…), r3 34 (`/tmp/fprof_*` series, `/tmp/analyze*.rb`…). Constant within-run reuse via the nohup+`sleep N; grep ... <log>` polling loop (e.g. r3 m141 `grep -A 20 "Factories usage" /tmp/fprof_models_after...`). Cleaned up: r1 m178 `rm ... tmp/logsize_before.txt tmp/stackprof.dump`, r2 m238 `rm tmp/final_requests.log tmp/final_models.log && echo cleaned; ls tmp/`. Cross-run reuse via `docs/rspec_optimization_notes.md` (read at r2 m6, r3 m7). No tmp files leaked into patches.

## Q11. Boot-time awareness

**gpt** — never discussed in prose, but recorded it in docs: r1 m38 wrote to `docs/model-spec-performance.md`: "Baseline wall time: approximately 130.4 seconds (2:08.3 test time; 1.7 seconds load)".

**grok** — yes, early: r1 m32 thinking: "Files took 1.49s to load, 21 examples in 1.06s. That's actually quite slow per example (~50ms)." and m34: "1795 examples … At ~50ms each that's ~90 seconds plus load time."

**kimi** — most explicit, repeatedly: r1 m37 thinking: "note 'files took 2.19 seconds to load'. The per-file load overhead maybe ~2s — small. So the issues must be inside example bodies"; r1 m51: "What about load time? 'files took 2.19 seconds to load' — small."; r2 m172: "examples basically are the whole near-total. Boot time (~2.2s files load) + suite hooks."; r3 m285: "each run took 2.1s just to load files; if wall is ~43s with huge variance, measurements are unreliable."

## Q12. Blast radius (distinct repo files named in read commands before the first edit of each run)

Method: distinct `spec/|app/|config/|docs/|lib/|Gemfile|.rspec|.env.test` paths appearing in commands before the first repo-file mutation. Directory-wide `grep -R`/`find` scans are not counted as file reads, which deflates gpt (it leans on recursive greps) relative to grok/kimi (which `cat` files individually).

| model | run1 | run2 | run3 | first edit |
|---|---|---|---|---|
| gpt-5.6-luna | 8 | 5 | 8 | r1 m24, r2 m19, r3 m28 (all python3 str-replace) |
| grok-4.6 | 31 | 48 | 83 | r1 m45 (sed -i experiment), r2 m54, r3 m62 |
| kimi-k3 | 13 | 29 | 35* | r1 m61 (sed -i + .orig backup), r2 m100, r3 m137 |

*kimi r3: a throwaway probe (`cat > spec/support/zz_fprof_test.rb` marker, immediately rm'd, m83) precedes the first real edit at m137; 35 counts reads up to m137. grok r3's 83 reflects its exhaustive fabricator + gem-source reading spree before touching anything.

---

## Cross-model notes

- No `maybe-unfair` variants exist on disk for any model.
- All three models converged on the same core fixes (rails_helper redis/cache cleanup, Sidekiq fake vs inline, fabricator after_create hooks), but only kimi named them as planted.
- grok and kimi both re-read their own docs/ notes at the start of runs 2 and 3 exactly as the task suggested; gpt did too (r2 m4, r3 m4).
- Patch footprints: gpt smallest (2–4 files/run), grok broadest in r2 (16 files incl. app/ and config/ changes), kimi middle.
