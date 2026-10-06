# Instructions for agents working on ELTEN Game Room

## Current contract

- The sources require the final ELTEN 3.0.4 release; the integration contract
  is described in [HOST_API.md](docs/HOST_API.md).
- Maintenance rules: [ARCHITECTURE.md](docs/ARCHITECTURE.md); the index of
  current contracts and instructions: [INDEX.md](docs/INDEX.md).
  Git contains the change history; that history is not an instruction to revert current code.
- LiveSessions is the only backend for tables and moves. Do not restore the
  former tables or Signals. Krowa/lobby/registry/subscription tables are still needed.
- Do not recalculate Daily Krowa from the dictionary's current index or size.
  The first `krowa_daily_assignments` record by server ID fixes the word for
  the day (midnight in Polish time). New words take part in the next draw;
  they do not change the current puzzle. A missing historical assignment
  means the word is unknown, not that its value should be guessed.
  Encryption protects the ordinary view, not against a modified client.
- Preserve both stale-closure guards, participant epochs, immutable history,
  reconciliation of uncertain writes and protection of private phases.
- An ordinary game has one executor, planning outside the write lock,
  revalidation before writing and a presentation bridge on the active UI
  thread. Realtime has a separate loop. Do not add UI/keyboard work to the
  worker or introduce polling.
- Do not restore a second bot scheduler in `GameScreen`: turn-based games
  are executed by `GameRoomSessionRunner`, realtime bots by their own client.
  Tests of bot move writes and acknowledgements must use the active executor.
- Unfreezing after a failed write requires confirmation of that write's own
  boundary, the same game and the current host. Do not unlock a newer write.
  Accepting an invitation and leaving normally share the private-phase
  handover guard and repeat the check immediately before releasing the current table.
- Game order comes from `__stack_sequence`, not a random identifier.
  A remote Pong spectator presents full snapshots, without replaying from
  scratch a history of hits they never received. Sender and epoch checks still apply.
- A programming error is not a disconnection: preserve diagnostics and stop
  retrying the faulty action. Any intentional fallback must be explicit and bounded.
- Presentation caches must not skip events or share mutable models; also
  test `nil` state in board games, participant changes and new sessions.
- Keep training/experiments outside the runtime, in `tools/`. Tests share
  helpers from `test/support/`, not scenarios from other `*_test.rb` files.
- Host tests use a single `ELTEN_HOST_SOURCE`. A missing dependency, skip or
  timeout is not a success. After the first full run, the user requested
  testing only changed cases from then on (25 September). Do not rerun the
  entire runner now. For the subsequent fourteen points, the user approved
  live-client trials and loading code into memory, not installation, a new
  package or publication. Do not extend that permission to other operations.
- Historical quiz applicators were removed along with the one-off audits.
  Do not restore them as compatibility wrappers. Do not repeat question
  filtering or change audio/databases as part of code cleanup.

## Boundaries after the follow-up maintainability audit

- The history validator is pure: it indexes only earlier accepted game
  starts. When ordered records change, it validates history again; do not
  treat a rejected or later start as authorization for a move.
- Inactive-table retention must not remove an active session, an operation
  in progress or an unreconciled write. At callbacks and when publishing
  validation, check session/collection identity under the lock: a repeated
  counter value does not prove that the generation is the same.
- The option editor and shortcut bindings have separate responsibilities.
  Do not add move writes or a second session executor to them. Games declare
  phase rules, local options and sound effects instead of adding another
  list of game IDs to the framework.
- Realtime clients reset their own fields; shared code manages channel
  lifetime, ping and announcement sequencing, not shared physics. Test player
  replacement, a spectator acting as host, stale-channel closure and ping re-registration.
- Strategy simulation is lazy. A new strategy without a declaration still
  receives the previous context; opting out of simulation requires an
  explicit contract. Compare selected actions, their order and subsequent
  RNG state, not just the game result.
- Registry/subscription candidate reads use a bounded table snapshot:
  up to 15 s and 4096 rows, with no query for an empty list. Read the user's
  own settings fresh; invalidate the cache after a write, even if the result
  is uncertain. An error does not mean empty preferences. Do not invent an
  API batch operator or make one request per user; changes by other accounts
  have an explicit delay of up to 15 s.
- Importing test helpers must not execute other tests' scenarios. Binary
  aggregates isolate scenarios, and reports must not count their children
  again as independent additional coverage. Preserve initial failures separately.

## Working practices

- A multi-stage form that writes an auxiliary action first must pass the new
  replay and revision to the rest of that same form's handling. Do not
  remove `StaleView` checks or allow writes from a stale view.
  Regression: `test/games/monopoly/staged_trade_screen_test.rb` (including
  cancellation, reopening, human/bot play and the following turn). Ordinary
  modal choices that do not write an intermediate event need no such handling.
- After participant replacement, the bot analyzes the history projection
  for the current seats through `GameRoomParticipantDecisionEvents`; the
  immutable accepted log and historical messages retain their original
  authors. Test both full and incremental planners and subsequent RNG state.
  Historical presentation caches must account for the whole event prefix,
  options and participants, not just a count or the last ID.
- Do not expand every move candidate merely to find the executor or build
  the screen. Narrowing the presentation list must not narrow bot decisions
  or the set of genuinely legal moves. A membership read error does not
  mean everyone has left; preserve the error rather than returning an empty list.
- Coordinate private answers between instances of the same native Program
  that share a file. Removing a Krowa word must survive replay: associate
  the addition marker with its source event, not an aggregate for the entire session.
- Recheck host transfer and replacement at the write boundary, not just
  before opening the participant selector: a bot or human may confirm a
  private choice while the dialog is open. Replacement distinguishes the
  specific person from other people's pending secrets; do not remove
  protection for all private phases. Shortcuts summarizing earlier tricks
  or battles use historical messages, not the current participants' names.
  Games with simultaneous decisions declare `required_decision_key` instead
  of bypassing settings with their own `ding`.

Application windows use `GameRoomUI::Form` or
`GameSurfaces::RefreshAwareForm` with a `program:` reference. The shared
framework provides local F1 help as read-only text, plus F2/F3 and
Shift+F2/F3 for volume. History uses GameRoomHistory::View, with navigation
bound by GameRoomHistory.bind; index/check are character positions,
entry_index identifies an entry. Do not duplicate these keys in game
classes or change ELTEN's sources or saved QuickActions. Update dynamic
game and room help through the same definitions as the actual shortcuts
(`GameRoomContextHelp`), not hard-coded phase-dependent tips.
Details: `docs/UI.md`.

- First reproduce the problem and identify the layer responsible for it.
- A model progressing behind Messages/a forum does NOT prove that speech
  or audio is being delivered. GameRoomBackgroundPresentation presents a
  covered game on the active UI thread, in the correct application's
  runtime; the worker only publishes copied data. Do not update the game
  form or keyboard from this path. Preserve shared event/chat cursors,
  the sound queue, non-interrupting speech and deduplication after returning
  or starting a rematch. Session IDs are random, not monotonic. Clean up
  registrations on close; the host bridge must survive reloads without
  retaining closures from the old application or accumulating instances.
  A live test must confirm speech output AND working audio while still
  behind the native window, not just compare states after returning.
  Regressions: game_background_presentation_test and game_background_native_input_test;
  details in docs/BACKGROUND_GAME_EXECUTION.md.
- Turn-based games run automatic policies and bots through the shared
  GameRoomSessionRunner with both visible and covered forms. Do not add
  another automatic-action loop in a game class or GameScreen. Models and
  policies must not call UI, speech or loop_update, or read controls.
  Planning runs outside the write lock; supply ready callbacks and check
  the current session/revision before writing. Do not let planning block
  UNO interception, Makao or chat. Preserve custom constructors in
  build_session_game, identify drafts with automatic_surface_identity,
  and narrow concurrent-input exceptions through concurrent_session_input?
  to one round/phase/operation. Rules are still checked by action_for.
  Do not move the whole GameScreen or game_client into Thread.new.
  Realtime runs its own physics and bots in a single clock-driven timer
  on the active UI, including behind another window. SessionRunner only
  writes agreed points through the standard rules; it does not run physics
  or input. Menus and covering windows neutralize keys but do not stop
  synchronization. When changing this, test multiple instances,
  backoff/uncertain writes, returning, deadlines, freeze/rematches and completion.
  Tests: game_session_runner*_test.rb and game_session_screen_test.rb.
- Open the leave-table confirmation before `GameScreen#run` ends.
  Keep the executor, realtime client and presentation alive until leaving
  succeeds; No, Escape or a failed operation must not recreate them from
  scratch. Continue to use the shared leave guard and revalidate it after
  the dialog. A confirmed departure returns `:left_table`, without a second
  question in the lobby; server-side closure asks no question.
  Regression: `game_leave_confirmation_test.rb`.
- Launching over Conference may put Game Room on a parallel UI thread.
  Final ELTEN 3.0.4 delivers callbacks for the active scene in its own loop;
  do not add a second dispatch in the form. Application windows still use
  the shared Form with `program:` to manage discovery/retention and launches.
  Preserve the separate drain for a covered game's executor and the drain
  before writing. Do not replace these boundaries with a global tick or
  server polling. Test main and parallel launches, returning from another
  window, bots, rematches, and preservation of chat drafts and focus.
  Regressions: test/host/parallel_scene_events_test.rb and parallel_scene_native_test.rb;
  `ELTEN_HOST_SOURCE` must point to sources matching the host under test.
- An extension attached to a global host object survives application
  updates without restarting ELTEN. An “already installed” marker must not
  retain a closure with the old application namespace or data format.
  When changing such extensions, test old package -> new package in one
  process, repeated reloads, no accumulating wrappers and no replay of
  stale input. A clean start or binary load alone does not test this.
  Audio Ball regression: `test/games/audio_ball/keyboard_reload_test.rb`.
- `Replay#state` is optional: Tic-tac-toe and Four in a row keep the position
  in `board`/`players` fields and return `state: nil`. Shared hooks must
  not require a state Hash; game options also come from ActionContext.
  When changing them, test real replays from game classes, not just an
  artificially constructed Hash. Bot-delay regression:
  `test/models/bot_delay_replay_test.rb`.
- Check UI text encoding in the package too: ELTEN may load sources as
  ASCII-8BIT, and a missing `_()` translation leaves the text unchanged.
  Even an English label with an em dash “—”, multiplication sign “×” or
  another non-ASCII character can then cause Encoding::CompatibilityError
  when a control appends a Polish/Russian role or state description.
  Normalize text and labels passed to controls, and messages assembled
  from parts, to UTF-8 with `GameRoomContent.utf8` before concatenation or
  formatting. Do not change IDs, option values or binary data, override
  global gettext or ELTEN controls, or hide the problem by stripping
  diacritics. The shared framework normalizes `OptionDefinition` and
  `OptionChoice` labels; new settings must use it. Tests must exercise
  actual form construction and focus/state announcements, including a
  missing Game Room translation alongside a translated host. Do not force
  UTF-8 in `_()` or control stubs when the host does not — that hides
  regressions. Use `test/localization/game_option_encoding_test.rb`
  (binary sources; EN, PL and English text with a Russian host), and on the
  next packaging run also pass the finished package's path as an argument.
  A normal `require` or PL-only test is not enough to establish compatibility.
- Shuffling must be compatible with ELTEN: the host overrides `Array#shuffle`
  and `shuffle!` with methods that accept no arguments. Do not use them in
  game or planner code, especially `shuffle(random: ...)`. For new calls,
  use `GameRoomRandom.shuffle(values, random: Random.new(seed))`, passing
  the shared seed recorded in the event, not a new random seed during replay.
  Preserve existing deterministic helpers (`CardGame#shuffled_cards`,
  `GameRoomDominoTiles.shuffle`, planner helpers) and their seed conversion;
  do not migrate older games incidentally if that would change saved games.
  Do not fix compatibility by removing the random argument, using `srand`
  or global `rand`, or changing Array in a running ELTEN. Test with
  `test/support/elten_array_shuffle.rb`, checking the deal, reshuffling or
  exchange, replay and the next use of the same RNG. A test on ordinary
  Ruby outside the host is not sufficient. During packaging, also run a
  binary load with this API simulation; distinguish source and package tests.
- Make small, coherent fixes and add a targeted regression test.
- Use ELTEN's new event-driven API. Do not write manual UI loops.
- Extend the shared framework when behavior is common to a family of games;
  do not copy the same handling into several game classes.
- Do not move game rules into `GameScreen` or UI details into transport.
- Do not bypass `action_for`, `GameRepository` or event replay.
- New card games must use the shared hand handling rather than copy cursor
  logic: stable unique card IDs, `hand_order` in actual draw order, and
  `hand_epoch` identifying the owner and deal. Details are in
  `docs/CARD_HAND.md`. Do not mark other lists, boards or dice as card hands;
  this mechanism must not change their behavior or announcements.
- A new game with an actual card hand implements `playable_card_navigation`
  and groups all legal actions by the physical card's stable ID. The shared
  framework provides `Z` and `Shift+Z`. Mark a move as automatic only when
  the card needs no further choice, declaration, meld or packet.
- Manual hand sorting exposes `hand_sorting_available?` and the shared
  `hand_sort_shortcuts`. Cards provide semantic `sort_keys` for
  colour/number/none, never translated labels as keys. Do not change the
  default layout merely by adding this capability. View sorting does not
  sort game state, packets or meld-selection order; CardTable/PacketCardSurface
  controls preserve physical IDs and the cursor. Check shortcut conflicts
  and whether the screen actually contains a hand.
- Expose permanent elimination through `eliminated_from_game?`, separately
  from round end, passing, disconnection and all-in. The shared sound
  selector detects the transition into that state and respects the final
  result/draw. Do not replay the defeat effect at game end or during replay.
- Independent consequences of one move may have simultaneous audio effects.
  Collect them independently, not through mutually exclusive if/elsif
  branches; preserve event deduplication, move acceptance and game volume.
- Translate non-ASCII rule text through the local `GameRoomRules.translate`:
  the host dictionary may store binary MO keys. A translation's existence
  and a UTF-8 result do not prove that the key matched. Test with the actual
  dictionary or a faithful binary stub.
- A bot chooses an action but executes it through the standard game path.
- The LiveSessions stack synchronizes table and game state. Discover public
  tables through discovery and join them directly; do not restore bootstrap
  or synchronization through Signals.
- Avoid periodic polling and full form rebuilds. Updates must not move
  focus or cause unnecessary announcements or sounds.

## Realtime games — latency and Communications

- A spoken announcement is not confirmation of network readiness. In Pong,
  do not make serving depend on any player's final speech index or add
  another pause after it: use the ordinary deadline, as in singles.
  A stub that supplies the final index itself does not test the reliability
  of a real synthesizer. Also account for a completely missing index,
  interrupted speech and different speech outputs. See `docs/REALTIME.md`.
- Use the shared `Channel`/`EventChannel`. Before implementation, map the
  entire action path: input, queue, relay, receipt, application and
  presentation. Establish who is authorized to decide each event.
- Optional P2P in Pong/Audio Ball uses native `p2p: :full` and
  `p2p_participants_limit`, not custom sockets or another intermediary.
  Preserve relay when disabled, the setting after reconnect/host transfer,
  and a limit that includes spectators (default 8, 0 for unlimited).
  Do not change ELTEN's global P2P consent. `routing: :peers` does not mean
  physical P2P, and relay ping does not measure the direct connection.
  Regressions: `realtime_p2p_*`.
- Ctrl+F4 distinguishes HTTP measurements, UDP to the relay server and RTT
  to individual P2P participants. Read the route from native
  `Session#p2p_status`, not table options; after P2P expires, do not report
  stale RTT as current. Describe mixed connections separately. Reading
  the status must not send extra probes or start connections or callbacks.
  Regressions: `test/realtime/ping_p2p_test.rb`, `test/localization/ping_p2p_dictionary_test.rb`.
- A host coordinating the match, including a spectator host, need not relay
  every message. For actions decided by an authorized sender, use relay
  delivery without an extra hop through the host. A model requiring host
  approval needs justification and measurements; do not automatically
  switch all games to `routing: :peers`.
- Do not wait for the network or disk in a UI frame. Send a ready action
  immediately in the background, without waiting for a periodic packet
  or the next frame. Replaceable positions may retain only the newest
  value; important actions must not be dropped.
- Preserve sender authentication, match/generation IDs, ordering,
  deduplication, bounded queues and full acknowledgements from required
  participants. A temporarily absent recipient does not disappear from
  delivery requirements. A new game gets a new client; stale tasks and
  repeated invitations must not affect the new connection. Recovery must
  work without the player pressing Enter.
- LiveSessions stores durable table state and results; do not make every
  movement or safe local presentation depend on a durable write. Do not
  improve speed at the expense of scoring permissions or consistent decisions.
- Measure HTTP, relay RTT, queue/UI time, action application and durable
  writes separately; do not subtract raw clocks from different computers.
  Test humans and bots, different seats, a spectator host, rematches,
  loss/duplication/ordering, background operation and reconnects.
  Four copies on one computer are no substitute for different connections.
  Do not mask transport problems by changing physics, or call unexplained
  stalls fixed.

Delivery contract and measurement rules: `docs/REALTIME.md`.

## Verification

- Optional startup updates: only on a cold entry, after acquiring the
  single-instance lock and before joining a table. Compare build numbers
  (not just version differences); do not downgrade a test build. Declining,
  errors and catalogue timeouts must not block startup. ELTEN's native
  installer must run only after the old Program has finalized, outside
  its runtime. Preserve the entry destination and block further launches
  during the download; after reload, resolve the class by UUID, never
  through the old class object. Test every entry path, decline/cancel/failure
  and return after installation. Do not update an active game or the public
  catalogue during tests.

Shared table features are described in `docs/ARCHITECTURE.md`, `docs/UI.md`
and `docs/PRIVATE_STATE.md`:

- The Ctrl+R variant/settings announcement comes from
  `table_options_announcement` and the same definitions as the settings
  document. Do not maintain a second list of rules.
- A board game's S counter is implemented through
  `remaining_piece_counts(replay)` in player order; count the actual board,
  not the score or initial state. Do not bind letter-key game shortcuts
  to editable chat.
- Privacy is a shared table-creation option, not a setting in every game.
  Do not publish private activity. A private notification's validity must
  come from the server invitation, not an application-assumed deadline.
- Saving uses the standard replay and `saved_game_schema_version`.
  A new game defines `save_game_error` for unsafe phases or disables saving
  through `supports_saved_games?`. If event values contain controller names,
  implement `restored_event_value` for those specific fields. Do not replace
  players or close the table before the account archive write is confirmed.

- Run targeted tests during development.
- Before a pull request, run `ruby test/run.rb`.
- Transport changes require `live_sessions_*`, `test/transport/transport_test.rb`,
  `test/transport/game_sync_test.rb` and a multi-client scenario.
- Shared-surface changes require a test of the surface itself and at least
  one affected game.
- Do not change the release number or sign a package without the maintainer's
  explicit instruction.

## Data that must not be committed

Do not store MCP tokens, keys, certificates, ELTEN profiles, logs containing
private data, server credentials or signed `.eltsetup` packages.

Keep reports, audits, test results and summaries of local changes in the
local, Git-ignored `tmp/` directory. Do not add them to tracked repository
files unless they are necessary for maintenance or the user explicitly
requests it.

## Audio assets

The default format for every new effect, voice, loop and music track is
Ogg Opus `.opus`, 144 kb/s VBR, 48 kHz, 20 ms frames, libopus audio,
complexity 10. Preserve mono/stereo, metadata and levels; do not normalize,
trim or repeatedly transcode files that already comply.
Use `tools/encode_audio.rb` and keep the original outside the package.
Renaming a file is not conversion. Packaging rejects other formats and
invalid Opus headers but does not re-encode; sound IDs remain extensionless.
`tools/generate-pong-echo.rb` also produces Opus from deterministic PCM.
Procedure: `docs/BUILDING.md`. Preserve licensing and attribution.

## Contracts added after build 239

- One UI instance per process: `GameRoomSingleInstance` switches the native
  thread rather than running `main` again. The widget alone is not the
  owner. A rejected launch must not close the shared sound pool. Specific
  actions wait for a form boundary and do not interrupt modal dialogs.
  ELTEN may leave the completed thread of a redirected launch in its
  Windows list. Remove only our own marked, already completed threads,
  on the active UI after switching, including in a modal form. Do not kill
  threads or clean up other applications' windows. Test the native launch
  lifecycle, not just the value returned by the lock
  (`test/host/single_instance_native_test.rb`). A cold widget entry (table,
  creation, preset, Ctrl+J) schedules a new program scene through native
  `insert_scene`; do not open a long-lived form inside a Scene_Main callback
  or on the shared widget object. Core must set the scene context and
  finalize its lifecycle. Regression: `test/room/widget_scene_navigation_test.rb`
  — including another window and return.
- `DiscoveredSession` is tied to the connection that discovered the table.
  A row passed by the widget or a notification must not lend that connection
  to the new game window: joining resolves the ID in its own LiveSessions
  store, whose callbacks are handled by the game executor. Invalidate
  discovered objects after an endpoint change. Test public and private
  tables and a move behind another window after a cold widget entry,
  not navigation and synchronization only in isolation.
  Regression: `test/transport/live_sessions_discovery_owner_test.rb`.
- Statistics: UI/replay callbacks only queue copied data in bounded memory;
  atomic writes and networking belong to the worker. A telemetry failure
  must not interrupt gameplay. Do not ignore conflicts other than a
  difference solely in the date of a repeated result for the same game.
  Retention removes only the account's own expired presence reports,
  never historical statistics.
- Statistics wake a managed worker on events, not empty polling every
  30 seconds. `GameRoomAnalyticsStorage` resolves native `data_path` once
  per runtime, in the background; do not return to repeated host package
  parsing through read_json/update_json. Preserve atomic writes, the file
  lock, account isolation and rejection of corrupted JSON. Retry only the
  backlog: 30/60/120/300 s, without new entries bypassing backoff. Presence:
  participant/state changes plus a heartbeat 120 s after success, not
  moves/chat/points. Readers cover the current minute and five preceding
  minutes; publication cleans up at most 64 of the account's own older rows
  per 15 min. Developer mode still disables statistics. Smoothness tests
  must explicitly enable isolated statistics or they do not test this path.
  Details: docs/STATISTICS.md.
- Statistics send at most 25 entries per batch and yield the worker after
  exceeding a soft budget between batches. Acknowledge only the returned,
  validated prefix; a lost response does not remove deduplication or
  account/cancellation checks. Honor a longer server `retry_after` deadline.
  Date a cold visit only using confirmed time, retaining the moment of
  entry. Do not skip a presence correction after an uncertain write, even
  if the state has returned to its previous value. Report cache: 15 s/4096,
  a fresh schema on every read; explicit Refresh and a write attempt
  invalidate the snapshot. Regressions: `statistics_audit_regressions_test.rb`,
  `game_room_analytics_client_test.rb`.
- Statistics and presence reads do not stop at a short page. The server
  may return 1000 records despite a schema limit of 2000, or fewer still.
  Request at most 1000 (or the table's lower limit), advance the offset/ID
  by the records actually received and stop only on an empty response or
  a confirmed snapshot boundary. Preserve deduplication, canonical dates,
  progress and cancellation checks; a later-page failure is not partial
  success. Test servers must be able to shorten pages independently of
  the schema. Regressions: `statistics_pagination_test.rb`,
  `room_presence_store_test.rb` and `game_room_analytics_client_test.rb`.
  Do not “fix” counts by inventing starts or capping completions at starts.
- Board presentation is local. Save only explicitly allowed flags, and
  orientation relative to the player's seat; do not save cursors or drafts.
  New Ludo tables use `enter_on_one: true`; old events without that option
  still follow the former rules. Do not change the meaning of old rolls.
- Ctrl+M and Ctrl+Shift+R act on the selected person in the participant
  list, not the game field. Help checks current availability, and execution
  rechecks permissions and identity, not just the row index.

## Quiz question editing

Before creating, importing, expanding, correcting or translating a set,
read the [quiz editorial guidelines](docs/QUIZ_EDITORIAL.md) in full and
apply them to EVERY new or changed question, including those from existing
datasets or PRs. They apply in every language. Check the source, an
unambiguous answer, natural wording, three plausible wrong answers and
semantic duplicates. Perform a separate language review of the entire
batch; sampling and passing format tests do not replace editorial review.
Do not add unresolved items to an active set. Preserve explicit user
restrictions on sources and text changes; do not rewrite other sets
incidentally. For a new language, apply the shared rules and add verified
language-specific guidance to that document.

## Readable quiz question copies

- After any change to questions, answers or divisions, or adding a set,
  run `ruby tools/export-quiz-text.rb` and include the updated
  `docs/quiz-questions/*.txt` files.
- Readable files contain a sequential number on its own line before each
  question (starting at 1 in every set), the question, A–D choices and the
  correct answer, **without technical question identifiers**. Do not edit
  them manually: the sets in `content/` are the source of truth. The only
  current Witcher set is `quiz.witcher.books.pl` (books); do not restore
  removed game or screen-adaptation sets. Verify questions in the books,
  not in adaptations.
- `ruby tools/export-quiz-text.rb --check` and
  `test/games/quiz/text_export_test.rb` detect stale copies. For a new set,
  also check that it appears in the export. Do not include TXT files or the
  export tool in the game installer.

## Packaging runtime content

- Realtime progress under menus and behind another scene uses a single
  clock, `GameRoomRealtime::Progress`; do not add a second physics loop in
  a worker. A hidden field has neutral input, not an intentional pause.
  The ordinary executor writes agreed points. A Pong point proposal must
  match the current rally even before the validator is called.
- The Scrabble preview client implements the full GameScreen client
  contract, not just message reception. Test its actual start/loop/close
  lifecycle. The draft contains only placed tiles, not the rest of the rack
  or a private choice.

Translations have one `locale/<LANG>.po` and a generated `locale/<LANG>.mo`
per language, plus a shared POT. Do not recreate the old JSON fragments or
their export manifest. PO is also the translation source for Polish rules
and the application's changelog. Changelog entries are in
`lib/game_room_changelog.rb`; do not maintain separate Markdown copies.
Preserve the flat MO paths required by ELTEN's runtime.
`test/tooling/locale_build_contract_test.rb` checks both manifests, staging
and native builders using unsigned fixtures, not a game release.
The source manifest in `__app.rb` keeps LF line endings.

Never pass the entire repository to ELTEN's recursive packager. First
prepare a separate directory with `tools/stage-release.rb`. The shared
allowlist includes production code, game data, recordings, compiled MO,
manifests, the root README.md and its content/readme/{EN,CS,ES,RU}.md
translations, licenses and source notices. README is a resource read from
the main menu (after Settings, before What's new), selected by interface
language. Keep one copy of each language's content in the repository and
installer; do not generate a second copy in Ruby. Tests, tools, docs,
AGENTS/CONTRIBUTING/CHANGELOG.md, source translation catalogues, import
reports and editorial materials stay in the repository, not the installer.
Rules and the application's changelog are in the prepared code/translations.
Add any unusual new runtime asset explicitly to packaging rules, with a
targeted test; do not fix a missing file by copying the whole repository.
Before release, check the exact file set, dependencies, required sounds,
byte-for-byte agreement with the snapshot, the signature, and binary loading
of games/content/PL/EN. Run tests from the source directory against the
finished package. Missing tests in a package are expected; a missing
production file must never be masked by loading its on-disk counterpart.
Preserve the short staging-path guard on Windows, and do not release an
archive containing only the manifest.

### Technical documentation and player-facing translations

Maintain technical and contributor documentation in English in the existing
files, without parallel Polish copies. Player-facing README files, rules
and other localized materials remain multilingual.

When changing features, shortcuts, settings, menu paths, rules or limitations,
check and update the relevant README sections in EVERY supported language
without waiting for a user reminder. The Polish version is README.md; the
others are in content/readme/<LANG>.md. These are complete translations,
not shortened descriptions. Preserve the author's manual edits and removed
passages. Do not reintroduce removed text while updating translations.
Adding an interface language also requires a complete README, document
selection wiring, an explicit installer resource list and extended tests.

In README, rules and other documentation, maintain correct Markdown,
heading hierarchy and order, paragraphs, lists, spacing, working links and
tables of contents. Do not flatten the content into one continuous block.
Rules retain their JSON source and native ELTEN headings — do not put raw
Markdown into ordinary paragraphs when the view does not interpret it.
Check the document in use, not just as a file: reading in the native
control, heading navigation, Enter in the contents and Escape to return,
including binary-loaded sources and Polish and other Unicode characters.
The README language-coverage test must detect a new manifest language
without a document; an English fallback alone does not mean a translation
is complete.
