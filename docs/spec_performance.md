# RSpec performance notes

Working notes for suite-level optimizations. Prefer configuration and shared
setup changes over rewriting individual examples. Do not treat this as product
documentation.

## Scope and how to measure

- Ignore system specs and streaming/search/js-tagged specs (excluded by default).
- Do **not** run the whole suite in this environment; it will time out.
- Profile one spec type at a time: `spec/models`, then `spec/requests`, …
- Leave factories alone until that dedicated phase.
- Use a fixed seed for comparable timings:

```sh
RAILS_ENV=test bundle exec rspec spec/models --profile 25 --seed 1234
```

Useful TestProf (already in the Gemfile) commands for later phases:

```sh
FPROF=1 RAILS_ENV=test bundle exec rspec spec/models --seed 1234
EVENT_PROF=sql.active_record RAILS_ENV=test bundle exec rspec spec/models --seed 1234
RD_PROF=1 RAILS_ENV=test bundle exec rspec spec/models --seed 1234
```

## `spec/models` baseline (before this phase)

- Command: `bundle exec rspec spec/models --profile 25 --seed 1234`
- 1795 examples, 0 failures
- **148.9s** example time (files ~2.1s)
- Hottest groups: `Trends::Statuses` (~12s), `AccountStatusesCleanupPolicy` (~14s),
  `TagFeed` (~11s), `Status` (~11s), `PublicFeed` (~8s), `Notification` (~7s),
  `MediaAttachment` (~6s)

Shared cost (not example-specific):

1. **`Sidekiq.testing!(:inline)` on every example** — Account/Status/User
   `after_commit` callbacks enqueue `TriggerWebhookWorker`. Inline mode runs
   `WebhookService`, which **serializes the event even when no webhooks exist**.
   Reblogs/status-heavy examples pay this over and over.
2. **Redis cleanup after every example** used `redis.del(redis.keys)` (`KEYS *`
   + `DEL`). Behavior is needed (`Rails.cache` / `Setting` isolation; e.g.
   `public_feed_spec`), but `FLUSHDB` is equivalent and cheaper.
3. Factories (later phase): `Fabricator(:status)` creates a bookmark;
   `Fabricator(:user)` creates two login activities. Trends/cleanup-policy specs
   fabricate many statuses, so this compounds.

## `spec/models` changes in this phase

- Model examples use Sidekiq **fake** mode unless tagged `:inline_jobs`.
- Other spec types stay on **inline** (do not change their runtime behavior).
- Three model examples deliver mail through Sidekiq and need the tag:
  - `spec/models/admin/account_action_spec.rb` — sends email to target user
  - `spec/models/email_subscription_spec.rb` — confirmation email callback
  - `spec/models/user_spec.rb` — welcome email on first confirmation
- `capture_emails` (ActionMailer) only sees deliveries if the Sidekiq/ActiveJob
  mail worker actually runs.
- After hook: `redis.flushdb` instead of `redis.del(redis.keys)`.

After (same seed, including `:inline_jobs` tags): **97.17s**, 1795 examples, 0 failures (≈35% faster than 148.9s).

## `spec/requests` baseline (before this phase)

- Command: `bundle exec rspec spec/requests --profile 25 --seed 1234`
- 1877 examples (ignore system/streaming/search/js).
- Representative slice `spec/requests/api/v1` (916 examples, same seed): **59.23s**.
- Hottest request-specific costs (not individual example logic):

1. **Debug logging** — `Rails.logger` level 0 (`debug`). One `api/v1` run wrote
   ~9MB / 28k lines of SQL + `Rails.cache` + Rack::Attack traces to
   `log/test.log`. Shared I/O on every request.
2. **Sidekiq inline** — same webhook/AP/distribution tax as models. Most request
   examples only assert HTTP status / JSON / `have_enqueued_sidekiq_job`. A
   minority need workers to actually run:
   - Home feed is Redis-only (`DistributionWorker` / `FanOutOnWriteService`).
   - Notifications / conversations / favourites use `LocalNotificationWorker`.
   - `capture_emails` needs `deliver_later` to run (ActiveJob → Sidekiq).
3. **`WebhookService` serializes even when no webhooks exist** — still paid by
   remaining `:inline_jobs` request examples (and any other inline spec type).
4. **Rack::Attack + HttpLog** — every request hits a dozen throttle cache
   keys; HttpLog wraps Net::HTTP in test because `Rails.env.local?` is true.
5. **`cache_spec.rb`** — 258 examples, each re-fabricating alice/user/statuses/
   poll/invite/token + follow (~19s after the other cuts, ~21s in a mixed run).

## `spec/requests` changes in this phase

- Test log level defaults to `fatal` (`RAILS_LOG_LEVEL` overrides).
- HttpLog is not loaded in test.
- `Rack::Attack.enabled = false` in test; `spec/config/initializers/rack/attack_spec.rb`
  re-enables it around its examples.
- Request examples use Sidekiq **fake** unless tagged `:inline_jobs`.
  Tagged files (worker side-effects or mail):
  - `spec/requests/api/v1/timelines/home_spec.rb`
  - `spec/requests/api/v1/notifications_spec.rb`
  - `spec/requests/api/v2/notifications_spec.rb`
  - `spec/requests/api/v2/notifications/accounts_spec.rb`
  - `spec/requests/api/v1/conversations_spec.rb`
  - `spec/requests/api/v1/statuses/favourites_spec.rb`
  - `spec/requests/api/v1/reports_spec.rb`
  - `spec/requests/api/v1/admin/account_actions_spec.rb`
  - `spec/requests/admin/confirmations_spec.rb`
- `WebhookService` returns before AMS serialization when no webhook matches.
- `cache_spec.rb` builds the shared graph once via test-prof `before_all`
  (examples unchanged). 258 examples: **18.75s → 4.56s**.

After (same seed):

- `spec/requests/api/v1`: **39.06s** / 916 examples / 0 failures (≈34% vs 59.23s).
- `spec/requests`: **83.81s** / 1877 examples / 0 failures.

## Future phases

### Factories

- Status fabricator `after_create` bookmark and user `login_activity` records
  are the next large shared cost. Consider traits / optional associations.
- `let_it_be` / `before_all` (test-prof) would help
  `account_statuses_cleanup_policy_spec` and `trends/statuses_spec` which rebuild
  large graphs per example. Request `cache_spec` already uses `before_all`.
- `include_context 'with API authentication'` fabricates user+token per example;
  many API files override `scopes`/`token`, so do not blindly switch that
  context to `let_it_be`.

### Later spec types (controllers, services, workers)

- Still on Sidekiq inline by default. Same webhook early-return now helps them.
- Devise `reload_routes_unless_loaded` stays per-example (lazy routes + Devise
  https://github.com/heartcombo/devise/issues/5705). Cheap after first load.
- Remaining request hotspots: ActivityPub replies/contexts, signature
  verification (RSA + `reload_routes!` after each example), HTML settings/admin
  pages, Paperclip media endpoints.

### Media / Paperclip

- `MediaAttachment` mp3-with-cover is inherently slow (image processors).
- Do not globally disable Paperclip post-processing; those examples assert on
  metadata. A later pass can tag `:paperclip` and skip styles elsewhere.
