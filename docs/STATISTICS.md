# Statistics and current room activity

## User interface

Statistics is directly below Leaderboards in the main menu. Its General entry
opens application activity; games with personal statistics have separate entries
through the shared capability. The General screen offers today, the last
7/30/365 days (including today), calendar years, and all collected time. Dates
use Europe/Warsaw. Game rows are ordered by completed matches, then started
matches, then name; games without activity are last. Enter on a game opens the
humans/bots/solo breakdown. See [sports player statistics](SPORTS_LEADERBOARDS.md)
for the game-specific counters, not a leaderboard.

The main options context menu also offers Current room activity, available through native Ctrl+W. It shows public rooms, private rooms, and the sum of human room memberships. Observers count; virtual bot seats do not. A person participating in multiple rooms can contribute to several room membership totals. This is not a census of everyone signed into Elten, and it does not list names.

Both screens use native read-only controls and deliberate Refresh. Failed reads display unavailable, not invented zero counts. The historical screen distinguishes dates before collection and partial coverage.

## Historical metrics

- Visitors are distinct authenticated accounts that deliberately entered Game Room through its main entry, active widget, widget action, or a relevant notification. Background loading and list refresh do not record visits.
- Players are distinct human participant accounts observed in active play or on the completion day. Viewing an older finished game or an aborted session does not create a new player-day.
- Starts and completions are separate events. A completion requires a finished accepted replay, not a closed room or a local realtime prediction. Technical aborts do not count as completions.
- A match gets a random statistical identity independent of native identifiers. Rematches get new identities. Save/restore preserves match identity, original start date and initial humans/bots/solo mode. Legacy saves remain playable but do not acquire fabricated historical match records.
- Client retries and multiple participants can create raw duplicate rows because the server index is not unique. The lowest server row ID is canonical for a match report. Date-only reports of another restored ending are acknowledged as already recorded. The reader resolves canonical rows before applying the requested date interval.
- Querying a period never sums daily unique-account counts. Starts minus completions is not an abandonment count, and completed/started within one period is not a completion rate.

UI and replay callbacks put small copied records into a bounded in-memory queue, then wake a managed worker. That worker persists the per-account outbox before uploading. An analytics-only storage adapter resolves the host's legitimate `data_path` once per runtime, in the worker, and retains the existing filenames and JSON formats. Subsequent reads do not reparse the installed package to find its directory. Updates use a shared lock file and a flushed temporary file replaced atomically; corrupt JSON fails closed, never as an empty queue. Disk and server I/O never run under the replay callback's lock. Uploads use native cancellation. Persisted history survives reloads and network errors; as with other asynchronous telemetry, a process stopped before the first background write can lose the newly staged record. Errors must not interrupt gameplay or poison the lobby table provider.

There is no periodic historical-statistics upload. A startup check discovers durable pending records once; new semantic events wake the worker. Each pass handles at most 50 records, with bulk lookups/inserts in chunks of at most 25 (also respecting the table's select limit). It yields between confirmed chunks once its one-second soft budget is exhausted and schedules another pass only while work remains. This is not a one-second HTTP timeout: an in-flight chunk must finish or fail, and every request retains its five-second timeout. The store returns the confirmed prefix length. Only this prefix is acknowledged, with the remaining count obtained from that same atomic queue update, not another full JSON read. Partial commits or lost replies are retried by stable event keys, with conflicts and malformed bulk acknowledgements rejected.

Retryable failures use 30, 60, 120, then 300 seconds between attempts, or longer when the server's `retry_after` requires it. New records are still persisted during backoff, without bypassing the network retry deadline. Unconfirmed writes stay pending; acknowledgements require the same account/runtime and a confirmed server response. Corrupt local data or unsafe server schemas stop that job rather than retrying indefinitely. The native extension tick checks only in-memory deadlines, never files or tables.

Before the clock's first synchronization, a visit records only its monotonic instant in bounded memory. The worker synchronizes the server clock and derives the Warsaw date of entry, including when the response arrives after midnight. A clock failure retains the intent for retry; it does not freeze an untrusted OS date into the outbox. No clock HTTP runs in the UI callback or during network backoff.

While navigating periods, a statistics dialog may reuse its read boundary, collection start and canonical match records for up to 15 seconds; canonical records are capped at 4096. The schema is still verified on every operation. Explicit Refresh renews the metadata through year discovery, expiry refreshes it automatically on the next read, and any attempted write (including an uncertain one) invalidates it. This is a short consistent snapshot, not automatic background polling or permanent report caching.

Historical and presence readers request at most 1000 rows, or the lower schema limit. The endpoint can return fewer rows than requested even while more data remains (the production schema permits 2000, but replies are capped at 1000). A nonempty short page is never proof of end-of-data. History advances by the actual distinct row count until an empty page; presence advances by the actual last ID until an empty page or its fixed upper ID boundary. Cancellation, account checks, canonical deduplication and snapshot bounds apply on every page. A malformed, repeated or failed later page raises an error instead of returning plausible partial totals. History therefore makes one final empty-page request on a nonempty snapshot; uploads and presence heartbeats are unaffected. No server records need rewriting to correct the formerly truncated reports.

## Current room presence

After an uncertain publication, even a return to the last confirmed contents must be published again: the server may have committed the intervening state. Skip unchanged snapshots only after a fully acknowledged publication. A malformed local reporter identity stops the job without deleting/regenerating it; ordinary disk failures remain retryable.

An unrelated random room identity is attached at creation. It survives rematches and owner handovers, but a new room, including one created to resume a save, gets a new identity. It is separate from match identity. Updated clients omit it from discovery; it is available to authorized room participants. Older clients may retain their previous discovery-copy behavior, so the token must not be treated as an authorization credential.

Each active program instance registers a managed snapshot source with the account's collector. The collector uses the existing transport and fresh authorized snapshots. It counts connected native human members, including observers, instead of counting player seats or discovery estimates. Only rooms containing the reporting account are eligible.

Presence is refreshed on room creation, membership changes (including observers), waiting/playing transitions and departure, coalesced for one second from the first notification. Unchanged room contents do not cause another publication. Chat, moves, ball packets and individual points are not presence triggers. While a report is active, a heartbeat is due 120 seconds after the previous successful publication, including an event-triggered publication. Retryable failures use the same bounded backoff as historical uploads. Leaving the last room clears the known report, retrying if needed, and then the job becomes idle. Reporters remain individual participating clients; there is no new leader election.

Reports use minute-sized freshness slots; the current and previous five slots are included by every reader and canonical-record lookup. Their lifetime is approximately five to six minutes, allowing more than one missed heartbeat. A crash or network failure relies on expiry. Failed reads must not be converted into an empty membership list. This expiry is unrelated to LiveSessions leases or the separate 45-minute discovery filter.

After publishing, at most once per 15 minutes, the worker scans at most 64 expired records and removes only
ones the server identifies as owned by the current account. It rereads each
candidate before deletion and leaves recently renewed reports alone. Cleanup
uses a separate older cutoff of seven minute slots and an advancing cursor;
it never changes historical statistics. This is client-driven retention, not
a server expiration job: an offline account's last rows may remain stored until
it publishes again, although expired rows never contribute to the census.
`room_presence` therefore requires owner-scoped delete permission in addition
to select, insert and update.

Closing or switching runtime/account invalidates its jobs without waiting on the UI thread. Pending durable history remains account-scoped. No additional scheduler thread, server table, quota or protection change is needed. A publication/batch can still perform several native HTTP requests (schema, ownership/idempotency lookup, write and confirmation); one scheduled job must not be described as one request.

Public presence records must be scoped independently to each room. A private random per-installation/account token derives unrelated room-scoped reporter keys; the installation token itself, a cross-room reporter identity, and a reporter's room bundle must not be published. Reports for the same room are combined, not added as separate rooms. Membership totals are approximate snapshots: coarse freshness and asynchronous participant updates prevent an exact simultaneous global census.

## Server tables and privacy

The declarations add only:

- `statistics_accounts`: shared, unique per account, with sharing disabled. It supplies a stable account identity without publishing an account-to-identity directory.
- `statistics_events`: public append-only minimal activity reports.
- `room_presence`: public, independently scoped room reports which are updated rather than reinserted at every heartbeat.

The two public tables require `filter_for: everyone` and all of `__insertion_user`, `__last_update_user`, `__insertion_time`, and `__last_update_time` in `filtered_columns`. The real server rejects column filters on shared tables; private identities rely on account isolation instead. Ownership read-back requires an exact-ID query with `include_access: true` and no explicit projection, because a projection omits the access information.

Payloads do not include nicknames, private room names, participant lists, chat, native session IDs, native table IDs, or native event IDs. Public data is pseudonymous and client-reported, not an anti-cheat system or an information-theoretic anonymity guarantee. Participants can know their own room token; small groups and external knowledge can permit inference. Server/app administrators remain trusted infrastructure.

## Development mode

Game Room disables its analytics, including Axel Pong and Audio Ball player statistics, when the host's actual `$developer_mode` flag is true. Both use `analytics_enabled?`. This is an intentional local opt-out, even if the application author could access a particular table. Do not create telemetry queues or reporter identities, collect developer-mode activity for later upload, read analytics tables, or attempt background uploads. Do not display or log sending failures for this expected disabled state. Existing pending normal-mode events are retained without being sent or deleted.

Native gameplay communication is unaffected. A normal-mode participant can still report a shared room and its member count, including people playing in development mode; a room with no eligible reporter is missing from these counts. Explicitly opening an analytics screen can show unavailable without querying tables. Existing unrelated lobby/invitation table-access behavior is not changed by this analytics opt-out.

The unsigned test package runs in development mode, so automatic telemetry is deliberately inactive there. Do not toggle the live host flag or weaken production stamp checks to bypass this restriction. Authorized synthetic component tests use a separate diagnostic application, not automatic Game Room collection or real player activity.

## Deployment by the application owner

Editing the Ruby declarations does not deploy server tables. Do not update the production application while signed into another developer account.

[STATISTICS_TABLES.json](STATISTICS_TABLES.json) contains the three-table declaration fragment. It is generated from `GameRoomStatistics::Schema::TABLES` in [game_statistics_store.rb](../lib/game_statistics_store.rb) and `GameRoomPresence::Schema::TABLES` in [game_room_presence_store.rb](../lib/game_room_presence_store.rb). The application's `SERVER_TABLES` declaration already merges these with the existing tables. **The JSON file is not a complete application schema: merge its entries into the existing tables; do not replace the application declaration with this fragment.** `test/statistics/statistics_schema_documentation_test.rb` checks that it matches the runtime source.

1. Review the new schemas and existing live schema while authenticated as the actual Game Room owner.
2. Back up/read the complete live declaration. Merge the three analytics tables without removing unrelated tables, resource settings, notifications, or launcher-stamp protection. Do not replace a newer server declaration wholesale with an older checkout.
3. Apply the authorized schema update, then independently read back `data.server.tables` and verify visibility, permissions, uniqueness requirements, metadata masks, field types and limits.
4. Verify authenticated identity ownership, idempotent event writes, canonical cross-date reads, presence updates/expiry, and both owner/non-owner privacy before general rollout.
5. Distribute an appropriately signed updated client. An unsigned development package is not proof that protected production table access will succeed for another account; never bypass launcher-stamp enforcement.

Without a matching safe schema, analytics stays unavailable and collection/upload fails closed. Existing gameplay must remain usable. An unsigned test package does not activate production statistics.

## Coverage and limitations

There is no complete retrospective archive of private room activity to import. Live game stacks are trimmed on rematches. Collection begins with reporting clients; earlier history and older clients can be missing. Presence also requires a room carrying the new anonymous room identity, so an old room may need to be recreated after upgrading its creator.

Rows describe accounts and memberships, not verified unique physical people. Current-room reports are not durable historical occupancy snapshots. Historical game labels come from the installed game registry. Backend retention and long-term table quotas are not established by `max_select_limit`; annual selectors do not guarantee that the host will retain data forever.

Diagnostic API tests use only a separate owner-controlled application and explicitly synthetic fixtures. They are not community usage statistics and must never be imported into the production tables.
