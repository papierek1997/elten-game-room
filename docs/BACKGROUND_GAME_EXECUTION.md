# Game execution and presentation behind another window

`GameRoomSessionRunner` runs the model, automatic policies and bots without
a form. The visible and covered game use the same runner. `GameScreen`
retains the controls, key handling, speech, sounds, focus, history and dialogs.
Behind another window, controls are not updated and speech synthesis is not
invoked from the worker thread. The active UI thread does, however, handle
announcements and effects for events already received, even before returning
to the game. On return, the screen shows the confirmed replay without
announcing those events again.

Pong and Audio Ball do not use this runner. Their independent simulation,
pause protocol, input and Communications remain unchanged.

## Speech and sounds while Messages or the forum is open

The runner publishes a copied presentation bundle after an existing state
read; it does not make additional server queries. `GameRoomBackgroundPresentation`
registers the active screen and uses a narrow bridge in `EltenAPI::UI#loop_update`.
The original method runs unchanged; afterward, only the current UI thread may
pass ready events from the covered game to the existing presenters. This is
not a second `GameScreen#run`, a global extension tick or a manual update of
the game form. The bridge does not read the keyboard or change the active
window, focus, draft, selection or history position.

It uses the same event descriptions, turn transitions, score, sound selector,
volume settings and shared deduplication cursors. Speech uses `stop: false`
and `break_sequence: false`. Battleship's sound sequence continues even without
another network event. Quiz time announcements use the same session clock and
keys as the visible screen. Chat messages follow the same path; the form
remains untouched.

A rematch may arrive while the player is still on the forum. The presentation
cursor distinguishes sessions but does not compare their IDs numerically:
native identifiers are random. Returning to an old view must not roll back a
new game that has already been announced. Join/leave sounds also use one
participant projection so that the old screen buffer does not produce a
spurious departure and re-entry.

The host bridge does not retain a closure from the old application namespace.
It is installed once, and managed registrations are removed when the game
closes. Without an active registration, it reads and plays nothing. ELTEN's
source files were not changed. Krowa's local dialogs are still opened by its
visible adapter, not by the presenter running behind another window.

Regression tests: `test/ui/game_background_presentation_test.rb` and
`test/ui/game_background_native_input_test.rb`. The first covers a complete
game, rematch, random IDs, score announcements, audio sequencing, the quiz
clock, deduplication, registration cleanup and 20 binary reloads of the
application namespace. The second uses the host's native controls, keyboard
and speech adapter with a controlled character source: Polish text, cursor
and selection remain unchanged.

## Safety boundaries

- A `GameRoomSessionFeed` subscription has its own coalesced signals. A read
  by the runner does not consume the signal intended for the screen.
- Only ready callbacks from the runner's own endpoint are delivered. A local
  pass every 50 ms does not mean server polling. State is read after a change,
  during existing write verification or during connection recovery.
- The runner model and planner model are separate from the UI model.
  `ActionContext` contains copied data, not controls. The Categories draft
  comes from the UI and carries the identity of its own round/phase.
- `Coordinator`, `Simulation`, `TurnController`, `action_for` and the repository
  are preserved. No heuristics, penalties, answer choices on behalf of a human
  or different authorization were added. The seed and bot search budgets
  remain the same as in the existing path.
- Bot planning does not hold the write lock. After computing a decision, the
  runner delivers callbacks received during the computation, rereads the state
  and rejects a stale plan. UNO interception or saying Makao need not wait
  for the bot's computation to finish.
- Action writes, session changes and the screen's network operations share a
  short synchronization boundary. Waiting for it happens in `Tasks`, not by
  blocking the UI loop. It does not cover form waits or planning.
- Multiple open instances for the same account/table select one runner. The
  active window has priority, or the last active window when all are covered.
  Handing off execution reconciles state and does not bypass the pause after
  an uncertain write. This mechanism does not transfer the server-side table
  host role.
- An ordinary choice is tied to the displayed revision. Games with concurrent
  input allow only explicitly defined exceptions within their own round/phase:
  Quiz and Categories answers, Battleship fleets, Krowa race attempts, UNO
  interceptions/declarations and the Makao declaration. Ultimately,
  `action_for` always validates them against fresh state. The UNO penalty for
  a late attempt is also preserved; an old card does not carry over into the
  next deal.
- A save freeze, game interruption and table closure stop actions. A rematch
  uses a new session ID. An uncertain write preserves the existing confirmation
  path, message identifier and backoff; it is not sent as a new move. Closing
  does not kill the thread midway through a write.
- A transient error when writing an automatic action is subject to backoff,
  including for a local draft. A programming error stops retries of the faulty
  action. The error reaches the UI adapter only on its own thread. Returning
  after connection recovery has completed does not restart the previous
  30-second pause.

## Guidance for new games

The model and automatic policies must work without the UI. They must not open
forms, read the active control, call `loop_update` or speak. Custom constructor
arguments must be preserved in `build_session_game` (for example, Krowa's word
bank). The planner has its own persistent model instance; its mutable caches
must not be shared with the screen.

`automatic_action_due?` defines when an action is due, and
`automatic_action`/`action_for` define the legal operation. Do not assume that
the entire policy will be called indefinitely for an unchanged position. If
a draft is needed, define `automatic_surface_identity` and a safe data
snapshot. `concurrent_session_input?` must not be a blanket bypass of revision
checks; it compares the specific round identity and operation type.

Krowa's local presentation services (definition dialog, gallery, invitation to
publish a score and private solution display after giving up) still belong to
the UI adapter. The runner handles state, attempt evaluation and the public
outcome; it does not move arbitrary `game_client` methods to the worker thread.

## Verification

Runner tests are in `test/session/`, and presentation tests are in
`test/ui/game_background_presentation_test.rb` and
`test/ui/game_background_native_input_test.rb`. Check multiple instances,
planning outside the lock, uncertain writes, return, deadlines, rematches and
closure. A live-client trial must confirm speech output and active audio while
the game is still behind a native window. A matching model after return does
not prove background presentation; audio stubs are not a substitute for
listening.
