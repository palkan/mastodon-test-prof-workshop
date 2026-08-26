# Model spec performance baseline

Measured locally with the default RSpec filters (JS, search, and streaming are excluded):

- 1,795 examples
- Baseline wall time: approximately 130.4 seconds (2:08.3 test time; 1.7 seconds load)
- Slowest 30 examples: approximately 28.9 seconds / 21.9% of test time
- Slowest recurring groups included `AccountStatusesCleanupPolicy`, `TagFeed`, `Status`, `Notification`, and trend queries.

The model suite is database-heavy. The shared RSpec teardown previously cleared Redis with
`redis.del(redis.keys)` for every example. Model specs now use `redis.flushdb`, which avoids
fetching the complete key list before deletion; non-model specs retain the previous cleanup.
Sidekiq inline mode is also only re-selected when a preceding example changed the mode.

A complete post-change run should be repeated in CI or on a less variable machine before
using this as the final 30% benchmark; individual local runs varied by several seconds.
