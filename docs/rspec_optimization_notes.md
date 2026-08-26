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
