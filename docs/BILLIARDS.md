# Billiards

`billiards` contains pool, snooker, English Billiards, carom and Free Pyramid
under one game ID. Ordinary tables may be public and support bots. Tournament
registration remains disabled. New table creation defaults to Social billiards;
an explicit discipline choice and saved matches retain their selected variant. An absent
historical discipline still means private practice; existing practice saves
retain their original rules, free placement and solo undo. New configuration
offers Social billiards instead of creating more practice games.

## Disciplines and configuration

| Discipline ID | Players | Round or frame objective |
| --- | --- | --- |
| `friendly` | 2–8 | Clear the other object balls, then pocket the highest numbered starting ball. Pocketing that final ball ends the round immediately; an early or foul pot loses it. |
| `eight` | 2 | Clear the assigned group and legally call and pocket the 8-ball. |
| `nine` | 2 | Contact the lowest remaining ball first; a legal 9-ball pot wins. |
| `ten` | 2 | Call ball and pocket; the 10-ball wins only when it was the sole object ball before the shot. |
| `straight` | 2 | Reach the point target; fourteen scored balls are reracked during a continuing visit. |
| `one_pocket` | 2 | Score eight balls in the assigned foot pocket. |
| `bank_short`, `bank_full` | 2 | Score five of nine or eight of fifteen balls through declared bank shots. |
| `cutthroat` | 3 | Leave only one seat's fixed group on the table, under the club rules below. |
| `blackball` | 2 | Clear the assigned group and legally pocket black; no called pocket. |
| `snooker` | 2 | Fifteen reds, colours and frame points, including free ball, Miss decisions and respotted black. |
| `english` | 2 | Score cannons and hazards to a point target or within the selected time. |
| `carom`, `one_cushion`, `three_cushion` | 2 | Reach the point target through valid cannons with the discipline's cushion and corner-zone requirements. |
| `pyramid` | 2 | Score eight balls, using any remaining ball as the cue after the initial coloured-ball break. |

`race_to` is 1–25 rack/frame wins, default 1. Social billiards instead plays
exactly `rounds` rounds, 1–30, default 1; the most round wins decides the
match, with a draw if the leaders tie. Its `layout` is `single`, `diamond`
or `triangle`; new tables default to `diamond`: object balls 1–9 plus the
white cue, with the 9-ball played last. Explicit `single`/`triangle` choices
and older saved layouts retain their meanings. A final-ball loss awards a
round to the next seat in roster order when more than two people play.

Social billiards separately awards one pot point for each legally pocketed
object ball, including a legal final ball. Cue-ball pots, foul shots and shots
that pocket the final ball early earn no pot points. These totals persist
across all rounds; they do not change round wins, the match winner or a tied
match. S and Shift+P present both round wins and pot points. A new match resets
both counters. Historical practice keeps its existing scoring and controls.

`point_target` is 1–1000, default 100, for straight pool, English Billiards
and caroms. English Billiards selects `english_limit: points|time`, default
`points`; timed frames use `time_limit_minutes`, 1–180, default 30.
`baulk_crossing`, default false, enables the optional long-break crossing
restriction. Carom's `equalizing`, default true, allows the nonstarter's
equalizing inning. One Pocket, Bank Pool and Pyramid retain their fixed
discipline targets. `accurate` selects 480 rather than 240 simulation steps
per second. `bot_skill` is `easy|medium|hard`. Historical practice retains
its `shots` limit of 1–500, default 30.

Options are declared through the ordinary `OptionDefinition` schema. A new
match records its `rack_seed`; subsequent racks derive their shuffle from
that seed and the rack number. Accepted history, not a later UI default,
determines reconstruction. Practice-only undo/reset/pass cannot enter a
competitive discipline.

## Rule sources and digital decisions

Pool rules follow the [WPA Rules effective 21 October 2026](https://wpapool.com/wp-content/uploads/2026/10/WPA-Rules-2026-10-21-211.pdf)
and [WPA Regulations](https://wpapool.com/wp-content/uploads/2026/10/WPA-Regs-2026-10-21-211.pdf):
chapters 4–8 cover 8-ball, 9-ball, 10-ball, 14.1 and Blackball; chapters 12–13
cover One Pocket and Bank Pool. The Blackball group pattern was checked
against the chapter 8.4 diagram, including the black on the Foot Spot.
The numbered solids/stripes permitted by chapter 8.2 identify its groups.

Snooker and English Billiards use the [WPBSA 2024–25 rulebook](https://wpbsa.com/wp-content/uploads/2198_WPBSA-Rulebook-2024-25.pdf).
Caroms use the [UMB World Rules of Carom Billiard](https://www.umb-carom.org/uploads/documents/wifwnpfs.bz0.pdf)
with the [appendix updated 1 April 2025](https://www.umb-carom.org/uploads/documents/d3qro1mn.zad.pdf),
including starting spots, corner zones and three-cushion replacements.
Free Pyramid uses the [IPC September 2025 rules](https://www.ipc-billiard.com/sites/default/files/04-novaya_redakciya_pravil_piramidy_2025-09.pdf),
General Pyramid sections 6, 9, 13, 19, 20, 25, 27 and Free Pyramid sections
1–8. The older English IPC penalty text is not the implemented contract.

The first listed seat starts, replacing a physical lag. Subsequent new
racks/frames rotate the starter. Stalemate requires mutual agreement. For
straight pool, One Pocket and Bank Pool, the subsequent breaker choice
replaces another physical lag while retaining the required points/debts.
Social billiards and Cutthroat are explicit club formats. No federation
certification or measured equivalence to a physical table is claimed.

In Cutthroat, seats own 1–5, 6–10 and 11–15. A legal own-ball pot is an
allowed sacrifice. Empty groups are skipped, but a foul restores the
lowest numbered previously pocketed ball for each opponent, including an
eliminated seat. A legal stroke clearing every group draws the round.
This temporary elimination does not replace canonical participants.
Conceding instead removes that seat's group for the rest of the rack,
including agreed reracks. Remaining seats continue; a rerack cannot revive
the conceded player or select them as breaker. A multiplayer stalemate
proposal needs agreement from every remaining seat. Unscored reracks do
not consume a social match's fixed round count.

After a Pyramid foul, improperly pocketed/off-table balls are respotted,
then the opponent selects a table ball to remove and receives one point.
They choose who plays next; an illegal break also permits a partial rerack
with either player breaking. The penalty point is retained. If necessary,
reracking exchanges the removed coloured ball for a remaining ivory ball
without changing scores. Normal no-pot strokes use the chronological IPC
completion requirements, including cushion/centre-line sequences, frozen
balls and subsequent driven-ball contacts.

M moves only the active cue when the discipline permits it. A Blackball free
shot may use the existing position or M placement in baulk; it does not
require moving a cue that remains on the table. English Billiards/snooker
use the D, with discipline-owned resets and spotting. Ordinary fouls do
not reset the layout. Miss replacement remains an explicit opponent choice
and retains penalties. The digital Snooker referee does not infer intent
on fully obstructed shots; Blackball does not infer deliberate wrong-first
intent. Frozen forward pushes are approximated from the available planar
contact/direction/spin evidence rather than measured cue-tip contact time.

## Ownership and replay contract

- `games/billiards.rb`: option schema, authenticated replay, ordinary
  `action_for` validation, results and presentation stages. The repository
  and `GameRoomSessionRunner` remain the only move executor.
  `games/billiards_clock.rb` supplies the game's hooks to that executor's
  automatic-action contract for timed English Billiards.
- `lib/billiards/rules.rb`, `engines.rb`: shared setup, engine dispatch,
  active-cue identity, placement and spotting. `pool.rb`/`snooker.rb` retain
  the original competition rules. New engines are `friendly.rb`,
  `ten_ball.rb`, `points_pool.rb`, `blackball.rb`, `cutthroat.rb`,
  `english_billiards.rb`, `carom.rb` and `pyramid.rb`.
- `geometry.rb`: table profiles, cushions/jaws, actual pocket-admission
  planes, placement, aiming rays and ghost-ball aiming. `visibility.rb`
  owns whole-ball/edge and whole-D visibility at 0.1 mm placement precision.
- `physics.rb`: deterministic simulation in metres, seconds and radians.
  +X points right, +Y up; displayed angles grow anticlockwise from +X.
- `strategy.rb`, `shot_candidates.rb`: deterministic proposals and bounded
  simulations using public positions, through the ordinary bot executor.
- `lib/game_surfaces/billiards_surface.rb`: native controls, local drafts,
  declarations and finite prediction tasks. `controls.rb` drives both
  shortcuts and F1 help; `match_presentation.rb` owns rule/status messages.
- `aim_audio.rb`: local synthesized aiming cues through the ordinary sound
  gate and central playback path, without HRTF initialization.

Physical IDs and ball-array order remain stable. Pool uses cue ID 0;
English Billiards and caroms use the current seat's own cue, IDs 0 or 1.
Pyramid records the chosen cue on each shot. Simulation accepts `cue_id:`
without renumbering or moving a ball to the front of the array. Placement,
aiming, prediction, scoring and cache identity use that same physical ID.
Changing pair order would alter old tightly packed contact resolution.

Event values are integer-only compact JSON arrays within the shared
64-character limit:

- Practice shot: `[1, revision, angle, power, top, side]`.
- Placement: `[1, revision, ball_id, x, y]`; simple actions:
  `[1, revision]`.
- Original competitive shot and Social billiards:
  `[2, revision, angle, power, top, side, call, pocket, mode]`.
- Advanced discipline shot:
  `[3, revision, angle, power, top, side, call, pocket, mode, cue_id, packed_rails]`.
- Decisions: `[2, revision, choice_index]`.

`packed_rails` starts with sentinel 1 and appends each declared rail in two
bits: left/right/top/bottom are 0/1/2/3. At most twelve rails are declared;
the decoder restores their order. The full serialized value must still
fit the shared limit, including a large revision. Mode 0 is ordinary,
1 safety, 2 push-out and 3 free ball. Discipline/phase determine which
declarations exist. Older wire versions keep their existing trajectories
and meanings. Exact keys/types, actor, event ID, revision, current cue,
declaration, placement and tip-offset bounds are validated before a move.

Angle units are 0.01 degree, power units 0.1 percent, placement units 0.1 mm
and spin units one percent. The replay cache owns authenticated input;
copied simulation results never confer authority. A separate pure-physics
cache is limited to 64 entries and 4 MiB of encoded values; its key covers
the complete geometry, ball state, shot, accuracy and physical cue ID.
Each caller receives an independent copy.

Timed English Billiards uses the ordinary executor's automatic boundary,
not a game-owned polling loop or wall-clock read inside the rules engine.
The accepted `clock_start` record fixes the frame's origin; a confirmed
next-frame choice clears it before the next start. `GameRoomSessionClock`
converts native accepted event times into the same logical time used by
the executor. That boundary determines whether a shot began before the
deadline. A stroke already accepted before expiry receives its full
simulation and scoring before the frame is settled. Merely opening a
prediction or local declaration does not reserve time or start a shot.

## Physical profiles, telemetry and bounds

| Profile | Bed size in metres | Ball radius / mass | Pockets |
| --- | --- | --- | --- |
| Pool, Social billiards, Blackball | 2.54 × 1.27 | 0.028575 m / 0.17 kg | Six, existing pool jaws |
| Snooker, English Billiards | 3.569 × 1.778 | 0.02625 m / 0.142 kg | Six, retained digital profile |
| Caroms | 2.84 × 1.42 | 0.03075 m / 0.21 kg | None |
| Free Pyramid | 3.55 × 1.775 | 0.034 m / 0.285 kg | Narrow jaws, approximately 72.8 mm corner and 83 mm middle mouths |

Blackball intentionally uses the existing pool-sized digital profile.
Pyramid's training profile follows the dimensions in the [FBSR technical
programme](https://www.fbsrf.ru/sites/default/files/tehnicheskie_normativy_fbsr_1.pdf);
that older programme does not establish current equipment certification.
The UMB straight-rail corner triangles have intercepts 0.71 × 0.355 m.
Changing mouth geometry also changes physical jaws and ray-admission
planes, rather than adding a proximity-based pocket threshold.

The solver integrates sliding/rolling friction, follow/draw and side spin,
normal restitution and bounded tangential impulses. Adaptive substeps at
high speed and three collision passes handle packed racks. Final positions
are rounded to nine decimals. The model remains planar: no jumps, cue
elevation, cloth nap, massé or three-dimensional pocket rattles. Initial
side-spin deflection and shared collision coefficients are approximations,
not calibration of an actual cue, cloth or table. The [Pooltool author's
derivations](https://ekiefl.github.io/2020/04/24/pooltool-theory/) informed
the contact calculations; this implementation does not vendor that code.

Advanced disciplines add deterministic event order to the physical tape,
second-ball contact positions `bx/by`, cushion identity for jaw contacts,
directional `:crossing` events at head/middle/baulk lines, and `:zone_exit`
events for straight-rail corner zones. Rule engines consume these in
chronology. The original discipline tapes retain their old contract.
Crossing/zone facts do not create spurious collision sounds.

A simulation has at most 50,000 steps, 60 simulated seconds and 4096
events. Limits raise a diagnostic instead of silently truncating a result.
Prediction is a finite, cancellable native task with a 15-second bound;
closing/changing the surface invalidates its result before speech. Bot
planning builds at most 96 geometric proposals and simulates at most 18
shots (six candidates at three powers in caroms). Bank proposals use one
or two cushions; carom proposals use the discipline's cushion count.
These are bounded tactical approximations, not exhaustive optimal play.
Idle tables perform no continuous physics work.

## Presentation and player documentation

P opens declarations and current decisions, Shift+P reads status, M places
the active cue, S speaks seats/scores, T announces the turn and Q concedes
the rack/frame. Bank Pool declarations include the ordered cushions.
Pyramid's menu selects the local cue and, after a foul, the penalty ball.
Local declarations are drafts until a shot is accepted. Closing a modal
or a stale revision cannot submit it. Shared F2/F3 volume controls remain
owned by the framework.
Social score readouts and match status include accumulated pot points beside
round wins; only round wins determine the match result.

Y previews a whole shot. V describes the cue's cushion rebound. Comma
previews the currently aimed object ball's actual simulated continuation,
using the current angle, power and spin, including a miss from insufficient
power. B instead follows the geometric aiming ray through successive
objects to the terminal cushion/pocket. Shift+B changes draw spin. These
queries never write a move. Physical cue identity is respected throughout.

Ball readouts begin with their number/colour, with discipline-owned
identities for own cues and Pyramid ivories. Pocket numbers are 1–3 below
and 4–6 above, left to right. Aim feedback is 5000 Hz at a central first
contact, falling to 500 Hz at a grazing edge; a pocket ray gives 3000 Hz
and a miss is silent. The 40 ms, 48 kHz mono cues use 3 ms ramps and a
−16.5 dBFS peak. Only the latest aim voice is retained. Modal entry, blur
or move submission stops it; normal game volume/mute policies apply.
Aiming tones always play centrally without HRTF, so short pulses replaced
during rapid arrow repeats do not enter the delayed spatial-effects path.

All contact events remain available in U. Sound presentation groups cues
in 50 ms buckets and compresses silent gaps to at most 1.5 seconds. The
active UI-thread presenter owns speech and audio, including covered games;
workers only publish copied results. Sounds use ELTEN's standard effect
buffering, never forced low latency, and do not alter the global mixer.

Contact sounds use local HRTF positions derived from the actual event on the
table, rather than the acting player's seat. The coordinate frame is fixed:
table left/right are listener left/right, with the far side in front. Cue,
ball, cushion and pocket sounds use this frame. The existing Power Games
HRTF setting and per-game 3D-sound selection govern these physical contact
sounds. Disabled HRTF or an unavailable spatial engine
retains the ordinary stereo path. No separate billiards audio option, cue
profile, artificial reverberation or continuous audio worker is introduced.

The game opts into the shared sound contract through
`event_sound_positions(history:, replay:)`, returning an asset-to-position map
of `[x, 0, z]`. Presentation stages retain copied contact evidence, so
`GameRoomSpatialSound.event_position(..., history: nil)` and `cue_position`
can resolve each staged cue from its own event. At most one cue of each sound
type is presented per 50 ms bucket. These presentation coordinates do not
change simulation, accepted records, move authority or replay chronology.

Authored rulebooks live in
`tools/data/rulebooks/{EN,PL,CS,ES,RU}/billiards.json`; the compiler owns
`games/generated/rulebooks/billiards.rb`. Interface messages use the normal
PO catalogs. Rulebook factual validation and separate whole-book language
review follow [RULES_EDITORIAL.md](RULES_EDITORIAL.md).
`LICENSES/BILLIARDS-SOUNDS.txt` records the sources, licences and edits of
the four contact assets; the cushion sample is a separate CC0 pool-rail
recording. No rolling-loop or continuously spatialized table audio is
implemented.

## Verification and remaining limits

Use only changed cases, routed through ELTEN MCP as requested by the user;
do not rerun the whole project runner. Shared helpers live in
`test/support/`, with no imports of another test's executable scenarios.
Relevant checks in `test/games/billiards/` include:

- `social_points_test.rb` verifies the social table default, points per legal
  pot, zero-point fouls/early finishes, cumulative round totals, unchanged
  match ties, cold reconstruction and the native spoken S announcement.
  `spatial_audio_test.rb` sends copied real shot contacts through the actual
  shared presenter for players, spectators and covered views; it checks
  directions, HRTF settings/availability, stereo fallback and unchanged
  buffering. `aim_audio_test.rb` covers native arrow repeats, central tones
  that do not initialize HRTF, and bounded handling of playback failure.

- `friendly_test.rb`, `additional_pool_test.rb`, `points_pool_test.rb`,
  `english_billiards_test.rb`, `carom_test.rb`, `pyramid_test.rb`: discipline
  boundaries, scoring, rulings and choices. Additional pool tests include
  the actual WPA Blackball rack pattern, playing away from touching balls,
  free-shot continuation, off-table ten, Cutthroat revival and simultaneous
  empty-group draw. Pyramid also tests selected penalty identity, partial
  rerack conservation and an actual dynamic-cue simulation.
- `variants_integration_test.rb`, `competition_model_test.rb`,
  `competition_setup_test.rb`: declared options, action validation,
  serialization and reconstruction through the game model.
- `physics_test.rb`, `aiming_test.rb`, `referee_edges_test.rb`,
  `shot_candidates_test.rb`: geometry, physical contacts, legal aiming,
  referee boundaries and finite proposal generation.
- `object_prediction_test.rb`, `competition_native_test.rb`,
  `variants_native_test.rb`, `native_input_test.rb`, `short_feedback_test.rb`, `aim_audio_test.rb`:
  native bindings, short readouts, local drafts, no-write predictions,
  waveform/volume and bounded voices.
- `runner_test.rb`, `competition_runner_test.rb`: actual ordinary bot
  executor writes and acknowledgements against the native endpoint fixture.
  `localization_test.rb` checks binary-source language runtimes.
  `variants_integration_test.rb` exercises the active executor in all twelve
  new disciplines; `timed_english_test.rb` checks authenticated clock
  boundaries, in-flight simulation and executor expiry. Table profiles
  have actual tight-pocket admission checks in `table_profiles_test.rb`.

Targeted discipline tests run through MCP and retain first failures
separately from corrected results. A model pass is not a native modal,
audible playback, live-server or full-match result. Earlier live DEV
evidence includes a private 8-ball table with a human and bot, two shots
and the return to the human's turn. It establishes neither a completed
match nor the new disciplines on different computers. Native sound handles
and speech delivery were inspected without a hardware listening assessment.

Remaining verification includes full matches on separate computers,
reconnection, host replacement, saved-match reconstruction in those live
conditions, and calibration against physical equipment/player feedback.
Named position files, guided lessons, multi-shot comparisons, exhaustive
bank/combination tactics, cue profiles and continuous rolling sounds that track ball movement
from the broader prompt remain future work. Do not package, publish or
change the release version as part of these source checks.

On 13 November 2026, the updated source was loaded into ELTEN Dev from the
persisted `power-games-source` entry. The running client reported all sixteen
discipline choices and twenty-three rule chapters; its native Polish table
form exposed the new choices and the social-round setting. No game executor
was active during reload. A single private social-table creation attempt
returned to the menu while ELTEN logged invalid encrypted responses containing
HTML and rate-limit text. One bounded readback also failed with the expected
network error; no local room/session was attached. Creation was not repeated,
and no new live round is claimed. The newly added variants' successful bot,
modal and replay checks use the native endpoint fixtures through ELTEN MCP.

The later social-default/pot-score/HRTF change was also loaded into ELTEN Dev.
The untouched native creation form selected `Bilard towarzyski` automatically,
the Polish rulebook opened with its social-play introduction, and the source
entry remained enabled for startup. Native left/right probes opened both the
aiming tone and the collision asset with HRTF enabled; their directions were
approximately `[-0.776, 0, -0.630]` and `[0.776, 0, -0.630]`. Temporary probes
were closed. This confirms native effect creation and playback requests,
not a subjective headphone calibration or a new online match.
These probes describe the earlier HRTF-aiming implementation. The current
aiming tones use the central path described above; contact HRTF remains.

The aiming-tone follow-up was loaded into ELTEN Dev through MCP. Native
keyboard frames exercised an initial arrow press and two repeats with HRTF
still enabled in preferences. Each produced nonzero PCM captured by the
host's per-sound recording API; a pocket produced a fourth tone, and aiming
at a cushion stopped it. The probes made no game writes and released all
temporary voices. The untouched creation form selected Social billiards
and the nine-ball diamond. This verifies the native output path, not
subjective audibility or headphone calibration.
