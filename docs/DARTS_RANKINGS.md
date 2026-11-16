# Darts records and leaderboards

The runtime owns record collection through the existing analytics extension,
durable queue and managed upload job. Both initial service creation and existing
callbacks use `analytics_enabled?`; developer mode neither collects nor uploads
records. `GameRoomAnalyticsStorage` permits the separate
`darts-rankings-pending.json` file. No ranking storage work runs in an aiming frame.

The result projection uses accepted completed-game throws, excludes training,
bots and tie-break darts, and verifies score/time bounds against the number of
throws. A returning human must not publish an inherited bot's throws. Private
records retain the best three per difficulty and metric. Public publication is
opt-in; withdrawal removes public snapshots without changing private records.

## Storage and concurrent clients

The host's AppTable API does not offer conditional row updates. Both declared
tables therefore use immutable snapshot rows, without `unique_per_user` or
update permission. A write reads that account's snapshots, unions their top-three
records with the incoming result, inserts a confirmed merged snapshot, then
deletes only the exact old row IDs included in that snapshot. Deletion is batched
and restricted to authenticated account-owned rows.

A stale concurrent writer cannot overwrite or delete a newer snapshot it never
read. Concurrent documents are merged by account and result key when displayed;
the next write compacts them. Sequential writes retain one document per account.
The top three for each metric remain bounded inside every document. Duplicate
result keys must have identical payloads, and lost insert acknowledgements are
reconciled by reading the retained snapshots before retrying. Withdrawal can
remove multiple snapshots; later opt-in publications can appear again.

Reads use ascending native row IDs, not offsets that can shift during compaction.
Short pages do not end acquisition. Public acquisition is capped at 4096 snapshot
rows; account acquisition at 128. Exceeding a cap or a malformed page fails closed,
not as a partial leaderboard. Public cache: 15 seconds, invalidated by local writes.

## Presentation and deployment

The leaderboard is an application module; its navigation is described in every
README. The Darts rulebooks explain scoring and personal publication settings.
Public placement notices use the existing ordered realtime event channel,
not the replaceable cursor lane. Personal-record notices are private and wait
until the throw presentation completes.

Declaring the two tables does not deploy them. An authorized owner must merge
their declaration into the complete live schema, preserving all other tables,
protection, quotas and data. Do not replace an existing unique-row deployment
without an explicit migration decision. No client-side bounds check makes a
public convenience leaderboard cheat-proof.

Targeted regressions: `test/games/darts/ranking_{result,store,concurrency,runtime}_test.rb`,
`network_cursor_test.rb`, `observer_bots_test.rb` and `departure_test.rb`.
