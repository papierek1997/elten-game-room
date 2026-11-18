# Darts records and leaderboards

The runtime owns record collection through the existing analytics extension,
durable queue and managed upload job. Both initial service creation and existing
callbacks use `darts_rankings_enabled?`, backed by the application's confirmed
`GameRoomServerTables::Runtime` access decision for the current account and runtime.
Developer mode itself does not disable Darts records: with table access they
can be collected, read and uploaded in either mode. An unchecked, refused or
failed access check suspends those operations, including captured callbacks
and store reads. Already queued records remain intact for later retry. Bind
the provider when checking access on application entry, not when an unchecked
widget instance initializes its unrelated services. General/presence/sports
statistics retain their separate developer-mode policy.
The shared `GameRoomAvailability` messages distinguish missing table access from
disabled statistics: an authorized developer Darts session can still send its
records. Refuse the common Rankings entry before showing game choices when no
table access is available. Captured readers and publication/removal actions use
the same explanation after a later denial, rather than suggesting a useless retry.
`GameRoomAnalyticsStorage` permits the separate
`darts-rankings-pending.json` file. No ranking storage work runs in an aiming frame.

The result projection uses accepted completed-game throws, excludes training,
bots and tie-break darts, and verifies score/time bounds against the number of
throws. A returning human must not publish an inherited bot's throws. Private
records retain the best three per difficulty and metric. Public publication is
opt-in; withdrawal removes public snapshots without changing private records.
The fixed scopes are easy, normal, hard, expert, master and legendary; the
legacy easy-to-normal-to-hard progressive game remains a separate scope.

Expert, master and legendary are account progression rather than replay
authorization. Exactly three rounds and at least 850 points on hard unlock
expert; 800 on expert unlock master; 750 on master unlock legendary. Unlocking
is strictly sequential. A guest may play a host's advanced table and the result
may be retained, but the creation form and leaderboard navigation hide levels
above that guest's entitlement until the normal preceding achievement is met.
Canonical table options still accept every difficulty so joining and replay do
not depend on one device's private state.

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

Personal version-two documents also carry their highest unlocked level in the
same `records_json` field. Version-one snapshots grant the default through hard.
Version-two readers take
the highest level from all concurrent snapshots, so a stale client cannot lower
an unlock, and every subsequent personal write compacts that value with the
records. The client also mirrors a newly earned level into local preferences for
immediate use, tagged with its canonical ELTEN account. An account switch
invalidates the in-memory preference view; a different or unowned cache grants
only the default levels. Late feedback cannot update a different signed-in
account. The private server snapshot provides cross-device recovery.

Reads use ascending native row IDs, not offsets that can shift during compaction.
Short pages do not end acquisition. Public acquisition is capped at 4096 snapshot
rows; account acquisition at 128. Exceeding a cap or a malformed page fails closed,
not as a partial leaderboard. Public cache: 15 seconds, invalidated by local writes.
Both `records_json` columns retain the supported `string:4096` type. The server
rejects `string:8192`, including in schema preview. Version-two documents use
fixed tuples and canonical base64url representations of the same 32-byte result
keys; decoding restores the complete validated record objects. Even all seven
scopes with three maximum-length records in both categories fit the original
column. No record, timestamp, precision or scope is dropped. Version-one rows
remain readable and are not rewritten by deployment. The version-two envelope
has `r` for compact records and private-only `u` for the level index. Strict
decoding validates tuple widths, keys and progression before ordinary record
validation. All parsed documents remain bounded by the original column limit.

## Presentation and deployment

The leaderboard is an application module; its navigation is described in every
README. The Darts rulebooks explain scoring and personal publication settings.
Public placement notices use the existing ordered realtime event channel,
not the replaceable cursor lane. Personal-record notices are private and wait
until the throw presentation completes. Opted-in private record history remains
local. The client increments `local_history_revision` after new feedback or a
history-visibility change; the owning GameScreen form consumes it and updates
only the native history control. Background frames do not touch controls, and
unchanged revisions do not refresh, move focus or repeat announcements.

No server migration is required: both table declarations remain unchanged.
Live schema preview showed that adding a column would recreate the personal
table, reset its rows and clear shares; the client must not perform that update.
The earlier proposed 8192-byte/extra-column migration was removed. Future schema
work still requires the owner's explicit authorization, a complete current
declaration and `Apps.preview_update` with inspection of destructive effects,
not assumptions that adding a column preserves rows. No client-side bounds
check makes a public convenience leaderboard cheat-proof.

Targeted regressions: `test/games/darts/ranking_{result,store,concurrency,runtime}_test.rb`,
`record_codec_test.rb`, `account_progression_test.rb`, `local_history_native_test.rb`,
`network_cursor_test.rb`, `observer_bots_test.rb` and `departure_test.rb`.
