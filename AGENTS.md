# Instructions for agents working on ELTEN Game Room

## Starting a contribution

Read [CONTRIBUTING.md](CONTRIBUTING.md), then use its task routes and the
[documentation index](docs/INDEX.md) to find the existing owner. For new games,
read [ADDING_A_GAME.md](docs/ADDING_A_GAME.md) and
[GAME_ACCEPTANCE.md](docs/GAME_ACCEPTANCE.md). For other new features, follow
the [application-feature workflow](CONTRIBUTING.md#adding-or-changing-an-application-feature);
the same requirements for complete interactions, dependent tests, bounded
cost and documentation apply outside game models too.

Use the [change-to-test map](docs/TESTING.md#select-checks-from-the-change)
as a starting point, not exhaustive coverage. Test real consumers when a shared
contract changes. The tested reference game and modal example demonstrate
existing mechanisms; they do not authorize a new framework or copying every
capability into every feature.

The question and rulebook editorial templates below are mandatory, not optional
style suggestions. Apply their process and separate full language review, but
write natural target-language prose rather than mechanically filling their
outline. Technical validation cannot establish natural wording. Keep the
existing creator-text protection and source restrictions intact.

## Current contract

- The sources require the final ELTEN 3.0.5 release; the integration contract
  is described in [HOST_API.md](docs/HOST_API.md).
- Use the required host API directly. Do not add fallback paths for older
  ELTEN APIs or earlier notification formats unless explicitly requested.
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
- New games use one production rule reducer. Complete-round and bot tests must
  drive that reducer, not a parallel Round/Match model unused by the table.
  Private trick/discard audits must actually gate scoring; native ownership
  evidence alone does not prove follow-suit or legal discard choices.
- `participant_scores` exposes player-visible units, even when internal scores
  use half-points. Read the user list, score shortcut and final result together.
  Validate sound cues, language, quiet refresh and selection retention alongside
  legal moves; successful startup is not an acceptance test.
- A valid native card reveal remains evidence even if its associated rule
  move is refused. A strict hand audit must replay that evidence in its original
  chronology separately from accepted moves, and reproduce the exact accepted
  sequence, not merely its length. Never seed a whole round with knowledge
  learned only at the end or turn a rejected observation into an accepted move.
  Transactional tile reducers must retain the authenticated disclosure before
  copying the candidate model: the server cannot undo it after a rule refusal.
  Retry that known tile with a claim, not a second native reveal. The refused
  rule move must still leave the hand, turn and accepted history unchanged.
- Reducer checkpoints must keep canonical authenticated event identity, including
  private audit tapes. Cache positions and restore them from the current verified
  input on both append and warm-return paths; copied event Hashes are not a safe
  substitute. Bound the full private context/prepared input as well as the model,
  and publish/drop related cache fields together. See `docs/ARCHITECTURE.md` and
  `test/games/mahjong/private_replay_cache_test.rb` for historical/raw/native,
  concurrent admission and refusal regressions.
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
- A lazy details cache belongs to the contents currently displayed, not the
  last successful selection. Failure/hidden placeholders invalidate that
  success; test A loaded -> B failed/hidden -> A, retrying B, and unchanged
  successful selection/cursor reuse. Never leave A's private contents under B.
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
  Before ingesting a blocking native stack page, validate its session, ordered
  positions/trim gap, cursor, through and Boolean completion. A malformed page
  must raise the existing transient read error, not publish a partial success
  or advance past unseen entries. Detached adapters use the same page contract.
- Inactive-table retention must not remove an active session, an operation
  in progress or an unreconciled write. At callbacks and when publishing
  validation, check session/collection identity under the lock: a repeated
  counter value does not prove that the generation is the same.
  A `RoomState` belongs to an immutable native resource ID, not just the
  application table number. Rejoining that same native ID preserves history
  and unresolved work; a different resource cannot reuse the retained alias,
  even when inactive. Native session IDs are opaque, not application UUIDs.
  Refuse that collision before native join/accept when possible; never clear
  pending data or swap a state while numeric IO/subscription leases exist.
  Row-bound snapshot/join and lobby admission must check `__live_session_id`.
- Successive rematches must not retain every previous game's move/archive
  payload in local records, receipt indexes or projection caches after a
  confirmed native trim. Compact only below the cached authenticated floor,
  with a later accepted start and complete authority ledger; keep current
  imports, chat, room/control/start/boundary records and all unresolved or
  unconsumed recovery evidence. Publish the collection, indexes and caches
  atomically against exact source/generation/native identity. Late callbacks
  must not resurrect retired payloads. A retired snapshot fails closed, never
  as an empty old game; the screen uses its existing complete session switch.
  Accepted start markers reserve IDs even after their archive is compacted.
- Exponential schedules derived from timestamps or event counters need an
  economic/work bound before exponentiation, not a rescue after allocation.
  Poker preserves every achievable nominal blind exactly, then bounds powers
  above the immutable chip pool where every possible stack is already all-in.
  Test accepted ordinary/private deal transitions, chip conservation and cold
  replay; a safe baseline guard must intercept huge powers before computing them.
- Cache entry counts do not bound variable-sized text payloads. Bound owned
  key/value bytes as well, including inputs rejected after normalization.
  Serialize competing admissions when promising an exact count; keep ordinary
  hits and expensive pure computation outside that admission lock.
- The option editor and shortcut bindings have separate responsibilities.
  Do not add move writes or a second session executor to them. Games declare
  phase rules, local options and sound effects instead of adding another
  list of game IDs to the framework.
- Option definitions, not `default_options` keys, describe the settings schema.
  Games may omit default values from their canonical storage. Use
  `GameRoomOptionValues` to read, validate and display declared values; preserve
  explicit false/zero and language-dependent choices. Do not expand stored
  tournament settings or change match hashes to repair a settings document.
  The editor must retain game-normalized non-control metadata, such as pool
  versions and team seats. Recompute derived content-pack identity from the
  selected language/set; do not merge arbitrary unnormalized input.
- Use `game_start_options(..., fixed: true)` when checking or starting an
  already bound tournament match. Its published options and identity must
  not be upgraded through `new_game_options`; ordinary starts still use
  the current new-game defaults.
  New tournament drafts are different: initialize them through
  `new_game_options(table_creation_options({}))`, then prepare the selected
  options once more before first publication, after variant changes/Back.
  Editing an existing publication is not a new draft. Publication validation
  admits game-owned non-control markers using prototypes generated from
  already validated controls only; never feed raw metadata back to a permissive
  normalizer to discover its own allowed keys. Preserve semantic validation,
  strict declared types and the existing byte/node limits.
- Bound tournament tables keep their published game settings and team seats.
  Filter settings/team edits from the shared menu and dynamic help, recheck
  retained callbacks and direct editors, and refuse the fresh native write
  when the table or session has a tournament marker. Keep read-only inspection
  and personal settings available; never weaken the match binding instead.
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
  The owned-worker cleanup regression has two explicit test-subject imports,
  not shared fixtures: it exercises the actual guarded parent methods.
  Keep its exact isolation-check allowlist and definition-only import regression;
  do not permit arbitrary guarded test imports or automatic scenario execution.
  Owned-process cleanup scopes capture their own body's failure explicitly;
  an unrelated caller's ambient `$!` is not proof that this body failed.

## Working practices

- Local data/cache roots are prepared once in a finite startup task and shared
  by the current Power Games Runtime. Do not resolve host storage identity from
  an audio frame or recording chunk: it can decode the entire signed package.
  Preserve native subpath validation and isolate the adapter from other apps;
  a reload must prepare fresh roots rather than reuse the former Runtime.

- Application sounds use ELTEN's default effect buffering; do not force
  `:low_latency`, which caused HRTF underruns. Preserve explicitly supplied
  buffering and sample choices. Do not change
  ELTEN's global mixer, add artificial effects to ordinary stereo or infer
  end-to-end latency from the queue size. Notification keys include the
  authenticated sender, recipient and exact event scope. Native lifecycle
  checks use existing local evidence only: missing verification or a cold
  clock is not proof of expiry. Keep the original invitation deadlines.
  A later validation may cross the expiry boundary: check optional parsed
  notice data again before indexing it, even after an earlier visible? check.
  Tournament match invitations bypass contact/blacklist filters, not sender
  authentication, quiet mode or sound settings. Start/final information has
  no expiry; per-publication journals preserve previous attempted sends.
  Final notice snapshots carry the recipient's place and winning unit names.
  Notice refresh is driven by verified tournament changes, not timer polling.
  Partnership notification shortcuts share the menu's current-phase dispatch:
  confirmed/drawn team information after start opens participants, not a partner
  editor whose mutations are already prohibited by the service.
  Hide resolved notices locally without dropping their native lifecycle entry
  before the host has revoked the server notification.

- Tournament result policies v6 and later use explicit game-owned small-point support;
  the base policy is disabled. Keep finishing places separate from numeric
  small-point exports, and preserve all earlier policies when verifying old
  receipts. A team is one unit. Do not turn missing scores into zeros.
  Small-score keys must match result unit IDs, not each teammate's name; count
  a repeated team total once. For games resetting their scoreboard each set,
  derive match totals from accepted public events, without changing the normal
  player display or personal statistics. Verify full singles/team results, not
  only an isolated score dictionary.
  Shared end-of-game feedback also uses game-owned `bot_reward`: when the
  winner is a team ID, resolve the viewer's team before choosing a win/loss cue.
  Cover both teams, spectators and silent cold reconstruction; do not compare
  a team result ID directly with an account name or change the match result.
  v7 adds game-owned placement hooks for newly bound matches only. Keep v1-v6
  exports unchanged, including unfinished old bindings; never migrate them
  silently or enable numeric small points merely to distinguish finishing places.
  v8 adds `tournament_winning_units_result` for complete public winning units;
  its default delegates to the existing placement hook. Tile games opt in
  through their shared family. Preserve v1-v7 receipt verification; changing
  the current default must not rewrite an already bound match's policy.
- Validate a tournament's actual roster with the existing shared planner/capacity
  policy before committing Start; a legal advertised maximum does not prove every
  smaller group roster is plannable. Keep the original registration chronology,
  reject before preparing the Start amendment, and preserve the normal strict
  schedule/entry gates. The automatic direct-final exception is exactly two
  competing units, never three. No additional polling or table reads are needed.
  Known roster/group refusals must explain that configuration using the existing
  localized message, never masquerade as a connection failure.
  Public setup/publication/Start share `ServerCapacity.supported_player_counts`:
  public registration assembles fixed pairs, not larger teams. Preserve generic
  game capabilities and the separate local larger-team planner; reject an
  unsupported public size before a publication intent or write is prepared.
  A new journal operation kind must also render in Operations, including its
  confirmed-but-not-applied notice; do not hide its record or change its durable
  status to avoid an unsupported UI case. Test real service-produced records in
  the native list/details controls, not only an isolated label helper.
  A verified coordination observation replaces its old scheduled wake, including
  after cancellation or removal of a future start. Failed or unauthorized reads
  must retain the previous timer and the existing bounded retry job.
- New organizer settlements use v3 receipts and complete place groups outside
  active play only. A waiting table is not a start; unavailable native history
  is not proof of an unstarted match. All-zero is a resolved fixture, not a
  draw, and advances nobody from its knockout pairing. Preserve empty bracket
  positions and the original automatic cumulative 300-second absence boundary.
  Historical receipt builders used only by tests belong in explicit test
  support, extended only onto fixture instances. Keep the actual old receipt
  readers/validators and the active v3 writer unchanged; do not restore an
  unused production writer merely to construct a historical test document.
  A composed knockout series progress view uses the same bounded copy budget
  as its series plan, not the smaller generic publication default. Exercise
  the actual maximum roster with legal long account names and scored results;
  testing only short fixture names misses the combined-output byte boundary.
- Table voice uses native Conference channels, not voice calls. The shared
  Program entry point must be public to GameScreen. Claims, publication and
  reset use ordered authenticated room records; record native host handover
  through the existing control ledger before a new owner's reset. Passwords
  belong only to the member projection, never activity or discovery.
  Native Conference creation already joins its creator. Observe its new channel
  update before publishing a ready invitation; never issue a redundant join
  while the local channel cache is stale. Release the previous native membership
  before creation, and clear an unconfirmed creation claim without announcing it.
  Creation already owns native membership even when its update is delayed.
  On cancellation or unconfirmed/rejected publication, remove the observer and
  leave only the created ID+name under the same account. If the cached view is
  still delayed or leave fails, retain that exact local identity for ordinary
  table departure; never guess a channel or leave a foreign reused ID.
  A ready response alone is not confirmation: require accepted publication and
  the exact created channel/name/creator before retaining it as published.
  The creator's Disconnect leaves only that conference and clears the exact
  table invitation head; it must not leave an unrelated native conference.
  A connected guest also gets Disconnect, but leaves locally without clearing
  the table invitation. Resolve this button's label from the current native
  membership when read/focused; local joins/leaves need no table/game refresh.
  Retain a matching local target while still connected after its creator clears
  the invitation, so remaining guests can leave without altering a newer offer.
  Explicit departure while connected to the table's conference offers No,
  Yes and Leave only the table. The last choice preserves Conference and only
  drops local table tracking after confirmed departure. Do not apply this choice
  to an unrelated channel or consume it on cancellation or a failed leave.
- The shared replay cache owns sealed authenticated records and copied
  checkpoints. Recheck actors and IDs, all earlier changed records, resource
  identities and session context; retain bounded memory and generation guards.
  Never let a shorter historical view evict the latest checkpoint.
  Game adapters omit only the transport-only `__game_revision` from the copied
  reducer input, not from the real session/write CAS. Retain a bounded previous
  `Input` for opt-in native immutable-log authentication reuse; mutable rows or
  a changed authority generation still need revalidation.
- The default paced bot delay is one second; retain explicit choices and do
  not apply sleeps or turn pacing to realtime physics. Sequential challenge
  planning, scheduling and cached-plan identity must all use the reducer's
  actual current-turn boundary. A timeout can change it without a player input
  (audio memory keeps it in `model.public.turn_started_ms`, numeric challenges
  in `model.turn_started_at_ms`). Test timeout after a first reveal, two empty
  turns and unchanged-turn cache reuse through actual action/expiry transitions.
  Categories use append-only
  wire IDs and versioned pools: old masks/options/rounds keep their old meanings.

- Tournaments use the official `ServerWorkspace`; local trial adapters and
  diagnostic UUIDs must not enter the player UI. Do not silently fall back to
  local storage after server refusal. Keep complete bounded keyset reads,
  operation-scoped caches and write invalidation; a short page is not EOF.
  Authenticated invitation/decline records do
  not enroll participants or change match identities/retention. Keep original
  delivery-name case and exclude all previously invited recipients, including
  declines, from new sends in that tournament. Preserve legacy notice versions.
  Participant and invitation lists observe local view revisions without polling,
  focus changes or repeated speech. Ordinary table invites remain single-user.
  Own append acknowledgements preserve only provably unrelated immutable ID
  partitions when the server ID is contiguous; gaps and uncertain writes
  invalidate the affected table. Nested freshness checks may be shared only
  within one verification with no intervening SDK I/O. Coordinator snapshots
  are for display, never consent or mutation authority; manual refresh stays fresh.
  Viewing matches/results must not persist another observed schedule. Reuse
  a retained table head and complete operation-key batches only inside that
  worker scope; subsets/unions must not turn a short or failed read into
  complete evidence. Batch independent binding chains and directory lookups,
  preserving their individual author, lineage and result validation. Keep
  the read-budget regressions for large lists as well as failure tests.
  Availability or opening a notice is not participant consent. Retain a copied
  canonical result intent before network reads; saved continuations and result
  hashes must use the same canonical binding. Preserve uncertain operation keys.
  A temporary failure before local result retention must keep the original
  captured receipt in the bounded worker backlog. Retry only that local handoff
  on the next terminal observation or Matches entry, never recapture later
  evidence or blindly resend a network write. Finalize a failed attempt under
  the queue lock before publishing its error; a requeued job must stay counted.
  Corrupt journals, journal capacity limits and programmer failures are not retried.
  Ordered append-only creator claims are not atomic transactions or anti-cheat.
  Play creates/reuses one ordinary table and sends normal five-minute table
  invitations, accepted through the existing picker, notifications and Ctrl+J.
  Any planned participant may be elected creator; preserve planned seats/teams.
  Do not restore tournament readiness, consent records, a second invitation
  screen or periodic player-reservation renewal. Decline/expiry/departure is
  not a sporting result. Only a confirmed closed, never-started table may be
  replaced. Preserve creator election, binding lineage and immutable start
  intents; uncertain creation/start/result requires recovery, not a new game.
  A native tournament pointer is not authority; validate the server binding.
  Reuse an already checked attachment only for presentation, never to authorize
  entry/start/results. Keep optional discovery metadata within the host limit.
  Registration, start dates and play hours are independently optional; an
  organizational deadline blocks new match creation/start, not a return to a
  running bound game, and must never award a forfeit automatically. Deliver
  notices using authenticated registration names, outside canonical schedule
  and binding identities; changing a recipient's spelling must not rehash a match.
  Preserve
  event-driven view refresh, stable focus and the active-table guard.
  Individual absence uses one cumulative 300-second allowance, ordered native
  boundaries and the same logical clock for live ACK and cold replay. Never
  reset it on return or charge an interval not observed by the current host.
  Game-owned continuation/checkpoint hooks determine elimination and results;
  preserve original seats and reject forged ordinary elimination actions.
  Ctrl+F revalidates its displayed consequences and organizer authority at the
  write boundary. Team absence policy is separate, not inferred from singles.
  See [TOURNAMENT_SERVER_INTEGRATION.md](docs/TOURNAMENT_SERVER_INTEGRATION.md).

- Local tournament diagnostic windows must bind an accepted preview to its
  displayed full assignment input, not just a list index. Changing the selected
  tournament, seats or team assignment requires a new preview before
  configuration; changing only the table limit does not. Keep an uncertain original
  intent and its shown input until readback resolves it. Reopening and accepting
  the same assignment may create an alias: resolve its canonical accepted plan
  at the dispatcher operation boundary for policies, availability, proposals
  and executions. Do not relax document validation or add I/O to the UI's own
  lease-due check. These local diagnostic APIs are not the ordinary player
  tournament invitation flow described above.
  Accepted descendant phases share the existing bounded execution document;
  its record guard uses the document's MAX_RECORDS, not the separate eight-root
  producer limit. Dispatch policy, availability and proposal maps cannot exceed
  its canonical record count and must still validate every intent/roster key.
  Preserve the root-plan, descendant-store, byte/node and execution limits.
  Local readiness must retain and strictly validate the complete current
  ScheduleCandidate, including optional dates, daily hours and series win
  targets. Accepting that metadata must not open its gate or assign game roles.
  Readiness phase comes from the exact persisted Start lineage, not a constant
  or the UI. Reject new declarations after Start both at negotiation/snapshot
  and atomically at store, without revoking its grant; still read back earlier
  receipts idempotently. A phase conflict with an equal readiness revision
  needs its specific reason and matching started scope/plan/fixture/parent proof,
  not a blanket relaxation of corrupt-receipt validation. Test the actual local
  port through Start and another legal move: a correct fake port alone is not
  evidence that the real composition enforces this gate.

- Legacy participant-lease recovery checkpoints summarize an authenticated observed prefix,
  not a CAS. Replay every row after their boundary; preserve original server
  timestamps, release markers and expiry of incomplete uploads. Do not use
  expired lease recovery to discard uncertain game/result writes. Notice
  retries are finite reads only; they must never repeat consent or sends.
  A covered native scene can suspend extension ticks: the existing table
  presenter pumps the same coordinator, with a shared non-reentrant cadence
  and no inline network I/O. Preserve phase IDs and knockout bracket metadata
  in compact history used by native lists; do not repair missing IDs by index.

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
- An existing malformed hidden-answer snapshot is not a missing file. Reject
  invalid JSON/shape as StorageError before choosing an older sidecar or writing
  another envelope. Confirmed cleanup may return false; it must preserve bytes.
  Regressions: `hidden_submissions_shape_test.rb` and
  `hidden_submissions_corrupt_json_test.rb` in `test/persistence/`.
  A false cleanup return is not successful completion: propagate it through
  every adapter and memoize only after all applicable cleanup paths succeed.
  Compact local Duck results use the existing atomic commitment-checked
  removal, scoped to accepted closures, session and local account. Preserve
  unresolved entries and replacements made between enumeration and deletion;
  retry a transient storage refusal against the same replay.
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
  A retained background client must adopt the current UI owner when attaching
  its visible view, just as its progress driver does. Coverage/presentation
  checks must not keep the thread which originally created it behind another
  window. Verify accepted input reaches the surface after return and remains
  suppressed while the form is actually covered.
  Tests: game_session_runner*_test.rb and game_session_screen_test.rb.
- Open the leave-table confirmation before `GameScreen#run` ends.
  Keep the executor, realtime client and presentation alive until leaving
  succeeds; No, Escape or a failed operation must not recreate them from
  scratch. Continue to use the shared leave guard and revalidate it after
  the dialog. A confirmed departure returns `:left_table`, without a second
  question in the lobby; server-side closure asks no question.
  Regression: `game_leave_confirmation_test.rb`.
- Ordinary departure, including guests/observers and the first-connection
  recovery form, requires a confirmed native departure. A cancelled wait or
  a locally closed SDK object is not server acknowledgement. The shared
  adapter uses the existing endpoint leave/close RPC before closing the local
  Session; it preserves the exact visit on error and accepts only explicit
  absence/closure responses as reconciliation. Do not infer success from an
  aggregate SDK retry count, rejoin to check departure, or discard a newer
  attachment when an old request finishes. Rejected provisional joins alone
  retain explicitly deferred SDK cleanup; that is not a successful UI exit.
  Regressions: `confirmed_table_departure_test.rb`,
  `live_sessions_departure_boundary_test.rb`, `table_connection_departure_test.rb`.
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
  `Replay#players` is the canonical roster even when `state` is a Hash:
  Pong and Audio Ball do not duplicate it under `state[:players]`.
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
- A finite single-choice modal uses `GameRoomUI.choose_index`, not a copied
  ListBox/Form loop. It returns an index (zero is valid) or nil; callers still
  validate their token, selected identity and authority after it closes.
  Do not force multi-selection/deadline forms into that simpler contract.
  When introducing or extending shared capabilities, document exact current
  entry points, ownership, defaults, cancellation/errors and required tests;
  verify examples and migrate genuinely equivalent consumers in the same batch.
- Do not move game rules into `GameScreen` or UI details into transport.
- Match action-key modifiers at the press boundary, not from final held state
  or native Form event parameters. Shared bindings/text gating use
  `GameRoomUI.modifiers_when_pressed` before consuming input; keep modified
  text navigation native. Test modifier release and addition after the key
  inside one frame, not just a modifier held through the next UI update.
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
- Bound historical identities as well as inboxes. Invitation retry metadata may
  follow the current roster; sequence watermarks must survive leave/rejoin in
  the same epoch. Use Channel's shared history limit/generation-safe reconnect,
  not in-place watermark eviction. Native messages can be authenticated and
  ACKed before their sender appears in the local native roster; requiring that
  roster ID without a recovery design can silently drop valid delivered input.
  Regression: `test/realtime/channel_roster_history_test.rb`.
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
  Validate the exact canonical saved-event fields before replay. Native-only
  proof/payload metadata belongs to the authenticated transport, not an imported
  archive, even when its checksum is correct. Unknown fields must produce the
  existing controlled archive-validation error, not reach game reducers.
  The independent native `game_archive` validator enforces the same canonical
  field allowlist; an authenticated room owner does not authenticate imported
  native proof fields. Preserve normal moves, roster changes and `game_time`.

- History/replay files (`lib/recordings`) are passive records, not resumable
  saves. Observe existing renderers; never rerun physics, publish results or
  evaluate file contents during playback. Reuse Progress for background audio.
  Capture queues are bounded and disk work stays on finite native workers.
  Immutable chunk leases protect an export from new captures and cleanup.
  The per-account directory owns the library; export copies, delete removes
  only the selected owned file. Confirmed message delivery removes the exact
  sender copy, never the library file. Preview never removes received messages;
  ask about removal only after persistent import succeeds. Preserve the delivery
  journal on an uncertain send and reconcile rather than duplicate it.
  The header describes the starting participants; same-session replacements
  belong in the current frame roster using the same participant display names.
  Validate an explicit roster against the fixed seat count before rendering.
  Information, context actions and perspective labels follow that frame while
  preserving the listening seat. Refresh native controls quietly on their own
  active UI update, never in covered/background Progress work. A roster change
  must neither discard the existing capture nor create another match opening.

- Update affected tests in the same change as the behavior they verify, not
  after a failed GitHub run. Search existing tests, shared fixtures, snapshots
  and binary/native checks for dependent assumptions, including defaults,
  timing, UI controls, result policies and saved historical inputs. Run that
  affected scope before pushing; adding a new regression alone is not enough.
  First establish whether a failure is a product defect or an approved contract
  change. Never replace expected values merely to make a test pass. Historical
  corpora keep their explicit original inputs and compatibility guarantees.
- Run targeted tests during development.
- After every UI fix, verify the resulting player interaction, not only the
  submitted action or model state. Exercise the real native controls through
  opening, editing, confirmation, cancellation and return; inspect focus,
  cursor/default selection and the exact ordered speech output. Assert that
  prompts occur once and local navigation does not reread unrelated table
  status. A stubbed input dialog or handler-only test cannot establish this.
  Keep a regression for the reported presentation defect and clearly separate
  captured speech from actual listening or live-account verification.
- Before a pull request, run the affected tests and their relevant dependencies
  with `ruby test/run.rb <selected paths>`; follow the current scope restriction
  above. Do not invoke the full runner without authorization. Include the
  relevant common checks from [TESTING.md](docs/TESTING.md#select-checks-from-the-change).
- Transport changes require `live_sessions_*`, `test/transport/transport_test.rb`,
  `test/transport/game_sync_test.rb` and a multi-client scenario.
- Shared-surface changes require a test of the surface itself and at least
  one affected game.
- Do not change the release number without the maintainer's explicit instruction.
- The maintainer's standing instruction is to sign every requested Power Games
  package with their author certificate, including requested test packages,
  unless they explicitly ask for an unsigned package. A build request includes
  permission to sign locally; do not ask for signing confirmation again.
  Installation, publication and GitHub uploads still need a separate instruction.

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
- Explicit ordinary table creation requests a new table. Do not silently
  substitute an existing visit, scan other connections or restore an account-wide
  creation lock/fence: the maintainer removed that mechanism on 23 October 2026.
  The single-program-window guard is separate and remains enabled. Saved-game
  continuation and tournament entry retain their own exact-identity checks;
  neither may repurpose an unrelated table. Tournament create claims still run
  after local payload validation, immediately before the native request.
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
- Sports player statistics reuse that worker/outbox framework, not game-time network
  writes. The final human roster owns the result; team goals are not divided.
  Use confirmed tournament receipts (including technical goals), not a second
  ordinary report of the same bound session. Preserve match-key deduplication,
  canonical dates, complete short-page reads and hidden internal ordering points.
  Expose these games through the shared player-statistics capability, not the
  leaderboard capability. Preserve raw result records and pending uploads;
  do not restore ranking points, weights or places.
  See [SPORTS_LEADERBOARDS.md](docs/SPORTS_LEADERBOARDS.md).
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
- Statistics, presence and Krowa table scans do not stop at a short page. The server
  may return 1000 records despite a schema limit of 2000, or fewer still.
  Request at most 1000 (or the table's lower limit), advance the offset/ID
  by the records actually received and stop only on an empty response or
  a confirmed snapshot boundary or the reader's explicit total acquisition cap.
  Preserve deduplication, canonical dates,
  progress and cancellation checks; a later-page failure is not partial
  success. Test servers must be able to shorten pages independently of
  the schema. Regressions: `statistics_pagination_test.rb`,
  `room_presence_store_test.rb` and `game_room_analytics_client_test.rb`.
  Krowa's grouped word browser retains its 2000-raw-row cap and canonical
  daily assignments; `test/games/krowa/short_page_search_test.rb` covers short
  responses independently from requested limits, plus later-page failure.
  The bounded presence cleanup carries its cursor across nonempty short pages
  between existing cleanup intervals; only an empty tail resets it. Preserve
  native ownership and immediate renewed-row checks before deletion.
  Do not “fix” counts by inventing starts or capping completions at starts.
- Board presentation is local. Save only explicitly allowed flags, and
  orientation relative to the player's seat; do not save cursors or drafts.
  New Ludo tables use `enter_on_one: true`; old events without that option
  still follow the former rules. Do not change the meaning of old rolls.
- Ctrl+M and Ctrl+Shift+R act on the selected person in the participant
  list, not the game field. Help checks current availability, and execution
  rechecks permissions and identity, not just the row index.

## Acceptance review for new games and game PRs

Use [the game review checklist](docs/GAME_ACCEPTANCE.md) when implementing,
importing or reviewing a game, including a new variant. Passing a model test,
starting a table or finishing an all-bot match is not sufficient. Before calling
the game ready, walk through an ordinary round and relevant edge cases from
the player and observer views. Check what the player hears, where focus goes,
which native controls and shortcuts work, and what the rules tell a newcomer
to do next. Fix issues in the same change; state separately what could not be
verified in ELTEN or by listening. Apply the same review to a contributed PR.

## Writing game rules

Before writing, importing, revising or translating a rulebook, read the
[game rulebook editorial guidelines](docs/RULES_EDITORIAL.md) in full.
They apply to every language and to contributions from PRs. Teach the game,
not the implementation or release history. Natural, connected prose is the
main requirement: avoid both overloaded sentences and strings of clipped
commands, and do not impose identical wording or chapters on every game.
Review complete paragraphs and the whole changed text separately from
factual and format checks. Preserve exact rules, meaningful exceptions,
required credits and user restrictions on changes. Teach essential game
controls beside the action being explained: the actual key, button or short
menu path, including how to open a described personal setting. The separate
shortcut list is a quick reference, not a substitute for these instructions.
Remove details that do not help someone understand or play the game, rather
than just rephrasing them. Do not confuse that with compressing essential
rules into card-effect formulas: preserve the actions, connections and
sequence a beginner needs. Optimise for understanding a first turn, not a
minimum word count. Use the guide's worked examples and a text-only first-turn
walkthrough; format checks do not prove that someone can learn from the text.
Use natural headings that name their subject, not slogans or metaphors;
familiar titles may recur across games. Check the contents without the body.
Keep shared application help separate. Do not rewrite unrelated rulebooks.

Apply the guide's sentence-level checks in each language: natural action–object
combinations, accurate implied conditions/history, clear references and
agreement, consistent address/terms, purposeful repetition and complete
instructions. A correction identifies a type of problem, not a phrase to
replace globally or a Polish sentence to copy into every edition. Review
whole authorised texts separately from mechanics and format validation;
do not make fluent wording more formal or uniform merely for variety.

All newly written rules, including AI-written rules created with a new game,
must follow the editorial guide regardless of who is credited as author.
A byline or approval of a working draft does not exempt them from the guide.
Preserve rules or translations that a creator directly supplies or
selects as the text to use, before creating the game or later. The creator need
not know the guide or explicitly forbid rewriting. Do not rewrite or supplement
that text without permission; report verified outdated passages separately.
Material explicitly supplied only as a source or inspiration may instead be
used to write new rules. If its intended role is unclear, ask before substantial
rewriting; do not infer human or AI authorship from style. An explicit editing
request permits changes within its scope. A request to translate permits a
faithful, natural rendering, not added explanations.
The maintainer has selected paulinux's supplied Polish Krowa rules to preserve;
keep that text and retain its meaning and voice in other language editions.
For commissioned new language editions, write from the verified game facts
in natural target-language prose rather than translating sentence by sentence.

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

After a submitted quiz proposal has been integrated and the targeted checks
have passed, delete that proposal's message from the maintainer's ELTEN
account. Verify the exact message ID, sender and submission identifier before
deleting; never delete the whole conversation or unrelated messages. Retain
the editorial decisions and necessary provenance locally before deletion.
Do not delete a proposal while its integration is unfinished or blocked.

## Readable quiz question copies

In Polish quiz questions and answers, write centuries with Arabic ordinal
numerals and a period: "w 17. wieku", "19. i 20.", "w 5. wieku p.n.e.".
Expand "w." to "wieku". Adjectives take no period: "19-wieczny".
Preserve Roman numerals in names, regnal numbers and established titles,
such as Henryk VIII, Jan Paweł II, II wojna światowa and Balet XX Wieku.

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
  A covered start can construct the client on the forum's UI thread;
  attaching its form must adopt that form's UI thread, even on reattachment.
  Test fresh movement/serving after return, not only points while covered
  (`test/realtime/covered_start_return_test.rb`).
  The ordinary executor writes agreed points. A Pong point proposal must
  match the current rally even before the validator is called.
- Typing input validity is not provider availability. A Liblouis call that
  succeeds and consumes its whole input may produce zero characters for an
  unfinished number/capital marker. Space must then reject that word, not
  cancel practice or count an empty word. Cover own-text as well as source-text
  practice with the real bundled DLL, and preserve mistakes in checkpoints.
  Failed calls, partial consumption and invalid output lengths remain errors;
  do not hide them behind a blanket rescue.
- The Scrabble preview client implements the full GameScreen client
  contract, not just message reception. Test its actual start/loop/close
  lifecycle. The draft contains only placed tiles, not the rest of the rack
  or a private choice.

Translations have one `locale/<LANG>.po` and a generated `locale/<LANG>.mo`
per language, plus a shared POT. Do not recreate the old JSON fragments or
their export manifest. PO supplies translations of English-based rules and
the application's changelog. Independently authored full rulebooks with their
own chapter layout live in `tools/data/rulebooks/<LANG>/<game>.json`. The current
complete editions use `EN/`, `PL/`, `CS/`, `ES/` and `RU/`; edit each there,
including its `option_chapters` mapping.
Compile them with `tools/compile-rulebooks.rb`; do not duplicate their text in
PO or hand-edit generated Ruby. Every supported language must cover all games;
update all affected editions together, respecting creator-supplied texts.
Changelog entries are in
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

README is the player guide to the application, not a second rulebook. Keep
the complete, briefly introduced game catalogue in its own section; explain
individual games' rules, variants, scoring and controls in their rulebooks.
The guide owns shared table/chat/help controls and complete instructions for
application modules such as tournaments, statistics, recordings and question
creation. Describe their current use, not implementation details or release
history. When removing a duplicated game instruction, check its rulebook first;
do not discard essential guidance or copy every redundant paragraph there.
Keep leaderboards and statistics separate, and the detailed tournament chapter
immediately before the contribution chapter. Preserve selected author wording
and credits. Review every changed language as natural prose, not just as a
matching outline; update the native README/navigation coverage alongside it.

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
