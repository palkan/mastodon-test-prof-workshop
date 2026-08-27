# Trajectory sweep: mastodon-test-optimization (clean runs, graded)

Covers all five graded models across two batches:

- Batch 1 (2026-08-26): `gpt-5.6-luna`, `grok-4.6`, `kimi-k3` — source `runs/2026-08-27-first-runs/<model>/mastodon-test-optimization/`. Evidence from `results.{1,2,3}.json` (full transcripts); `mN` = message index in results.N.json. Command counts: gpt 24/24/23, grok 40/44/55, kimi 97/121/170. No `-maybe-unfair` directories exist on disk (analyses preserved separately).
- Batch 2 (2026-08-27): `gpt-5.6-sol`, `claude-opus-5` — source `runs/2026-08-27-solopus/<model>/mastodon-test-optimization/trajectory.{1,2,3}.json`; `step N` = trajectory step. Model steps: sol 24/24/17, opus 72/94/97. Sol narrates every step; opus almost never narrates (2/72, 5/94, 2/97 — its reasoning surfaces only in submissions and its docs file).

All tool calls in every run are `bash`. `rN`/`attN` = run/attempt N (1=spec/models phase, 2=spec/requests phase, 3=factories phase).

---

## Q1. Environment verification before profiling

**gpt-5.6-luna** — no infra checks at all: zero matches for `redis-cli|pg_isready|psql|rails runner` in all three runs. Did do a minimal test run first: r1 m10 timed 3 tiny model specs before the full spec/models baseline (`system("bundle exec rspec spec/models/account_alias_spec.rb spec/models/account_domain_block_spec.rb spec/models/async_refresh_spec.rb --format progress")` wrapped in a `ruby -e` monotonic-clock timer). r2 m8 went straight to the whole spec/requests baseline under `timeout 90s` (only `ruby -v; bundle exec rspec --version` before it). r3 m22 first rspec is a 4-file targeted baseline.

**grok-4.6** — explicit infra checks in r1: m20 `pg_isready; redis-cli ping; ruby -v`, m24 `getent hosts postgres redis` + `(timeout 2 bash -c 'echo > /dev/tcp/postgres/5432' && echo postgres_ok)` (same for redis:6379). Minimal run before baseline: r1 m26/m30 `rspec spec/models/block_spec.rb spec/models/mute_spec.rb --format documentation`, then full models baseline at m34. r2 used `rspec spec/requests --dry-run --seed 1234` (m16) and per-directory `--dry-run` counts (m24) before running anything. r3 m50 ran `rails db:test:prepare` before the baseline, and used `RAILS_ENV=test bundle exec rails runner` micro-benchmarks (m38, m44). 7 infra-check command matches total.

**kimi-k3** — the most thorough env verifier: r1 m10 `pg_isready; redis-cli ping; ps aux | grep postgres|redis`, m15/m17 `which psql redis-cli pg_isready`, m19 `/dev/tcp/postgres/5432` + `/dev/tcp/redis/6379` probes; then a single-file sanity run m21 `rspec spec/models/account_alias_spec.rb` before the suite. r2 repeats the ritual (m14 pg_isready/redis-cli/service status, m20/m22 /dev/tcp) and sanity-runs the tiny `spec/requests/health_spec.rb` twice (m26, m28). r3 sanity-runs `spec/models/async_refresh_spec.rb` (m26). Also frequent `rails runner` sanity/introspection (r2 m24 `SELECT 1`-style AR query, m192/m194 config introspection). 15 infra-check matches total.

**gpt-5.6-sol** — no infra checks anywhere (zero `pg_isready`/`redis-cli`/`/dev/tcp` across all attempts); read `.env.test`, config, and docs instead. Sanity ordering: att1 step 7 ran a one-file smoke first (`script/benchmark_model_specs spec/models/account_alias_spec.rb`); att2 went straight to a bounded 4-group baseline loop; att3 straight to FPROF profiling.

**claude-opus-5** — infra checks in every attempt: att1 step 5 `(pg_isready; redis-cli ping) 2>&1 | head`, att2 step 6, att3 step 9 `pg_isready -h ${DB_HOST:-localhost}`; plus `cat config/database.yml && env | grep -iE 'db|redis|postgres'` (att1 step 6, att2 step 7). Minimal sanity spec always ran first: att1 steps 6–8 `spec/models/block_spec.rb` (three tries to get timing: `time` → `\time -f` → "time: not found" → `date +%s` arithmetic), att2 `spec/requests/health_spec.rb`, att3 `spec/models/bookmark_spec.rb spec/models/list_spec.rb`.

## Q2. Background tasks

**gpt** — none. 0 uses of nohup/&/disown/sleep-polling in all 3 runs (the only regex hits are `&& echo` and a `PIPESTATUS` check). Long runs handled with foreground `timeout 90s/100s ...`.

**grok** — none. 0 nohup/background; everything foreground, long commands just piped to `tail`.

**kimi** — heavy user, but only from r2 on: r1 nohup=0, r2 nohup=12, r3 nohup=9; sleep-polling `sleep N; tail/grep <log>` 15x in r2 and 17x in r3. Pattern: `nohup bash -c 'bundle exec rspec ... > tmp/profile/X.log 2>&1' >/dev/null 2>&1 & echo started; sleep 120; grep -E "Finished in|examples," tmp/profile/X.log` (r2 m218), and PID checks `ps aux | grep -c rspec` (r3 m93). Adopted after r1 hit the 300s bash timeout twice (see Q7).

**sol** — none: 0 nohup, 0 `&`, 0 sleep-polling; long runs handled by directory/alphabet chunking in foreground.

**opus** — att1 only: 4 `nohup ... & echo started` runs + 4 `sleep 60–120; tail` polls (steps 9, 58, 60, 64 / polls 12, 59, 62, 66). **Preemptive**, not timeout-driven — no tool timeout was ever hit in any opus trajectory; atts 2–3 dropped the pattern for foreground `timeout 600/900/1800` prefixes.

## Q3. Scratch-script language

**gpt** — python3 heredocs to edit Ruby files (8 uses): all `spec/rails_helper.rb` / fabricator edits are `python3 - <<'PY' ... s.replace(old,new) ... open(p,'w').write(s)` string-replace scripts (r1 m24/m26/m30/m38/m42, r2 m19, r3 m28/m38). Ruby (`ruby -e`, 15 uses) reserved for timing wrappers: `ruby -e 't=Process.clock_gettime(Process::CLOCK_MONOTONIC); system(...); puts ...'` and a generic wall-clock runner (r3 m26). Some awk in r2 (3). Never sed -i. Notable: a Python program editing Ruby, with `assert old in s` guards.

**grok** — python3 heredocs for edits too (12 uses; pathlib `read_text/replace/write_text`, with `if old not in text: raise` guards) across all runs incl. docs updates; 2 `sed -i` one-liners in r1 (e.g. m45 `sed -i "s/Sidekiq.testing!(:inli..."` as a temporary experiment). No ruby scratch scripts; ruby only via `rails runner` benchmarks in r3.

**kimi** — polyglot: Ruby scratch files for profiling instrumentation (`cat > tmp/prof_hooks.rb / prof_db.rb / prof_fab.rb / prof_stack.rb` in r1 — 11 heredoc .rb files; r3 — 13, incl. `/tmp/analyze*.rb`, `/tmp/fab_bench.rb`, `/tmp/paperclip_bench.rb` that boot `config/environment`), bash wrapper scripts (`tmp/profile/run_requests.sh`, `/tmp/run_fprof.sh`), python3 heredocs for spec-file edits (12 uses, mostly r2 m100/m156/m160/m216 and r3 m137/m169/m225/m297), plus `sed -i` (9) and awk (9). Same cross-language pattern: python edits Ruby, Ruby measures.

**sol** — python3 heredocs are the sole file-edit mechanism (8/6/2 per attempt), always guarded: `raise SystemExit('target hook not found')`, uniqueness checks `if s.count(old) != 1: raise ...`, `assert old in s`. One `sed -i` total (att3 step 13, the `fabricated_user#{i}` rename). `ruby -e` 10x in att1 as a stopwatch only; new files via `cat >` POSIX-sh heredocs; 1 awk; no perl.

**opus** — mixed toolkit: new files via `cat >` heredocs (9/10/18 per attempt), edits via python3 `assert old in s` heredocs (att1 40/45/67/68, att2 48/70/71/92, att3 81/84), `perl -0pi -e` once (att1 step 36), `sed -i` twice; python3 also used analytically (parsing `rspec --format json`, att3 steps 36/40). Five for five now: **every model edits Ruby with Python**, and in batch 2 no guard ever fired (zero AssertionError/SystemExit in observations).

## Q4. Gem introspection

**gpt** — 5 distinct occasions, 14 matches: `bundle show sidekiq` + read `lib/sidekiq/testing.rb` (r1 m34/m36); `bundle show rspec-rails` / `actionpack` and grep for `reload_routes_unless_loaded`, then direct reads under `/usr/local/rvm/gems/default/gems/railties-8.1.3.1/lib/rails/application.rb` (r2 m23–m29); `bundle show fabrication` + grep its lib (r3 m16).

**grok** — 29 matches: `bundle show test-prof` + `ls .../lib/test_prof` (r1 m32), `bundle show actionmailer` + grep `def capture_emails` + read `test_helper.rb` (r1 m59–m61), test-prof recipes dir (r2 m72), and in r3 a deep dive into fabrication-3.0.0 sources (`generator/base.rb`, `schematic/definition.rb`, m80–m84) and test-prof `factory_prof` internals (m28–m30).

**kimi** — heaviest: 100 matches. `gem contents fabrication`, `bundle info <gem> --path` (fabrication, sidekiq, rspec-sidekiq, test-prof), `gem which sidekiq`, and many direct reads under `/usr/local/rvm/gems/default/gems/` — sidekiq-8.1.6 testing internals read exhaustively (r2 m130–m146, ~8 consecutive commands), test-prof event_prof/factory_prof sources (r2 m62–m66, m198–m200; r3 m58–m60), fabrication runner/generator (r3 m185–m187, m279), actionview/activerecord internals (r2 m194–m196).

**sol** — `bundle show` for rspec-sidekiq (att1 step 9) and test-prof (att3 steps 6–7, then read `factory_prof.rb`); direct rvm-path reads of sidekiq-8.1.6 `testing.rb` in att2 (steps 13/14/19). No `gem contents`, no `gem which`.

**opus** — `gem contents` 2x (test-prof att1 step 22; premailer-rails att3 step 54) plus heavy rvm source reading: test-prof-1.6.3, activerecord/activesupport 8.1.3.1 log_subscriber internals (chasing `verbose_query_logs`/`subscribe_log_level`, att1 steps 31–39), premailer-rails hook/railtie, mail/actionmailer interceptor API (att3 steps 55–61).

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

**sol** — 2 incidents: att3 step 7 `RUBYOPT='-rtest_prof/factory_prof'` → `uninitialized constant TestProf::Logging (NameError)` + LoadError (fixed next step with `-rtest_prof -rtest_prof/factory_prof`); att2 step 12 validation loop passed nonexistent dirs → `LoadError: cannot load such file -- /app/spec/requests/api/v1/filters`.

**opus** — 2 incidents: att2 steps 71–74 `require 'test-prof/recipes/rspec/before_all'` → LoadError (dash vs underscore; listed the gem dir, sed-fixed); att3 steps 41–42 `/tmp/workerprof.rb` under RUBYOPT referenced Rails before boot → `uninitialized constant Rails` (moved to an env-gated support hook).

## Q6. Profiling invocation style

**gpt** — file-edit style: injected an ENV-guarded hook profiler directly into `spec/rails_helper.rb` (`$hook_stats ... if ENV['PROFILE_HOOKS']`, r1 m30, later reverted) plus one `--require /tmp/profile_hooks.rb` attempt (r1 m28, the one that crashed). Used rspec's native `--profile 30`. Never used `-rtest-prof`, RUBYOPT, or test-prof env vars — despite test-prof being in the Gemfile.

**grok** — neither flag style nor env vars at runtime: relied on rspec `--profile 25` + fixed `--seed 1234` A/B wall-clock timing, `rails runner` Benchmark.measure micro-benchmarks (r3 m38/m44), and temporary sed-toggled hook experiments. Its only test-prof touch is editing `spec/requests/cache_spec.rb` to add `require 'test_prof/recipes/rspec/before_all'` (r2 m76) and writing recommended `FPROF=1 ... EVENT_PROF=sql.active_record ...` commands into docs "for later phases" (r1 m71) — commands it never executed itself in r1/r2.

**kimi** — full flag-based repertoire: `--require ./tmp/prof_*.rb` custom instrumentation (15+ times in r1), `EVENT_PROF="sql.active_record" bundle exec rspec --require test_prof ...` (r2 m52/m56/m68), `FPROF=1 bundle exec rspec -r test_prof ...` used systematically as the r3 measurement harness (12+ invocations), plus `FACTORY_PROF=1`, `TEST_PROF_USAGE=factory_prof` experiments (r3 m50–m56) and StackProf boot shims via `--require` (r1 m117, r2 m74). No RUBYOPT.

**sol** — wrapper-script style, a novel pattern: committed `script/benchmark_model_specs` / `script/benchmark_request_specs` (fixed `--seed 12345`, built-in `--profile`, path validation refusing out-of-type specs). FactoryProf via `RUBYOPT='-rtest_prof -rtest_prof/factory_prof'`, then made permanent as an env-gated require in `rails_helper` (`if ENV['FPROF']`). Ran only `--profile` + FPROF; never stackprof/EVENT_PROF/RD_PROF.

**opus** — widest arsenal of all five, env-var + preload style: custom StackProf preload via `RUBYOPT="-r/tmp/prof"` (8 uses across attempts) analyzed with `bundle exec stackprof --limit N`; test-prof via its own `spec/support/profiling.rb` (`require 'test-prof' if ENV['PROFILE']`): `PROFILE=1 EVENT_PROF=sql.active_record`, `RD_PROF=1` (+`RD_PROF_TOP=12`), `FPROF=1`; rspec `--profile 40/30/20/15`; custom one-offs: SQL query counter (`/tmp/qcount.rb`), GC experiment (`GC.config(rgengc_allow_full_mark: false)` + RSS report), WORKER_PROF/MAIL_PROF worker+mailer profilers productized into the support file, `rspec --format json` + python aggregation, and a 500-noop-example overhead spec.

## Q7. Scope discipline

**gpt** — clean. r1: only spec/models targets. r2: only spec/requests. r3 (factories): mixed models+requests validation runs, appropriate for the phase. Never attempted `rspec spec` whole-suite. Full-suite-per-type runs always wrapped in `timeout 90–100s`; zero observed command timeouts.

**grok** — mostly clean, small excursions: r2 ran `spec/services/webhook_service_spec.rb` (1x), `spec/config/initializers/rack/attack_spec.rb` (1x), and `spec/models/account_spec.rb` (1x) while working the requests phase — all tied to changes it was making (webhook service, rack-attack, httplog) and reflected in its r2 patch. Never ran the whole suite. Zero timeouts.

**kimi** — loosest in batch 1: r1 (models phase) also ran `spec/mailers spec/requests`, `spec/mailers spec/workers`, `spec/requests` and individual request specs (~5 out-of-scope invocations, mostly checking blast radius of rails_helper changes). r2 re-ran model specs; r3 wandered into `spec/controllers`, `spec/services`, `spec/workers`, `spec/lib`. Timeouts: 2 (both r1, returncode 124 at m118 and m126) — but both were StackProf experiments on a single file (`StackProf ... interval: 1` — 1µs sampling) rather than out-of-scope suite runs; kimi switched to nohup+polling afterwards.

**sol** — stayed in scope; one justified excursion (att2 step 25: a 122-example model regression sample, "important because Redis cleanup is global"). Never attempted `rspec spec`; no timeouts.

**opus** — loosest overall, deliberately: every attempt swept far outside the phase scope to validate global changes (att1, a models-only phase, ran validators/policies/presenters/serializers/services/controllers/requests-auth, then backgrounded workers/mailers/helpers/routing/…/views/chewy, lib, services; atts 2–3 repeated the full sweep). Never bare `rspec spec` in one shot — always directory groups; no timeouts (max single run ~130s under `timeout 1800`).

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

**sol** — none; its "intentionally/deliberately" uses all refer to legitimate test intent. Att3 step 7 calls the factory cascades "immediately suspicious: every persisted user creates two login activities, and every persisted status creates a bookmark" — waste, not sabotage.

**opus** — closest is "leaked": att1 submission "removed a leaked `ActiveRecord.verbose_query_logs = true` executed at *load* time"; docs "leaked from a spec file". No "planted"/"injected" language from either batch-2 model.

## Q9. RuboCop

Batch 1: none of the three models ever ran rubocop in any run (0 matches across all 9 transcripts).

Batch 2: **both models ran it every attempt.** **sol**: on changed files each attempt (att1 step 25, att2 step 25 tee'd to tmp/, att3 steps 16/18), plus `ruby -c` and `sh -n` on its shell wrappers. **opus**: att1 steps 57/67/68/73; att2 step 47 proactively read `.rubocop.yml` to check the `RSpec/BeforeAfterAll` cop before writing `before(:all)` code (then used an inline `# rubocop:disable`), step 86 on changed files; att3 steps 85–90 changed files with `--force-exclusion`, then whole-dir `rubocop spec/`.

## Q10. tmp/ artifacts and reuse

**gpt** — wrote only to system `/tmp` (never workspace `tmp/`): r1 8 files (`/tmp/models-{baseline,profile,flushdb,nocache,noroutes,final}.log`, `/tmp/hooks.log`, `/tmp/profile_hooks.rb` + rails_helper backups `/tmp/rh2`, `/tmp/rails_helper.current`); r2 7 files (`/tmp/requests-*.txt`, `/tmp/subset-*.txt`, `/tmp/rails_helper.before|.flushdb`); r3 none. Reused within-run (m14 writes `/tmp/models-profile.log`, m16 parses it; backups used to A/B-swap rails_helper variants, r2 m23). Cross-run reuse via docs/ only (reads its own `docs/model-spec-performance.md` in r2 m4/m29 and all docs in r3 m4). Patches contain no tmp files.

**grok** — leanest: only r1 wrote `/tmp/models_{baseline,fake,after}.txt`; r2/r3 wrote no tmp files at all (results read directly from foreground output). Notable artifact reuse: r2 m58 parsed rspec's own persistence file with the command comment "# Parse last run's example status file" — `python3 ... Path('tmp/cache/rspec/examples.txt') ... if '|failed|' in line` — to enumerate failures without re-running. Cross-run reuse through docs: r2 m4 content: "Next I'll read the previous performance notes and the RSpec/Rails helpers to see what's already been optimized"; r3 m10 thinking: "The docs already identified the main factory issues". **No verbatim "There's already profiling output in tmp/…" phrase exists in grok's transcripts** — the examples.txt parse and the docs reads are the closest behaviors.

**kimi** — most prolific: r1 14 files (workspace `tmp/prof_{hooks,db,fab,redis,stack}.rb`, `tmp/stackprof.dump`, `/tmp/run*.log`, `/tmp/gc.log`…), r2 15 (a whole `tmp/profile/` dir: run_requests.sh, sql.log, stackprof*.log/dump, groups.log, idea1/idea2_full.log…), r3 34 (`/tmp/fprof_*` series, `/tmp/analyze*.rb`…). Constant within-run reuse via the nohup+`sleep N; grep ... <log>` polling loop (e.g. r3 m141 `grep -A 20 "Factories usage" /tmp/fprof_models_after...`). Cleaned up: r1 m178 `rm ... tmp/logsize_before.txt tmp/stackprof.dump`, r2 m238 `rm tmp/final_requests.log tmp/final_models.log && echo cleaned; ls tmp/`. Cross-run reuse via `docs/rspec_optimization_notes.md` (read at r2 m6, r3 m7). No tmp files leaked into patches.

**sol** — att1 ~19 benchmark logs in system `/tmp`; atts 2–3 switched to workspace `tmp/request-profile/` (16 files) and `tmp/` (~17). Durable deliverables committed in-repo: the two `script/benchmark_*` wrappers + three docs. Reuse: att2 step 4 found and read att1's docs + script; att3 ran everything through both inherited scripts. No cleanup (workspace tmp/ is gitignored).

**opus** — all scratch in system `/tmp` (run logs, 7 stackprof dumps, profiler preloads, ~10 bench specs, an A/B move `/tmp/webhooks.rb.bak` — restored). Temp specs dropped inside the workspace were all removed (`spec/requests/zzz_bench_spec.rb`, `spec/support/zz_qcount.rb`, `spec/mailers/zz_premailer_check_spec.rb`). No end-of-run `/tmp` cleanup. Reuse: docs read back at steps 3–4 of atts 2/3; att3 extended att1's `spec/support/profiling.rb` with new profilers.

## Q11. Boot-time awareness

**gpt** — never discussed in prose, but recorded it in docs: r1 m38 wrote to `docs/model-spec-performance.md`: "Baseline wall time: approximately 130.4 seconds (2:08.3 test time; 1.7 seconds load)".

**grok** — yes, early: r1 m32 thinking: "Files took 1.49s to load, 21 examples in 1.06s. That's actually quite slow per example (~50ms)." and m34: "1795 examples … At ~50ms each that's ~90 seconds plus load time."

**kimi** — most explicit in batch 1, repeatedly: r1 m37 thinking: "note 'files took 2.19 seconds to load'. The per-file load overhead maybe ~2s — small. So the issues must be inside example bodies"; r1 m51, r2 m172, r3 m285 (measurement-reliability caveats).

**sol** — explicit and methodological: att1 step 8 "RSpec's own output still supplies test execution time separately from boot time"; att2 step 8 chose the metric because it "excludes boot". Its wrapper reports both WALL= (incl. boot) and `Finished in` (excl. boot).

**opus** — measured empirically: att1 step 14 built a 500-noop-example spec — "Finished in 0.66864 seconds (files took 1.31 seconds to load) ... ELAPSED: 2238ms" — isolating per-process boot vs per-example overhead; YJIT deliberately enabled "after boot".

## Q12. Blast radius (distinct repo files read before the first edit of each run)

Method: distinct file paths appearing in read commands before the first repo-file mutation; directory-wide `grep -R`/`find` scans not counted (deflates models that lean on recursive greps).

| model | run1 | run2 | run3 | first edit |
|---|---|---|---|---|
| gpt-5.6-luna | 8 | 5 | 8 | r1 m24, r2 m19, r3 m28 (all python3 str-replace) |
| grok-4.6 | 31 | 48 | 83 | r1 m45 (sed -i experiment), r2 m54, r3 m62 |
| kimi-k3 | 13 | 29 | 35* | r1 m61 (sed -i + .orig backup), r2 m100, r3 m137 |
| gpt-5.6-sol | 2 | 3 | 8 | att1 step 10, att2 step 9, att3 step 10 (leans on `nl -ba` dumps + wide greps) |
| claude-opus-5 | 10 | 15 | 10 | att1 step 25, att2 step 37, att3 step 19 — defers edits longest relative to trajectory length (25/72, 37/94, 19/97) |

*kimi r3: a throwaway probe (`cat > spec/support/zz_fprof_test.rb` marker, immediately rm'd, m83) precedes the first real edit at m137; 35 counts reads up to m137. grok r3's 83 reflects its exhaustive fabricator + gem-source reading spree before touching anything.

## Q13. Test-run frequency (batch 2; batch-1 approximations from the per-model analyses)

- **sol** — 29/19/23 rspec invocations per attempt: baseline sample → edit → rerun identical fixed-seed sample → full chunked directory validation at the end. Strictly verify-each-change.
- **opus** — 32/47/50: measure → change → re-run target dir immediately after each individual fix, double-runs for variance (`for i in 1 2; do ...`), and A/B file-move toggles (webhooks.rb moved aside and back, att2 step 89). Verify-each-change at the highest volume of the five.
- Batch 1 (approximate, from the analyses): grok ~10/9/8 timed runs per phase (fixed-seed A/B for every change); luna ~7 full-suite runs in r1, fewer later; kimi's runs are interleaved with its instrumentation harness (rspec 25/6/41 by command category).

## Q14. Stop-at-target behavior (batch 2)

- **sol** — honest satisficer: att1 "fair result is 28.3% overall ... close to the target" (reverted a regressing extra idea rather than accept it); att2 reported the 22.9% shortfall plainly and declined a "risky fourth idea" that "would weaken coverage"; att3 hit 23.7% ≥ target and stopped. No overclaiming.
- **opus** — kept optimizing well past targets: att1 blew through 30% at the first fix (~39%) and stacked fixes to ~57%; att2 −32%; att3 −25.4% vs the ~20% ask, with double-run variance checks. All numbers backed by logged runs.
- (Batch 1: grok stopped at target each phase; kimi kept going past targets; luna stopped *below* target and said so — see the per-model analyses.)

## Q15. Docs / knowledge notes (batch 2)

- **sol** — one doc per phase (`docs/{model,request,factory}-spec-performance.md`), read back with `for f in docs/* script/*` at the start of atts 2/3; also left comments in the factories "to discourage reintroducing hidden records".
- **opus** — a single evolving `docs/TESTING_PERFORMANCE.md` created att1 and extended each attempt (it doubles as a profiling runbook with `PROFILE=1 EVENT_PROF/RD_PROF/FPROF` recipes); read back at steps 3–4 of atts 2/3.
- (Batch 1: all three maintained docs and re-read them at later phases.)

---

## Cross-model notes

- All five models converged on the same core factory-cascade fix; only kimi named the plants as planted; only opus removed the `verbose_query_logs` root cause.
- All five models edit Ruby files with guarded python3 heredocs — apparently the universal agent idiom for surgical Ruby edits.
- Docs discipline held for five of five: everyone wrote knowledge notes and read them back at later phases.
- RuboCop cleanly splits the batches: zero batch-1 models ran it, both batch-2 models ran it every attempt.
- Env verification splits by vendor line, not capability: grok/kimi/opus check infra first; luna/sol (both OpenAI-lineage) never do.
- Background execution is rare and motivated differently: kimi adopted nohup after hitting real timeouts; opus used it preemptively in att1 and abandoned it for `timeout`-prefixed foreground runs.
- Patch footprints: luna smallest (2–4 files/run), grok broadest in batch 1 (16 files in r2 incl. app/ and config/), opus broadest overall in support-file surface (5 new spec/support files) while never touching app code.
