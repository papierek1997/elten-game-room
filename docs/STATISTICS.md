# Statistics and current room activity

## User interface

Statistics is directly below Leaderboards in the main menu. It offers today, the last 7/30/365 days (including today), calendar years, and all collected time. Dates use Europe/Warsaw. Game rows are ordered by completed matches, then started matches, then name; games without activity are last. Enter on a game opens the humans/bots/solo breakdown.

The main options context menu also offers Current room activity, available through native Ctrl+W. It shows public rooms, private rooms, and the sum of human room memberships. Observers count; virtual bot seats do not. A person participating in multiple rooms can contribute to several room membership totals. This is not a census of everyone signed into Elten, and it does not list names.

Both screens use native read-only controls and deliberate Refresh. Failed reads display unavailable, not invented zero counts. The historical screen distinguishes dates before collection and partial coverage.

## Historical metrics

- Visitors are distinct authenticated accounts that deliberately entered Game Room through its main entry, active widget, widget action, or a relevant notification. Background loading and list refresh do not record visits.
- Players are distinct human participant accounts observed in active play or on the completion day. Viewing an older finished game or an aborted session does not create a new player-day.
- Starts and completions are separate events. A completion requires a finished accepted replay, not a closed room or a local realtime prediction. Technical aborts do not count as completions.
- A match gets a random statistical identity independent of native identifiers. Rematches get new identities. Save/restore preserves match identity, original start date and initial humans/bots/solo mode. Legacy saves remain playable but do not acquire fabricated historical match records.
- Client retries and multiple participants can create raw duplicate rows because the server index is not unique. The lowest server row ID is canonical for a match report. Date-only reports of another restored ending are acknowledged as already recorded. The reader resolves canonical rows before applying the requested date interval.
- Querying a period never sums daily unique-account counts. Starts minus completions is not an abandonment count, and completed/started within one period is not a completion rate.

The event outbox is persisted per account through the host's atomic JSON API. Uploads use a managed extension schedule and native cancellation. Errors retain pending history and must not interrupt gameplay or poison the lobby table provider.

## Current room presence

An unrelated random room identity is attached at creation. It survives rematches and owner handovers, but a new room, including one created to resume a save, gets a new identity. It is separate from match identity. Updated clients omit it from discovery; it is available to authorized room participants. Older clients may retain their previous discovery-copy behavior, so the token must not be treated as an authorization credential.

Each active program instance registers a managed snapshot source with the account's collector. The collector uses the existing transport and fresh authorized snapshots. It counts connected native human members, including observers, instead of counting player seats or discovery estimates. Only rooms containing the reporting account are eligible.

Presence is refreshed by a native managed schedule every 30 seconds. Reports use minute-sized freshness slots; only the current and previous slot are included. Their lifetime is approximately one to two minutes. Leaving a room or disposing a source clears its known report on a subsequent successful update. A crash or network failure relies on expiry. Failed reads must not be converted into an empty membership list.

Public presence records must be scoped independently to each room. A private random per-installation/account token derives unrelated room-scoped reporter keys; the installation token itself, a cross-room reporter identity, and a reporter's room bundle must not be published. Reports for the same room are combined, not added as separate rooms. Membership totals are approximate snapshots: coarse freshness and asynchronous participant updates prevent an exact simultaneous global census.

## Server tables and privacy

The declarations add only:

- `statistics_accounts`: shared, unique per account, with sharing disabled. It supplies a stable account identity without publishing an account-to-identity directory.
- `statistics_events`: public append-only minimal activity reports.
- `room_presence`: public, independently scoped room reports which are updated rather than reinserted at every heartbeat.

The two public tables require `filter_for: everyone` and all of `__insertion_user`, `__last_update_user`, `__insertion_time`, and `__last_update_time` in `filtered_columns`. The real server rejects column filters on shared tables; private identities rely on account isolation instead. Ownership read-back requires an exact-ID query with `include_access: true` and no explicit projection, because a projection omits the access information.

Payloads do not include nicknames, private room names, participant lists, chat, native session IDs, native table IDs, or native event IDs. Public data is pseudonymous and client-reported, not an anti-cheat system or an information-theoretic anonymity guarantee. Participants can know their own room token; small groups and external knowledge can permit inference. Server/app administrators remain trusted infrastructure.

## Development mode

Game Room disables its new analytics when the host's actual `$developer_mode` flag is true. This is an intentional local opt-out, even if the application author could access a particular table. Do not create telemetry queues or reporter identities, collect developer-mode activity for later upload, read analytics tables, or attempt background uploads. Do not display or log sending failures for this expected disabled state. Existing pending normal-mode events are retained without being sent or deleted.

Native gameplay communication is unaffected. A normal-mode participant can still report a shared room and its member count, including people playing in development mode; a room with no eligible reporter is missing from these counts. Explicitly opening an analytics screen can show unavailable without querying tables. Existing unrelated lobby/invitation table-access behavior is not changed by this analytics opt-out.

The unsigned test package runs in development mode, so automatic telemetry is deliberately inactive there. Do not toggle the live host flag or weaken production stamp checks to bypass this restriction. Authorized synthetic component tests use a separate diagnostic application, not automatic Game Room collection or real player activity.

## Deployment by the application owner

Editing the Ruby declarations does not deploy server tables. Do not update the production application while signed into another developer account.

[STATISTICS_TABLES.json](STATISTICS_TABLES.json) contains the three-table declaration fragment. It is generated from `GameRoomStatistics::Schema::TABLES` in [game_statistics_store.rb](../lib/game_statistics_store.rb) and `GameRoomPresence::Schema::TABLES` in [game_room_presence_store.rb](../lib/game_room_presence_store.rb). The application's `SERVER_TABLES` declaration already merges these with the existing tables. **The JSON file is not a complete application schema: merge its entries into the existing tables; do not replace the application declaration with this fragment.** `test/statistics_schema_documentation_test.rb` checks that it matches the runtime source.

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
