# Architecture

## Data flow

ELTEN launches `EltenGameRoom` from `__app.rb`. The program creates table and
game repositories over a single LiveSessions store. A table is a public or
private session, and its stack is the authoritative, ordered history of the
room, chat, started games and moves. Game state is not stored as a single
mutated object. The server holds ordered events, and each game's class
reconstructs a `Replay` from them.

A typical move follows this path:

1. the shared game surface creates an action description;
2. the game validates the action in `action_for` and returns an `ActionPlan`;
3. `GameRepository` appends the entire move plan as one atomic stack entry;
4. LiveSessions delivers the same entry to the other participants;
5. each client reconstructs the state and updates the form only after an
   actual change.

This separation matters: the interface does not define rules, and the
transport does not interpret moves.

## Layers

Typing Mania's model is in `games/mania_pisania.rb`, with save handling in
`games/mania_pisania_support/`. Its client, typing engine, Braille input and
text library live in `lib/mania_pisania/`; `typing_surface.rb` in
`lib/game_surfaces/` connects typing input to the shared game UI. The text
library owns the UTF-8 byte limit for both file and pasted imports. Dialogs
report validation errors while retaining the input for correction. Table
options use the game's option-editor extension and carry a bounded text
descriptor; shared-text preparation handles transfer separately.
The practice buffer retains raw braille cells for validation; the editing field
receives their back-translation so native focus and navigation can read the
entered prefix. Presentation never replaces the engine's raw input.
Braille grading accepts the lowercase, source, title-case and uppercase
spellings produced by the selected Liblouis table. Word streams retain the
actual accepted cell prefix, including optional capital indicators, in saves.
A newly selected table applies at an empty input boundary; a pending word
keeps its old table until completion or deletion. Applying the new table also
invalidates the stream's cached expected spellings.
Personal settings expose the braille table as an inline list. Draft values,
including that table, are saved in one settings write through the native form's
accept button; Escape/Cancel discard them. A new custom-table choice opens the
existing file browser on save, while an unchanged custom table remains selected
by filename without reopening that browser. Active practice receives the new
table only after validation and successful persistence.

`lib/use_cases/` handles invitation acceptance and game saving, while the
application provides their UI. `game_screen/input.rb` stores the current
replay and revision for a single form. `GameRoomEventPresenter` shares
presentation between visible and covered games, without access to controls.
It does not execute the model.

`RoomState` is protected by the LiveSessions store's lock. Retention removes
it as a whole; the native-connection index and discovery queue remain in the
store. Projections, writes, invitations and archives have separate modules.
Each retained state is bound to its opaque native resource ID. A new membership
of that same ID preserves the ordered history and uncertain writes, but rotates
the local visit token. A different resource with the same application table number
is refused before reading or admitting its history; it does not replace the
retained state or borrow its IO/subscription counters. Normal bounded inactive
retention may later retire that alias. Own creation avoids all retained numbers;
this is not an account-wide one-table limit or an automatic room substitution.
Discovery joins, row-bound snapshots and lobby admission also compare the native
ID. See `test/transport/native_room_resource_identity_test.rb` for the real SDK
constructor/stack/callback control with local replies and no live network.
The history validator still runs outside the lock and checks source identity
before publishing the cache. Named contracts are in `game_session_contracts.rb`;
adapters preserve the existing rows, revision pairs and wire format.

Blocking stack reads validate the complete native page before ingesting its
first entry or advancing the room cursor. Session identity, contiguous positions
or an explicit trim gap, cursor/through and completion must agree. Malformed
successful envelopes enter the existing transient read-recovery path; they
cannot become successful partial snapshots. This boundary does not replace
packet authority or game validation. Detached local adapters return the same
page shape; no additional polling or SDK patch is involved.

Game-change wake-ups coalesce into one signal per retained room, not one entry
per past game. The shared synchronizer consumes that room signal; only the
authenticated repository snapshot selects the current game and its revision.
An old hint may request one harmless check, but cannot switch the game or
accumulate after rematches. Runner subscriptions keep independent wake-ups.
ID-only test/external transports retain the previous synchronizer fallback.

`GameRoomReplayCache` is an optional bounded reducer checkpoint, not a source of
write authority. Its adapters pass a copy of the session without only the native
`__game_revision` CAS; the original session and its write guards keep that token.
Pass the previous `Input` on the next read and retain it only while
`retention_bytes <= GameRoomReplayCache::MAX_BYTES`. The shared input can reuse
an immutable native prefix only for the same explicit repository authentication
identity; mutable rows and changed authors/IDs/session context are checked again.
Supply resource and localization identities to `reduce`, and return owned model
copies. Duck Racing, Monopoly and Mahjong show the same contract. Their
regressions compare cold/warm replay, native CAS-only updates, appended actions,
changed earlier records, authority changes and historical views.

Private Mahjong also binds the prepared input to the current local membership
token. A missing token bypasses the optimization; obtaining it must not perform
network I/O. Its input plus the complete session/player context has an 8 MiB
serialized retention cap, separate from the shared checkpoint's 8 MiB cap;
neither is a process-RSS measurement. Refused admission drops the prepared
input, resource and checkpoint together. Adapter-local replay serialization
keeps their admission/refusal in the same operation, without serializing other
games, transport or executors.

Checkpoint accepted moves and both private audit tapes as positions, never as
Marshal-copied event Hashes. Only a full authenticated prefix/context match may
hydrate those positions from the current canonical `Input`. Restore the tapes
before an appended reduction and on a warm return, including after an older raw
history view. Preserve absent/nil tapes before the hand starts. The maintained
private-cache regression checks those transitions against complete cold replay,
real scoring audit, account resource changes and both retention refusals.

Surface specifications are pure data in `game_surfaces/specifications.rb`,
independent of host controls. Rules are generated by the compiler described
in [BUILDING.md](BUILDING.md). The game declares local board preferences, and
validation allows only permitted values to be stored. Cursor data, drafts and
model state are not preferences.

### Manifest and program composition

`__app.rb` contains ELTEN metadata, auxiliary-table declarations and the main
program class. The model registry is in `games/catalog.rb`. Current tables
support user registration, global-lobby announcements, table subscriptions,
Krowa features and [statistics](STATISTICS.md). The former table, membership,
invitation and move tables are not a second game backend. Account archives
are stored by the private-file service, not in a table.

Krowa's optional attempt histories use `krowa_attempt_lists`: immutable
2048-byte payload parts, scoped to their publishing account and a
content-derived `list_key`. Add `history_key` (`string:64`) to
`krowa_word_scores`, `krowa_daily_scores` and `krowa_tower_rounds` before
enabling the feature on the server, plus `histories_shared` (`integer`) on
`krowa_tower_scores`. The latter records the final sharing choice even if a
failed earlier upload wrote optional round details. Public tower details
redact history references unless the published summary explicitly shares them.
This is an additive schema update by
the application's owner; no existing rows or tables need to be deleted.
Old rows and results published without histories have an empty/missing key.
Publication checks the remote declaration once per services instance. Until
the additive schema is available, sharing histories returns explicit feedback
and leaves ordinary score publication usable, without querying a missing table.
The canonical earliest row for an exact personal-best score selects its
history. A later playthrough with the same count cannot replace that list.

Only scored, accepted guesses enter a list. Publish/read back every part
before writing the score's reference, and reconcile uncertain writes through
reads. A partial upload can resume with its original nonce and content;
it must never produce a truncated list or a score referencing missing parts.
For concurrent identical uploads, the earliest native row fixes the nonce;
parts of competing envelopes are never combined with that canonical copy.
Histories use authenticated encryption to avoid exposing today's answer as
plain table data. As with daily assignments, the embedded application key
does not protect against modified clients. Ordinary daily-history reads
require a past Warsaw date confirmed through the server clock and do not
download today's or future payloads. The local solo gallery retains its
own best-result attempts independently of public sharing. Match state and
saved games remain based exclusively on the existing accepted event log.

Withdrawn Krowa nouns have a separate authored list, compiled with the active
dictionary. They remain recognizable for historical scores, but never enter
new draws or ordinary guesses. A canonical saved daily assignment may still
authorize its own withdrawn answer; it does not authorize other retired nouns.
Do not replace that whitelist with arbitrary public table text or recalculate
an existing daily answer after changing the active dictionary.

### Display names

Human display names are presentation metadata, separate from account identity.
Native `participant_metadata` carries a name at create/join/accept; later
`room_profile` stack records accept only the authenticated sender's own actor
and normalized display name. They are not game actions or control amendments.
Cold reconstruction can retain a departed player's label without replacing any
login in rosters, event actors, authorization, invitations, statistics or CAS.
The existing registry and subscription schemas remain unchanged.

Native public discovery exposes participant IDs/logins, not participant
metadata. The table owner therefore republishes `owner_display_name` and an
optional bounded `display_names` roster through existing discovery metadata.
These labels stay scoped to that public table view and its native roster;
they never enter the global participant-name directory. Direct participant
metadata and accepted self-authored profiles take precedence, including an
explicit empty profile that restores the login. Discovery has no native owner
identity field, so its claimed owner cannot authorize a global profile change.
The labels remain within its 1024-byte JSON budget; optional names never evict
game settings or control anchors. Invitation and
new-table notification metadata similarly carries `sender_display_name`, while
the native envelope sender still owns identity checks and notification keys.

### Access to auxiliary tables

Every `program_main` call and entry through a notification rechecks access to
`game_room_users` with a minimal read for the current account.
`GameRoomServerTables` shares the result with existing table handles.
Detection uses the server response: the `apps.tables.stamp_required` code
means developer mode without tables.

After access is denied, no further reads or writes to auxiliary tables are
performed. Global-lobby history polling does not start; features requiring
tables indicate the access restriction. Local Settings categories still work,
and unknown subscriptions must not be saved as an empty list. Discovery,
gameplay, invitations, room history and chat use LiveSessions and ELTEN
notifications, not the former invitation table. Timeouts and other errors
also suspend table operations until the next entry, but are presented as an
access-check problem, not developer mode. Running main again may restore
table features without creating a new application instance.

### Game models

`GameRoomGames::Base` defines the shared contract: identifier, name, rules,
player count, options, validation, game start, replay, actions, surface,
history and an optional bot strategy. `TurnBasedBoardGame` adds a standard
piece-to-square move model for turn-based board games.

Every game must deterministically reconstruct the same state from the same
events. Randomness should be represented by an event or a controlled source
from `game_random.rb`.

### Shared interface

`GameScreen`, `GameRoomLayout`, `GameRoomShortcuts` and `GameSurfaces` build
an accessible game form. Surfaces include a board with pieces, a pawn track,
a card hand, a dice tray, a command panel, an answer sheet and a scoring view.

The table and game form share one order: start, restart or waiting information,
an optional game surface, chat, history and users. Start is available before
the first game, and restart after it ends, both for the owner only. Other
participants see inactive waiting information in the same place. The standard
repository creates a new session, and the table controller opens its screen.
Entering your own waiting table focuses the start-game control; other
participants focus the waiting information. Starting, restarting and ending
a game do not steal focus from chat, history or the participant list: they
also preserve the draft, selection and viewed entry. The game surface changes
silently, without interrupting final announcements. There is no separate
preview mode. Action attempts still go through `action_for`, which rejects
them with a game-ended message. Normal updates within the same game preserve
the active section, selected participant's identity, chat draft and selection,
and the history position being browsed.

`GameRoomLayout::Screen` preserves the form, lists, buttons and chat editor;
it changes only the required game surface. The session identifier allows the
board selection to be preserved on re-entry and cleared for a new game. Event
bindings are replaced without multiplying native handlers, and timers are
removed when leaving the view. `GameRoomParticipantMenu` binds a single context
menu to the shared form: game rules through Ctrl+F1, inviting an online user
through Ctrl+I, inviting from contacts through Ctrl+Shift+I and adding a
computer through Ctrl+O. The menu and shortcuts work from every table field,
including during a game and after it ends. Delete remains a local action of
the user list and removes only the selected computer. All operations check
the current state and permissions, including after the menu opens. Returning
from the rules preserves the previous focus and chat draft.

Ctrl+J and the “Zaproszenia” (“Invitations”) context-menu item work throughout
Game Room, including in the game field, chat and history. Ctrl+J in the widget
uses the same path, directing handling to the active program instance.
Rejection through Ctrl+Shift+J remains a main-menu shortcut. A notification
allows accepting or rejecting a specific invitation. All these entry points
check that it is current and clean it up only after handling it; switching
to another table preserves the restrictions on leaving the current game.
Do not add separate mechanisms to individual fields.

Recipient decisions remain scoped to the exact invitation identity. An active
repository opportunistically retires a finite-expiry decision only after both
the invitation expiry and the response-outbox retry horizon. Still-valid and
legacy no-expiry decisions retain their original idempotency; pruning the local
decision cache never cancels an independent pending outbox delivery.

Process-local entry ownership is separate from table membership. Notification
and widget entries recheck the exact owner before admitting a redirect; if that
owner finished since lookup, route again instead of focusing the retired window
and losing the request. A cold widget entry still schedules a fresh Core-owned
scene. This does not make the bounded pending-entry queue durable after a normal
close or error; startup installation retains its explicit request handoff.

`RoomPresentation` stores participant identity separately from the label.
The game provides `participant_scores(replay)`: a map from participants to
scores, or `nil` if it does not track scores. Farkle, Thousand, Spades and
Categories return scores from the reconstructed state. Spades assigns the
team score to its members. Zero is a score; observers and games without
scoring do not receive an artificial score label. The finished game's scores
remain next to the current participants until the next game starts.

The game describes the surface and actions. It should not create its own form,
intercept system keys or manually drive the UI loop unnecessarily.

Games can declare `paced_event_presentation?` and return plain-data stages
from `event_presentation_stages`. The existing presentation queue separates
speech/sounds with monotonic, non-blocking delays; accepted events stay atomic.
Duck Racing uses one second between a race roll or an effect's displacement
announcement and its destination, including each move in a chained effect.
Destination rewards stay together. It uses two seconds between announcing a
challenge winner and the feather settlement,
and two seconds before a new turn or resuming after a challenge. Draws and
results without a feather change or freezing do not add the winner pause.
Its client defers new
challenge prompts/input until the queue finishes. The same runner view gate
applies in the foreground and behind another window; chat, network delivery
and local navigation continue. Other games keep their existing behavior,
including Battleship's sequencing by actual sound completion.

Duck Racing's sound-pair choices use a transient client playback handle.
An opt-in stage waits for its completion before presenting totals or the next
player; the same queue's watchdog and close handling apply. Digits and match
feedback are spoken with their sounds, never added to game history. The
client continues audio on its existing UI step while the shared queue is busy;
it must not independently announce the next turn from a refreshed snapshot.

Sound ordering starts after a shared five-second preparation and countdown.
The model rejects earlier swaps and starts its timeout at that boundary;
the client also waits for actual cue completion before accepting fresh keys.
It uses the existing progress loop, not an additional timer or speech wait.

Duck challenge bots add the configured bot pause to each planned decision,
including private trace inputs. Listening durations and rhythm intervals are
unchanged; private decisions keep the ordinary one-second deadline margin.
The delay belongs to the planning-cache identity. The existing session runner
still revalidates and writes every action; no separate bot executor is used.

Private Duck attempts retain their original canonical inputs, timestamps and
salted commitments. The wire codec delta-encodes times and press identities,
stores repeated input fields by a fixed mask, then compresses the envelope.
Pages retain session, round, seat, codec and byte-range metadata. The native
writer rechecks their complete packet size against the current grant and
controller epoch; it may split only an unsent range. Accepted page boundaries
and durably cached compressed bytes survive recovery unchanged. Pending
`zlib-json-1` uploads can finish after a code reload; new attempts use
`zlib-trace-1`. Neither codec truncates attempts or changes their scoring.

Selected question resources are validated once and shared between fresh Duck
game objects in a bounded cache of eight immutable selections. Cache identity
includes actual pack and language-profile objects, so a registry replacement
cannot reuse old content under the same ID. Label/discovery formatting does not
prepare question data. Disabled word challenges have no runtime dictionary.

After a verified replay, the session worker calls `cleanup_session_answers`,
including for a finished game with no next turn. Duck cleanup uses closure
receipts derived from accepted events, not a game object's transient memory.
Only this account's matching, confirmed or cancelled attempts are removed;
uncertain writes and other scopes remain. Failed local cleanup is retried on
a subsequent refresh. This does not compact server history: the existing
4096-record limit remains a known limitation of sufficiently long races.

### Private-card hand audits

The shared pool ledger distinguishes irreversible native reveal observations
from legal card use. Observing a valid authenticated reveal cannot be undone
because the game rejects its associated rule move; neither may that observation
consume a card, alter hand positions or become a public accepted game action.

Mahjong's strict final hand replay retains the accepted moves separately from
its chronological source tape, which also includes those observed-but-refused
reveals. Replay that tape with the ordinary ownership/proof/rule checks and
require the exact same accepted sequence before committing scores. Do not
initialize the audit's known-card ledger with all later revelations: that would
let a later disclosure authorize an earlier unsupported claim. The reducer
shares append-only source snapshots between states, not mutable aliases to a
caller's future event list. Checkpoints retain their positions as described
above. The rejection regression covers cold replay
and identical scores on four account views in Hong Kong, Riichi and MCR.

Commit/reveal games also distinguish safe structural decoding from the final
rule audit. In Battleship, sealing still requires a legal fleet, but a complete
bounded self-reveal of an illegal fleet must reach `honest?` and disqualify its
author; rejecting it at the reveal gate strands verification. This does not
relax participant, phase or nonce gates, accept malformed structures or replace
the native private-pool proof checks. Regression:
`test/games/battleship/illegal_fleet_reveal_test.rb`.

### Tables, participants and the game lifecycle

`game_room_screens.rb`, `game_lifecycle.rb`, `game_participants.rb` and the
lobby and activity repositories handle table creation, joining, bots, game
start, game end and the next game.

Explicit ordinary table creation requests a new native table; it does not
replace that request with a return to an existing visit. The account-wide
catalogue admission, pending-create fence and original-membership recovery
were removed at the maintainer's request on 23 October 2026. A failed request
does not trigger an automatic second create or a background search for a room.
The single-program-window guard remains separate. Saved-game continuation and
tournament entry still check their own retained identities, without adopting an
unrelated room. Tournament creation claims run after local payload validation,
immediately before the native request; this is a per-match journal safeguard,
not a limit on how many ordinary tables an account can create.

A bot has a persistent identifier and a randomly chosen name. Removal targets
the selected bot, not the last item in a numbered list. Team composition refers
to current participants. Permissions, phase and the person's presence are
checked again on confirmation. Ctrl+M transfers the table host role;
Ctrl+Shift+R on the participant list replaces the selected player/bot with a
present human who is not playing, or a new bot if the game permits it. This
is not a swap between two active players.

Leaving a table is a confirmed membership operation, not closing its form.
The first-connection recovery form uses the same guarded Leave action as an
already loaded game. Cancelled or failed departure keeps the current form;
an unrelated return from its wait does not become a return to the lobby.
The native SDK's `Session#leave` and `#close` close locally even when their
RPC fails. Ordinary departure therefore uses the existing native endpoint
RPC first and closes the local Session only after acknowledgement or an
explicit server response confirming absence/closure. An error retains the
exact native visit for retry; cleanup cannot erase a later attachment.
Cleanup of a rejected, provisional invitation join remains explicitly
deferred through the SDK, without treating it as a completed user departure.
This is not account-wide room admission or a one-table-per-user fence.

The lineup of a started game is recorded in the `game_started` event on the
session stack. Later replacements have their own history and epoch; replay
maps actions according to the lineup at the time they were performed. A
human's return does not automatically take the bot's seat away. Merely
covering the window does not mean the participant has left.

### Transport

`GameRoomLiveSessionStore` uses ELTEN 3.0.4's native API. Public session
discovery replaces the database table listing game tables, direct joining of
a discovered session replaces bootstrapping through Signals, and native invitations
replace application-specific invitation tables. Room changes, chat, game
starts and moves go to one stack and share a common order. Closing a session
removes the table from the list without separate record cleanup.

The visible history is still divided into `Wszystko` (All), `Gra` (Game),
`Czat` (Chat) and `Zdarzenia pokoju` (Room events). This division is only a
presentation filter over a single chronological stream; it does not split
the data back into separate stores.

`GameRoomSync::Controller` collects notifications and triggers controlled
state recovery after an error or gap. Failed recovery attempts wait 5, 10,
then at most 15 seconds between attempts; a successful complete recovery
resets this schedule and disables further reads until another event. Repeated
native error notices and the executor observing the same exception must not
postpone an already scheduled read or count as additional failed attempts.
An explicit rate limit or `Retry-After` can extend the wait. Do not replace
this with frequent, periodic server polling. An uncertain write preserves
the move identity and random result for reconciliation; repeated delivery
does not apply it twice. During recovery, the UI preserves the last valid
state and chat draft. A programming error requires diagnostics and stopping
the faulty action. Regressions: `stack_retry_schedule_test.rb` and
`native_stack_page_boundary_test.rb` exercise scheduling and the actual SDK
stack-request rejection without replaying a move.

Axel Pong and Audio Ball share a full-P2P option that is off by default.
Enabling it reveals the next form field: the participant limit, 8 by default;
0 means no limit. `realtime/p2p_options.rb` defines the options and their
validation, and `Channel` passes `p2p: :full` and `p2p_participants_limit` to
the native `create_session`. Disabling it leaves the existing session-creation
arguments in place. Settings come from table options, including on reconnect
and after a table-host change; they are not a local player preference.

The limit covers native Communications participants, including observers,
but not separate bot seats. ELTEN establishes direct connections according
to client privacy settings and network availability; without a P2P path, or
when the limit is exceeded, transport stays on the relay. Game Room does not
change global P2P consent or sender permissions. Full P2P covers both
Communications paths (positions and acknowledged actions); it does not move
chat, membership or durable point recording out of LiveSessions. Relay ping
still measures the server, not latency between players. Local `realtime_p2p_*`
regression tests are not a substitute for a trial across different network
links/NATs.

`GameRoomSessionRunner` is the single runner for an ordinary game in a visible
or covered window. `GameRoomExecutionPolicy` shares pure replacement decisions
and bot-plan preparation with the separate real-time path; it does not merge
their loops. Planning still takes place outside the write lock, and committing
rechecks the session, revision, table host and control epoch.

The background-operation bridge passes data to presenters on the active UI
thread; it never reads the keyboard from the worker. `GameRoomPresentationReplay`
stores an isolated copy of the latest prefix: it preserves all before/after
transitions but does not replay an already prepared final state a second time.
A change of session, epoch, options or prefix forces a full reconstruction.
A board game's `nil` state is a valid value, not an error. A programming error
stops the runner and reaches the UI/log; it does not masquerade as a transient
disconnection or retry moves.

`saved_game_archive.rb` describes the saved-game format and validation.
The file validator and independent incoming native `game_archive` validator
share `GameRoomEventProtocol::ARCHIVE_EVENT_FIELDS`: ID, sequence, actor,
action, value, raw creation time and optional logical `game_time`. Reject
unknown fields before replay; an archive checksum or authenticated room owner
does not grant authority to import native proof/payload metadata. Roster-change
rows retain their separate exact `id`/`players` schema.
`AccountSavedGames` uses only the account's private files and confirms the
write before closing the table. The legacy local adapter is separate, without
automatic fallback. Safeguards for uncertain writes, game time and secrets
still apply.

The optional `SaveGame` intent journal is not connected to the ordinary menu.
Its archive IDs remain UUIDs; native LiveSessions IDs are opaque bounded text,
not UUIDs. Reading an old UUID-based journal remains supported. Supporting an
opaque native ID does not enable conditional close or silently wire this
optional recovery path into the application.

### Bots

`game_bots.rb` defines shared strategy registration and execution. Planning
does not write a move directly: it chooses a legal action that goes through
the same game validation and repository as a human action. Specialized
strategies are in `*_strategy.rb` files; the shared tree search is in
`game_tree_search.rb`.

The coordinator builds an observation only when the strategy's `choose`
signature accepts `observation` or arbitrary keywords. Keep precise keyword
signatures for replay-only consumers that do not need that potentially large
projection. Existing external `**keywords` strategies and the original
four-keyword contract still receive the same observation. This is independent
of `ReplayOnlyStrategy`, which controls simulation, not observation.

Training, the arena, campaigns and strategy comparisons are in
`tools/training/`. The application does not load them. Production policies,
trained profiles and the simulation environment remain in `lib/`.

### Content and languages

`game_content.rb` uses the bundled Unicode normalization implementation and
pinned Unicode 17 tables, independently of the host's Unicode version. Its NFC
and NFD caches retain at most 18,000 entries each, with at most 256 bytes of combined
key/result string payload per entry. Larger matched sequences still normalize
identically, but are not retained. This is a cache-payload bound, not an RSS or
temporary-allocation guarantee. Do not change accepted characters, text limits
or normalization results to repair cache retention. The compatibility test
exercises binary application namespaces/three host versions; the cache-bound
test also checks actual rejected typing-text imports without writing a profile.
Only cold admission is serialized; ordinary Hash hits and normalization itself
do not acquire that lock. Duplicate concurrent misses reuse the admitted value
without evicting an unrelated entry.

`game_content.rb` and `content/languages.rb` handle versioned content packs
and language variants. Interface messages use `_()` and are delivered in
`locale/<LANG>.mo`. English comes from the sources; catalog-selection rules
are described in [INTERFACE_LANGUAGES.md](INTERFACE_LANGUAGES.md).

## Passive history and replay library

On the first application entry, `local_directories.rb` prepares the data and
cache roots in one finite native task. All instances share those roots through
the current application's Runtime, including native JSON storage helpers.
Subpaths retain native validation; no storage-identity or package discovery runs
again during gameplay. The adapter is runtime-local and is discarded on reload.

`lib/recordings` is separate from resumable server archives. A game declares
`recording_audio_kind`; the shared realtime presentation observer copies frames
and renderer calls into bounded immutable background chunks. Snapshot leases
protect exports while a match continues or a new one replaces the capture.
Only an explicit save persists the replay in the account's local library.
The opening-match cue is captured once per recording, not once per request:
the live audio guards later requests at every rally. Playback and navigation
indexes likewise ignore repeated opening requests in a passive timeline, so
creating a new renderer after seeking cannot announce another match start.
The header retains the starting participant names. Each current frame may
contain its own display-name roster for a same-session participant replacement;
an explicit roster is validated against the fixed seat count. Playback readouts,
contextual perspective actions and the native perspective list resolve that
same current frame, including backward and forward seeking. A quiet keyed list
refresh preserves the listening seat and focus and runs only on its active UI
update, not from covered/background Progress. Replacement keeps the capture's
existing timeline and does not record a second match opening.

The versioned JSON document contains passive presentation data, never executable
commands, Ruby objects or authoritative game state. `Prepared.load` validates
the complete document before any playback renderer or sound handles are created.
Validate participant-indexed contacts against the actual recorded roster, not
the maximum game size. Pong's live and passive validators share the pure
`axel_pong/snapshot_effects.rb` contact vocabulary. Both frame-level and scene
team maps must use canonical singles or typed, balanced doubles for that roster;
a doubles Pong scene also
requires its receiver. Passive information and audio-event perspective use the
same `Document.frame_teams` resolution (scene, then frame, then default), not
independent assumptions about alternating seats. Invalid import data is a
controlled `GameRoomRecordings::Invalid`, not an audio-frame rescue/fallback.
Playback reuses the game's
audio renderer with a virtual clock under the existing Progress bridge. Seeking
does not replay historical goals; no session or statistics writer is created.
TXT histories and JSON replays share a directory-authoritative library. Native
message attachments use exact-message checks, a delivery journal, confirmed
sender-copy removal and optional recipient removal after successful import.

## Invariants to preserve

- the LiveSessions stack is the source of truth for the room and game;
- every move is revalidated during replay;
- the client does not record a participant before LiveSessions confirms it;
- the form refreshes only after an actual state change;
- a bot does not bypass the rules or the human write path;
- a shared-framework change requires a test of at least one game from every
  affected family.

## Detailed contracts

- [HOST_API.md](HOST_API.md): adapters for the required final ELTEN 3.0.5 release.
- [UI.md](UI.md) and [CARD_HAND.md](CARD_HAND.md): forms, help and card hands.
- [BACKGROUND_GAME_EXECUTION.md](BACKGROUND_GAME_EXECUTION.md): the runner and background presentation.
- [REALTIME.md](REALTIME.md): Communications authorization, delivery and latency.
- [PRIVATE_STATE.md](PRIVATE_STATE.md): answer commitments and account archives.
- [SNAPSHOT_OWNERSHIP.md](SNAPSHOT_OWNERSHIP.md): ownership of models and data copies.
