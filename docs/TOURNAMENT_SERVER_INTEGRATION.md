# Tournament server integration

The player entry point is `SharedHub`, composed with `ServerWorkspace` and the
application UUID returned by `EltenGameRoom.server_app`. Local trial adapters
remain available to source tests; release staging excludes their unreachable
modules. Server refusal never selects a local-storage fallback.

New tournament drafts use the game's current creation defaults, including the
interface-dependent content language and non-control rule-version markers:
`new_game_options(table_creation_options({}))`. Prepare the selected options
again before their first publication, since the user may have changed a variant
or returned through Back. Editing an existing publication and starting its fixed
bound matches must preserve their recorded options; neither is a new-game upgrade.

`Publication.validate_game` checks declared control types before generating any
additional metadata prototypes. Only detached, already validated controls seed
the game-owned creation/new-game hooks; unknown input keys never seed their own
schema. The existing normalized-unchanged and game semantic checks still decide
whether each value is canonical. Known ordinary rows need no extra prototype
generation. Regressions: `new_draft_game_options_native_test.rb` and
`game_owned_option_metadata_test.rb` in `test/tournaments/`.

## Storage and authentication

`ServerSchema::PROPOSED_TABLES` declares three append-only tables:

- `tournament_announcements`: publication identity, game, rules, settings and dates.
- `tournament_registrations`: enrollment, withdrawal, pairing, amendments,
  cancellation, registration invitations and their explicit declines.
- `tournament_plan_documents`: schedules, phases, elected table creators,
  native-table bindings, start intents, continuations and results. Older
  availability/consent/participant-lease records remain readable for recovery;
  the active player flow no longer writes or renews them.

The SDK insertion author, ordered server IDs and timestamps authenticate events.
Names inside JSON are not authentication. Publication-specific projections
reject conflicting evidence without letting an unrelated malformed tournament
break the directory. Protected tables still require the official launcher stamp.

The organizer alone appends an `invitation`; only its recipient can append
`invite_declined` for the same operation key. These records use existing
nullable columns, preserve delivery-name spelling, never join or pair anyone,
and do not renew abandoned-tournament retention. A recipient can be invited
only once per tournament, including after decline, joining or withdrawal.
Version 2 registration notices refer to that persistent key and remain valid
while registration is open, without a separate seven-day lifetime. Version 1
notices retain their original lifetime and metadata contract. A confirmed
invitation row is not proof of notification delivery; delivery keeps its
separate durable attempt journal and never retries uncertain sends.

`ServerDocumentRows` reads by ordered ID in pages of at most 1,000 rows. A short
page is not EOF. The initial upper ID bounds each snapshot; repeated IDs, no
progress or exceeded budgets fail closed. Limits are 65,536 rows and 32 MiB.
`ServerReadScope` shares copied reads within one operation, not indefinitely or
between workers: at most 2,048 queries and 32 MiB. A contiguous acknowledged
append invalidates matching queries while retaining only provably unrelated
immutable ID partitions. Gaps, malformed acknowledgements and uncertain writes
invalidate the entire affected table. Nested authorization in one archive
verification can share a freshness check only while intervening reads stay
local; any actual SDK operation or leaving that verification ends this reuse.

The revision read also retains the complete latest row; refreshing an unchanged
head does not fetch that same row a second time. Complete operation-key reads
can answer subsets and unions within the operation, with author filtering
still applied separately. Only successfully completed bounded reads enter this
cache; partial pages and failed reads never establish absence. The cache remains
thread-, provider- and account-scoped and is discarded at the end of the operation.
Independent document keys are read in batches of at most 96. Directory projection
prefetches root phase/result keys in batches and preserves each tournament's own
error and retention handling. It does not copy a previous directory as authority.

Plan documents are limited to 256 KiB. Multipart records carry at most 1,536 raw
bytes each, up to 171 parts plus a header, within the 2,048-byte field limit.
Only complete digest-checked documents can be used; missing parts are not an
empty document.

## Game-owned results and bound policies

New bindings use `GameResult::CURRENT_RESULT_POLICY` (v8). The game's
`tournament_winning_units_result(replay, options:)` returns the complete public
winning units; by default it delegates to `tournament_placement_result`. Tile
games share an implementation using `tournament_result_from_public_winners`,
so a blocked Mexican Train game can retain every public co-winner. A complete
team is one unit; arbitrary private state fields are not a generic result API.

The binding retains its policy. v1-v7 results still use their original hooks,
including pending old games, and no stored receipt is migrated or recomputed
under v8. Placement scores and the explicit small-point capability remain
separate from the winning-unit export. Verify tied winners, a full draw, teams,
standings, unchanged historical exports and creation/reuse of old bindings.
Regression: `test/tournaments/tile_winning_units_policy_test.rb`.

## Coordination through the existing API

Public registration currently assembles fixed pairs, not larger fixed teams.
`ServerCapacity.supported_player_counts(game:, options:)` is the shared public
match-size capability used by setup, publication preflight and Start. Keep
generic `game.tournament_capabilities` intact: the separate local declared-team
planner supports larger units. Do not publish a six/eight-seat Taboo tournament
as individual players and discover the unsupported format only at match entry.
Reject before preparing a publication intent, using the existing localized
players-per-match refusal. Regressions: `public_match_sizes_test.rb` and
`public_match_sizes_native_test.rb`.

Start validates the actual currently registered roster with `ServerCapacity`,
the same bounded planners used for advertised capacity. A valid maximum does
not imply that every smaller group roster is playable. Only exactly two units
can use the automatic direct final; three must satisfy the real group planner.
Validate before preparing the Start amendment, without fabricating a closed
publication or dropping same-second registrations. Normal source and entry
gates still read their authenticated history. Regressions:
`start_schedule_capacity_test.rb` and `start_current_roster_groups_test.rb`.
The latter also checks the specific localized group-settings refusal; a known
invalid roster must not be reported as a network or uncertain-write failure.

An authenticated successful coordination observation replaces its previous
scheduled wake, even when the publication is now cancelled or has no next
change. Do not retire a timer on a failed or unauthorized read; keep the normal
retry job. `coordination_cancelled_deadline_test.rb` checks the actual workspace
cancellation, a retained timer through read failure/recovery, and no future work
for the cancelled tournament.

Editing publication metadata preserves existing concrete playing windows and
their stored timezone. Opening and saving the optional dates dialog does not
migrate them to unrestricted daily play. Its conditional retention control
allows the organizer to explicitly remove them or replace them with daily
hours; the two schedule models are mutually exclusive. New publications keep
the existing optional-date and daily-hours flow.

Active clients coordinate through authenticated append-only records. No custom
Ruby code runs on ELTEN's server and no additional daemon is required for this
workflow. Participants can coordinate an existing schedule while its organizer
is offline.

Play opens one ordinary native table for the planned fixture and sends ordinary
table invitations to missing participants. Any planned participant can create
it; the earliest authenticated creator record wins, including when two people
press Play together. Planned seat order and team membership do not depend on
who creates the table or who joins first. There is no readiness screen,
tournament acceptance record or renewable player reservation.

Recipients use the normal notification action or Ctrl+J and join directly.
Ordinary invitation expiry is five minutes. Decline, expiry or departure does
not publish a sporting result. Play can reuse the same table and send new
invitations. Starting the game checks the current tournament source, permitted
playing window, native host, roster, options and fixed game-instance binding.
A changed source cannot be authorized by an old invitation or cached view.

Native metadata contains a tournament pointer. Discovery packs its two digests
to stay within the existing metadata budget. This pointer is not authority:
entry resolves the authenticated binding before joining. The presenter may
reuse that exact in-memory attachment without reading it again just to display
the table; starting and result publication still validate fresh evidence.
Normal tables have no pointer and keep their existing path.

After that fresh entry check, the shared join-role hook uses the verified
binding's roster without another tournament read. Accounts outside this match
join as observers, whether registered elsewhere in the tournament or not,
through both public discovery and ordinary invitations. An already established
observer role is not written again. The start guard still requires the exact
planned playing roster; display metadata never grants a player seat.

The coordinator performs event-driven directory, phase, result and start-notice
work only. It has no active-match renewal timer. Enrollment, withdrawal, partner changes and organizer
actions also wake authenticated tournament views. A wake contains a reference,
not state or authority: readers revalidate it against the server. There is no
periodic public-directory polling. Known scheduled dates use local timers.
Internal `game_room.tournament_changed` wakes are excluded from both native
notification lists through the existing application-scoped host bridge.
`suppress_default!` only silences delivery; by itself it leaves an empty row.
List rendering must not replay coordination or revoke other notifications.
Normal match invitations and tournament-start announcements remain visible.

New tournament-start notices retain the original title and game in scoped
metadata from the authenticated organizer. The notifications list renders that
description without a server read, even after a runtime reload or delivery
expiry. Description is separate from eligibility for automatic speech/sound:
delivery still needs fresh verified evidence and respects notification sound
preferences and the host's quiet mode, including while the tournament UI is
open. There is no area-specific mute. List rendering cannot change delivery
state or play the sound as a side effect. Event
identity excludes the description, so a metadata upgrade cannot resend a
previously attempted notification. Older notices without a description can
only retain it while their verified in-memory evidence remains available.

Transient notice verification failures allow three read-only retries, with
backoff and respect for the server's retry delay. Cancellation, a stale source,
account changes and programming errors do not trigger retries. Receiving a
notice never repeats consent, delivery or table creation. Delivery journals
retain both confirmed and uncertain sends. Start/final information uses
`expires_in: 0`, without a late-start delivery cutoff. Its journals are scoped
per publication; matching entries from the previous global journal are copied
without expiry, never discarded or resent after an uncertain delivery.
Final v2 metadata records each recipient's place, the team flag and winners,
so its historical text survives runtime reloads and tournament retention.
Round-robin places come from verified standings; knockout elimination cohorts
share a place. Teams are single units, and separate group scores are not used
to order eliminated players across groups. A void knockout final has no winner.

Verified coordinator observations refresh only actionable notice proofs.
Pending registration invitees also receive authenticated change wakes before
they become players. There is no periodic notification storage scan. An
obsolete notice is hidden by the scoped list bridge; its native lifecycle
entry remains until ELTEN revokes it on the server too (checks every 60 s).
Permanent informational records are not withdrawn merely because the source
tournament was renamed or removed. Tournament match invitations bypass contact
filters and the blacklist, but retain sender checks, native quiet mode, volume
settings and the original five-minute invitation boundary.

Creation has one durable claim per table attempt, not a claim per player.
A partial earlier creator document blocks a competing creator. A lost native
creation acknowledgement is reconciled, never treated as permission to create
again. A complete successful discovery read can establish that a bound public
table has closed; only a never-started table may then be replaced. The
replacement links to the preceding binding digest and elects its own creator.
A failed discovery read cannot establish closure.

Before the first native game starts, an immutable start intent is retained.
A started game or uncertain start/result cannot be silently replaced after
closure. It requires explicit organizer handling.
Start intents and creator claims do not expire like invitations. A creator
that disappears before its table can be confirmed may leave an operation for
manual recovery rather than risk a duplicate table.

While a native Messages/forum window covers an open table, ELTEN can suspend
its extension ticks. The existing covered-table presentation bridge therefore
pumps the same tournament coordinator on the active UI thread. Foreground and
covered calls share a one-second, non-reentrant cadence; network work stays on
the coordinator's finite worker. Do not tick all host extensions, start a second
game executor or poll the tournament directory from the UI. Closing the table
removes its presenter. Regression: `covered_coordination_runtime_test.rb`.

Legacy participant-lease reconciliation retains its original authenticated
prefix, release and expiry rules. It is not called by the new entry flow.
Do not use an expired old lease to discard an uncertain native start or result.

This is cooperative coordination, not a server transaction or anti-cheat
authority. The API has no compare-and-swap transaction spanning tables and
native session creation. Ordered claims and readback reduce ordinary races,
but cannot promise exactly-once effects during every partition or protect
against modified clients. Stronger guarantees need trusted server logic.

## Matches, results and recovery

The Matches and Results views obtain the schedule and result projection in one
worker operation through `schedule_overview`, using the same bounded
`ServerReadScope`. Display does not publish a redundant observed plan document:
the response is explicitly `storage: observed`. Older plan journals remain
recoverable through `shared_schedule`. Constructing a match service also grants
no authority and does not separately read its source; the first entry, start or
result operation validates it. The views reject differing
schedule IDs and discard the scope afterward. Automatic updates may reuse the
coordinator's freshly published presentation for that same schedule. Pending, failed or in-progress
coordination cannot supply a cached presentation. Initial/manual reads, a phase
change and organizer match controls use the server normally. Starting a match
or awarding a forfeit still uses the separate mutation service and its fresh
authorization checks, never the display snapshot as authority.

Confirmed forfeits and reconciled result/forfeit writes emit the same scoped
change signal as ordinary game results. Failed or unconfirmed writes do not
announce a successful result. The receiving view still revalidates the server
records; a signal contains no score or authorization.

Matches use ordinary LiveSessions, game executors and immutable history.

First-to-wins history spans multiple phases: draws do not consume a required
win. Validate the whole series and each pairing with
`Standings.validated_results(max_results: 4096)`, retaining its byte/node and
identity/score checks. Do not use the ordinary `Standings.calculate` aggregate
as a history validator: its unchanged 256-result limit belongs to one phase.
Regressions: `knockout_win_series_capacity_test.rb` and
`knockout_single_pair_history_test.rb` in `test/tournaments/`.

An ordinary-match service retains its validated bindings for later result
reconciliation, but opening/attaching a match does not start an idle thread.
Its result consumer starts lazily when a terminal result or explicit local-retain
retry is queued and exits after draining. Queue admission, retry and handing off
the worker slot share one lock. The service remains a managed runtime resource
until close, rather than re-registering itself on every finite worker run.
Do not evict uncertain bindings or change result authority to reduce idle cost.
Regression: `test/tournaments/ordinary_result_worker_lifetime_test.rb`.

Started individual matches share a cumulative 300-second absence allowance per
player. The current host records observed native membership loss through the
existing ordered `game_boundary` stream, pausing the game clock. A return does
not reset the allowance; a new host does not charge an unobserved interval.
These are authenticated client assertions, not server-attested absence. Team
matches do not silently inherit an unagreed automatic-forfeit policy.

Boundary revision, previous boundary, controller epoch, fixture and binding
identity fence every decision. Already-started private operations retain their
original request identity across a pause; direct acknowledgements, recovered
acknowledgements and cold replay must use the same logical clock. New ordinary
inputs remain blocked while paused. A client-supplied origin boundary is not a
cryptographic attestation of when the request began.

Games declare whether active play can continue after an automatic absence
elimination and expose their last fully scored checkpoint. The shared projection
alone emits trusted elimination events; an ordinary action with the same name
is not sufficient. Original seats and historical authors remain fixed, while
active participants shrink. Final results append eliminated participants in
reverse elimination order. An unknown checkpoint is not a zero score.

Manual Ctrl+F settlements use v3 receipts, complete place groups and the game's
explicit small-point policy. They cannot interrupt active play. The organizer
confirms an immutable consequence preview; confirmation and recovery validate
its native-history boundary. Earlier receipt formats remain read-only.
Incomplete authenticated administrative parts are not a result in the standings,
but they fence creation/start, including entry recovery and a paired return leg.
Only recovery of the exact organizer intent can finish that partial archive;
it does not grant another client permission to start meanwhile. This preserves
the cooperative, non-transactional limitation described above.

The compact read-only history of previous phases retains each `schedule_id`
and the knockout round's seeds and player count. Native phase lists need stable,
unique IDs, and phase names depend on the bracket size. Do not substitute list
indices or change canonical stored plans to repair this projection. Regression:
`server_phase_history_ui_native_test.rb` traverses the actual phase store and
then builds the native match/result controls.

Bindings include native session, game instance, seats, options and history
lineage. Result lists traverse independent binding chains together, still
validating every creator, continuation and replacement in order with the
existing 64-step bound. Start and collection reuse complete match-document
batches without removing fresh authorization at write boundaries.
Return matches reverse the agreed seats. Result publication retains
a copied canonical intent before its first network read. A failed read or lost
acknowledgement must not silently discard a finished game. Conflicting results
block progression instead of choosing an arbitrary winner.

Tournament matches cannot be saved or resumed from private archives. The shared
UI hides Save, and service/result boundaries reject archived or restored matches
even when invoked without that UI. Historical binding chains remain readable
for inspection, but cannot authorize a new playable continuation or its result.
Ordinary non-tournament saves are unchanged; observers are not archived.
A closed, explicitly reserved waiting room may be replaced only before a
durable start intent exists. Ambiguous starts require recovery, not a fresh table.
Canonical binding bytes must agree locally and on server readback; JSON key
insertion order must not change a result digest. Sporting cancellation rejects later results without
closing a native table owned by another account.

Network work runs outside the UI. Tournament invitations share the normal
invitation list and accept/reject actions. Dismissed notices cannot be restored
by an older pending validation task; inactive notification fallback text is
nonempty. Opening an obsolete notice reports that it is no longer available.
Recovery uses bounded retries of 30, 60, 120, 240 and then 300 seconds. Uncertain
operations retain their keys and reconcile before retry. The journal preserves
unresolved operations instead of dropping them to meet its 128-entry
completed-history target.
Network failures also retain the failed startup or one-shot coordination job;
retrying does not require reopening the tournament or receiving another notice.

## Optional timing and player views

Publication schema 2 uses zero for manual registration/start dates and an empty
playing-window list for unrestricted hours. Opening, closing, starting and a
final organizational deadline are independent options. Starting also closes
registration. Owner actions append authenticated amendments; they do not change
historical eligibility or silently revive rejected registrations. A final
deadline blocks creation and start of new matches, but never awards forfeits or
interrupts an existing game. Rejoining an already-started bound session remains
possible after the deadline or outside daily playing hours; starting or replacing
an unstarted table does not.
An expired rejoin may first acquire native membership to inspect history, which
is unavailable to nonmembers. It must verify the same bound game and release
that newly acquired membership if the table has never started.
Sporting results advance phases and complete the tournament. A passed deadline
is displayed as “Deadline passed” without changing canonical publication or match
data. Unresolved expired tournaments remain in Current with the usual ordering;
only sporting completion moves them to Completed. Existing schema-1
publications retain their recorded dated contract.

Registration projections retain authenticated display names separately from
canonical account keys. Notice delivery uses those display names without
rewriting schedule candidates, bindings, operation keys or historical results.
Organizer notes use the existing publication `rules` field; no schema change is
needed. Returning to game settings preserves the tournament form. Automatic
scoring text is rendered in the viewer's language. Exact legacy catalog forms
are recognized without rewriting publications; custom organizer text is kept
verbatim, and new empty notes use the English source default on the wire.

The UI has one Current/My tournaments/Completed directory, a contextual
dashboard, one Matches entry, separate results and optional date settings.
Everyone sees all matches in the selected phase: unfinished own matches first,
then other unfinished matches, then completed matches. There is no ownership
or state filter. Opening the schedule selects the first unfinished own match. Later refreshes
preserve the selected match instead of jumping ahead. In-place updates must not
refocus controls: native navigation already announces the selected item.
Team partners must choose each other; an owner
can manage teams. Ctrl+Shift+T provides own-tournament access only from the main
lobby and the widget, without acquiring another application instance. Explicit
Refresh and Check pending changes remain available after uncertain operations.

Membership UI attempts latch before calling a write. A confirmed attempt may
retire after a successful fresh read of the same publication; this lets a
later registration epoch be joined, withdrawn or removed in the same window.
Confirmation alone must not unlock a stale view after a failed refresh.
Unconfirmed, attempted and conflicting writes keep their recovery guard.
`PublicService` owns operation identity and registration-epoch idempotence;
the view neither retries a write automatically nor fabricates membership.

## Abandoned tournament retention

`TournamentRetention` derives expiry from authenticated server timestamps: 14
days without accepted registration or organiser activity before the start, and
30 days without a confirmed sporting result after the start. Future registration
opening and start dates are respected. A completed tournament is retained.
Viewing, readiness, invitations, native table traffic, duplicate document parts
and invalid records do not renew the period. Result timestamps use the earliest
complete authenticated copy, including results from previous sporting phases.
A write after an expired gap cannot revive the tournament.

The server tables are append-only for players. Expiry therefore removes a
tournament from the application directory and rejects new actions on its old
reference; it does not physically erase server rows or award automatic forfeits.
Immutable evidence remains available for reconciliation of past writes. A known
expiry schedules one UI refresh, not a periodic network worker. Reads and normal
entry checks use the same policy on every account. Failed or incomplete result
reads must not be treated as an empty history proving abandonment.
An authenticated partial administrative receipt keeps an otherwise unresolved
fixture uncertain; it does not renew its progress timestamp. A complete valid
result still takes precedence over a later unfinished upload. If completing an
old upload makes its tournament expire, reconciliation may read the fresh
unfiltered publication evidence only to confirm that exact, already complete
result or sporting-phase document in the local journal. This read-only path never appends missing parts,
revives the tournament or grants entry to another game.

## Capacity and verification

The default is 16 participants. A phase may contain at most 256 matches;
preflight computes the schedule before publication. The form's selectable
ceiling of 128 does not guarantee every format fits. Groups, rotating
compositions or smaller limits can reduce the schedule.

Verify publication, ordinary invitation acceptance/refusal, competing creators,
empty-table replacement, ordinary and return seats, automatic results,
rejection of saved continuations, cancellation, lost acknowledgements
and organizer-offline operation. Local simulations and live accounts on one
computer are separate evidence; neither proves independent-network behavior.
See [administrator handoff](TOURNAMENT_ADMIN_HANDOFF.md).

Request-budget regressions: `server_directory_batch_test.rb` compares identical
24-tournament projections with and without prefetch; `ordinary_match_read_budget_test.rb`
requires 24 bound matches to use at most four document-table reads and no writes
for their result view. These are bounded local fixtures, not estimates of all
HTTP traffic. `server_read_scope_documents_test.rb` covers short SDK pages,
complete subset/union reuse, author/account/cursor isolation, uncertain writes
and later-page failures. Keep the source-change, continuation, cancellation
and result-recovery tests alongside these performance checks.

## Local diagnostic plan identity

The isolated local planning tools are not the official server tournament flow.
Their team and individual forms share `LocalFixedTeamPlanScreen`: the accepted
preview is bound to the entire displayed input. A changed tournament, seating
or team template needs a new preview before configuration. An uncertain write
retains its original intent and shown input for Check; changing the selector
must not replace or discard that pending operation.

Accepting the same assignment again can intentionally produce an alias to one
immutable plan record. `LocalTournamentDispatcher#target!` resolves that record
before policies, availability, proposals and execution selection use its original
intent. The storage validator still rejects foreign policy keys. The locally
captured own heartbeat retains its original lookup token; its due check performs
no backend I/O, and renewal revalidates the canonical target before writing.

Regressions: `local_plan_target_native_test.rb` covers changed selections and
lost replies after durable replacement; `local_plan_alias_native_test.rb`
covers two ordinary native form visits in both families; `dispatch_plan_alias_test.rb`
covers alias configuration, renewal, invitations, admission and exactly one Start.
These scripts live under `test/tournaments/` and use isolated local storage,
not authenticated remote account trials.

The local K03 readiness adapter also accepts the complete current
`ScheduleCandidate`, not a historical field subset. Optional `starts_at`,
`daily_hours` and series win targets are preserved in source identity and
validated on cold read. The gate remains closed, roles unassigned and the
original source is rechecked before a write. The native regression
`local_readiness_current_setup_native_test.rb` covers the real current
Hub/setup/dates/join/Prepare/Accept path; `local_readiness_optional_candidate_test.rb`
adds daily hours, group-series targets, typed corruption and idempotent readback.
