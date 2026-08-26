# Factory performance notes

The focused model and request suites use `Fabricate(:status)` and
`Fabricate(:user)` extensively. Their factories previously had broad `after_create`
side effects: every status created a bookmark and every user created two login
activities. These records were not part of the normal fixture contract; specs that
exercise bookmarks or login activities create the records explicitly. Removing the
callbacks avoids hundreds of extra inserts and nested fabrications per run while
leaving the examples unchanged.

If a future spec needs a status's bookmark or a user's login history, it should
create that relationship explicitly rather than making it an implicit property of
the base fabricator.
