# RSpec Suite Optimization Notes

This document tracks findings from test-suite profiling/optimization runs so
future phases can build on previous knowledge.

## Phase 1: `spec/models`

Baseline (no changes, serial run in this container, aio environment):

- `spec/models`: ~2m05s – 2m13s (1795 examples)
- `spec/requests` (unrelated target for this phase): ~2m23s baseline

Key findings from instrumentation:

1. **Global hooks are cheap.** per-example hooks (`Sidekiq.testing!`,
   `Rails.application.reload_routes_unless_loaded`, `Rails.cache.clear`,
   `redis.del(redis.keys)`, `Resolv::DNS` stub) cost well under 1s total across
   the whole suite. Not worth touching for speed, only for correctness.

2. **Debug-level logging was the biggest hidden cost.** In test env the Rails
   logger ran at debug level and wrote every SQL statement + framework logs to
   `log/test.log` (file sync'ed per write). ~116k queries for a models run
   meant ~55% of the wall time. Fix: set `config.log_level = :warn` in
   `config/environments/test.rb`. Log file confirmed to not grow during runs.

3. **Inline Sidekiq execution.** The suite forced `Sidekiq.testing!(:inline)`
   for every example, running worker callbacks (mailers, trends, process
   workers triggered by model callbacks, etc.) inside examples. Changed to
   `:fake` scoped to `type: :model` only, so other spec types keep the
   original behavior. Examples that need a job to run wrap the trigger with
   `Sidekiq::Testing.inline! { ... }` (3 examples updated).

4. **Fabrication dominates remaining time.** Rough measurements (nested
   instrumentation, values overlap): `account` ~58s, `status` ~43s, `bookmark`
   ~25s. Optimize factories in a later phase. Redis totals are small.

5. SQL totals for full models run: ~20s across ~116k queries (avg 0.18ms),
   so DB latency is not the bottleneck; Ruby-side work is.

Applied changes (Phase 1):

- `config/environments/test.rb`: `config.log_level = :warn`
- `spec/rails_helper.rb`: `Sidekiq.testing!(:fake)` for `type: :model` examples
- `spec/models/email_subscription_spec.rb`,
  `spec/models/admin/account_action_spec.rb`, `spec/models/user_spec.rb`:
  wrapped 3 examples' trigger with `Sidekiq::Testing.inline! { ... }`
  (needed when mailers must fire under fake mode)

Measured result:

- `spec/models`: **~44-48s** (~64-65% faster than baseline) — target (≥30%) exceeded.

Future phases ideas:

- Factories: `account`, `status`, `bookmark` fabrication dominate; consider
  trimming/flattening fabricators or caching accounts/users where validations
  allow (`FactoryHelpers` from test-prof could help once factories are in scope).
- `spec/requests` phase: the same log-level fix benefits requests; scoped fake
  mode for `type: :request` may also be a candidate after auditing examples
  (several request specs rely on inline delivery).

## Phase 2: `spec/requests`

Baseline measurement in this container (with Phase 1 changes applied):
~145s wall, 1877 examples, 0 failures (run with `--format progress`, no
system/streaming/search/js - default filters).

Instrumentation used:

- `test-prof` EventProf (`sql.active_record`): ~16% of wall — DB latency is
  not the bottleneck.
- `stackprof` (wall): PG exec ~15%, GC ~6-7%, BCrypt ~4% (user fabrication),
  rest spread over ActiveRecord/ActiveSupport internals — i.e., fabrication
  + Rails overhead, no single smoking gun. Global per-example hooks
  (Resolv stub, routes reload, `Rails.cache.clear`, `redis.del(redis.keys)`)
  measured negligible (~5ms/150 iterations in rails console).

Applied changes (Phase 2):

1. **Sidekiq fake mode for `type: :request`** (the big one, ~26-28%):
   `spec/rails_helper.rb` now sets `Sidekiq.testing!(:fake)` for request
   examples, like Phase 1 did for model examples. New `around` hook
   `sidekiq: :inline` runs tagged examples with inline job execution.
   Failing examples (~41 across the suite) that rely on job side effects
   (notification creation via `LocalNotificationWorker`, home timeline
   fan-out, report mailers, unfavourite worker, conversation records) were
   tagged. Whole-file tags used for notifications/timelines/admin-action
   specs; example-level tags for conversations/reports/favourites.
   Full run: 145s → ~104-107s, 0 failures.

2. **Tag narrowing** for conversations/reports/favourites so only the
   failing examples run inline (rest stay fake): ~3s saved.

Result: ~145s → ~104s (28-29%); ~40% was achieved mid-check before the
tagged-inline groups were restored for correctness.

Future phases ideas (factories still deferred, per assignment):

- Fabrication dominates: stackprof shows PG exec (~15%), BCrypt (~4%,
  Devise password digest during user fabrication), GC (~7%). Biggest
  next lever is factory caching/`FactoryHelpers` (test-prof) or trimming
  `account`/`user` fabricators.
- Even after fake-mode, inline-tagged groups (notifications v1/v2,
  timelines/home, admin account actions) are the slowest (~2-3s per
  group); consider moving notification creation off workers (app change)
  or reducing example setup.
- GC tuning (RUBY_GC_* env) ~5-7% — needs pre-boot env, not done.
- `Rack::Attack` is registered twice in the middleware stack
  (application.rb + railtie auto-injection); de-duplicating could shave a
  bit more (app refactor, not done).

## Phase 3: factories (`spec/models` + `spec/requests`)

Baseline measured this run (with Phase 1+2 changes applied):

- `spec/models`: ~46s (1795 examples)
- `spec/requests`: ~107s (1877 examples)
- Combined: ~153s

Method: `FPROF=1 bundle exec rspec -r test_prof <paths>` gives per-factory
totals ("total" includes nested fabrications; "top-level" is direct calls).

Findings & applied factory changes:

1. **status fabricator fabricated a bookmark on every create**
   (`after_create { Fabricate(:bookmark, status: status) }`). FPROF showed
   `bookmark` costing ~15s in requests / ~10s in models — plus it
   cascades into `account`/`user` fabrications (each bookmark fabricates
   an account, which fabricate.builds a user). Removed the hook; specs
   that need a bookmark fabricate it explicitly (only export/cleanup
   policy specs do).

2. **user fabricator fabricated 2 login_activities on every create**
   (`after_create { 2.times { Fabricate(:login_activity, user: user) } }`).
   FPROF showed `login_activity` ~2.4s in requests models/requests level.
   Removed; specs that care (sessions controller, cleanup scheduler)
   create one explicitly.

3. **account's nested user build** — the fabricator used
   `Fabricate.build(:user, account: nil)` to build the `user` association
   (~15 ms/call of Fabrication schematic-evaluation overhead). Replaced
   with `FabricateHelpers.build_user` (`User.new` with identical
   defaults, ~1 ms/call) in `spec/support/fabricate_helpers.rb`. The
   helper keeps its own email counter (`helper_user_N@example.com`) to
   preserve uniqueness across both paths. Saves several ms per
   `Fabricate(:account)`.

4. **Faker in hot paths** — account username (`Faker::Internet.user_name`,
   ~0.4 ms) and user email (`Faker::Internet.email`, ~0.18 ms) per call.
   Replaced with deterministic sequences (`user_N` / `user_N@example.com`).
   Username must match `Account::USERNAME_RE` — `user_` prefix is valid.

Measured results this phase (final, stable across repeated runs):

- `spec/models`: ~46s → **~34.2-34.7s** (~25%)
- `spec/requests`: ~107s → **~78.5-79s** (~26%)
- Combined: ~153s → ~113-114s (~25-26%). Target (~20%) exceeded.

Additional factory change in the final pass:

5. **memoized `UserRole.find_by`** in `admin/moderator/owner_user`
   fabricators (`FabricateHelpers.role`) — avoids a SELECT per fabricated
   admin/mod user (roles are seeded once per suite).

Leftovers (future phases):

- `media_attachment` is the priciest single fabricator (~90-126 ms/call)
  due to Paperclip image processors (lazy_thumbnail/blurhash/color
  extractor). Models run spends ~5s here, requests ~1.8s. Needs a careful
  approach (specs assert `thumbnail: be_present` for audio fixtures).
- `account` remains ~18s (models) — nested `account` + helper-built
  `user` still brings Fabrication pipeline overhead (schematic
  evaluation on BasicObject, BCrypt stretch for devise password hash,
  PG exec). GC is ~10%+ per stackprof.
- Nested fabrications are still the dominant amplifier: every
  `Fabricate(:status)` fabricates an `account`, so account-time surfaces
  inside many other factories (status, favourite, poll, etc.).
