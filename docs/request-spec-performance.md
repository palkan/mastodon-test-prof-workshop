# Request spec performance

The enabled request suite (with the default `js`, `search`, and `streaming` exclusions)
contains roughly 1,000 examples and is dominated by shared per-example setup/teardown rather
than one endpoint. Request specs use the same dedicated test Redis database as the other
non-parallel test processes. Their teardown previously ran `redis.keys` followed by `DEL` for
every example. That requires a key-list response and an extra command each time; `FLUSHDB`
provides the same isolation without enumerating keys. The request branch now uses `flushdb`,
matching the existing model-suite optimization.

The test cache is an in-memory store and remains cleared per example because request examples
explicitly exercise cache behavior. Search and streaming specs remain excluded by default and
were not changed.
