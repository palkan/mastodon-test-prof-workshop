## How to verify? (Draft)

_To be converted to verification_spec.rb, etc_

Non-final steps only use rewards to decide if can proceed to the next step or not: 0 reward — stop here; 1 — continue to the next step.

The final step's reward is fractional based on the optimizations applied and the overall speed improvement.

## Setup

We need to store the baseline information (time and/or tps) before the agent starts working.

IDEA: We can run `rspec spec/models spec/requests` during the setup phase, generate the `rspec-baseline.json` artifact and **encrypt** it via a key not available to the model. Then, decrypt at the verification phase.

### Restore paths

We can't restore `spec/` and `config` — we expect them to be updated by the agent. We should restore `bin/rspec`
and `.rspec`, drop `.rspec-local` (so there is no hidden `--dry-run`).

We should probably check the `spec/` diff size (it must be <5% or so).

## Step 1

Require `rspec spec/models` to be 30% faster than the baseline.

If the improvement is >1000% — marks as fraud and halt.

## Step 2

Require `rspec spec/requests` to be 30% faster than the baseline.

If the improvement is >1000% — marks as fraud and halt.

## Step 3 (final verification)

- Grade `rspec spec/requests spec/models` speed-up: `round((min((old_time / new_time), 2) * 5))` # 10 is max

  - Bonus points: if >150% faster — 2 more points

- Features (each gives 1 point and backed by a single test in the verification_test.rb):
  - sidekiq inline: verifiable by checking `Sidekiq::Testing.inline?` is an empty spec
  - log level changed to `:fatal`: verifiable by checking the `Rails.logger.level`
  - paperclip processing stubbed: verifiable by creating a test with media processing
  - Redis delete keys vs. flushdb: verifable by spying Redis commands?
  - requests/cache_spec reusable setup (before(:all) or before_all): verifable by running `FPROF=1 be rspec -rtest-prof spec/requests/cache_spec.rb`
  - factory cascades: verifiable by running a test with a factory and count the number of records created (1 point if at least one cascade of known cascades is fixed)
  - Encryption in factories (`user.password`): verifiable by a BCrypt spy? (see also [this fix](https://github.com/palkan/mastodon-test-prof-workshop/commit/59472aeaf801507947444d0cf5c9448388dad3d0))
  - Faker in factories: verifiable by a stub_const(:Faker)/spy/trace_location (?) on a :user factory

NOTE: We (should) have ~10 features.

The final reward is calculated as follows: `min(grade + scored_features, 20) / 100)`. Thus, if the model speeds up things much better than we anticipated (>150%) but didn't fixed all the known problem, it still can score 1.0.
