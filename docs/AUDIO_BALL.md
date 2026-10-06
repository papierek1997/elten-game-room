# Audio Ball

The `audio_ball` game supports two players (humans or bots); the owner may
observe. The original implementation is by `budyn1211` (PR #13).
The shared transport is described in [REALTIME.md](REALTIME.md), and sound previews
in [AUDIO_TUTORIAL.md](AUDIO_TUTORIAL.md).

## Controls and rules

- Up arrow / W: select lane one, or make the first shot after preparation.
- Left arrow / D: select lane two, or make the second shot after preparation.
- Down arrow / S: select lane three, or make the third shot after preparation.
- Right arrow / A: prepare to serve or hit after a defense.
- Shift+S: read both players' points and won sets.
- T: read the server and connection status.
- Ctrl+W: warn the opponent who is holding the ball.
- Ctrl+P: choose the local listening side and sound pack before or during a match.

The A/D mapping is deliberately nonstandard: Left/D and preparation Right/A.
Game keys operate only in the playfield, not chat, help or another application.
Held keys are not queued across pauses, focus changes or modal settings.

The court is 25 steps wide and has three shot lanes. Every new opponent hit
requires a NEW fresh defensive press for that incoming flight, even when the
opponent repeats the previous shot type. An early tap after the hit persists
after release until contact within the final two steps; no second timed press
or held key is required. Without a fresh choice for that flight, the ball is
missed. A previous defense, a pre-hit choice, a still-held key or the player's
own attack cannot arm the next defense. Only the latest accepted choice for
the current flight decides contact. Wrong choices can be corrected before the
ball passes. Arming is scoped to the flight, including bot hits inside a frame
and remote events, not merely to a durable point or visual surface instance.
An already armed defense survives chat/settings for the SAME flight; UI keys
cannot arm another one. Real network pause freezes physics. Preparation and
each attack still require separate fresh presses. Bots obey the same rule.

Holding the ball has no time limit until the opponent requests a warning.
The holder then has ten active seconds to hit. Preparing does not cancel or
restart the countdown. A repeated warning does not extend it. Expiry awards
the opponent a point. Only the holder's controller resolves that timeout;
other computers do not compare wall clocks to invent penalties.

Very easy starts at 4.0 seconds per full flight, Easy at 2.2, Normal (the
default) at 1.5, Hard at 0.9 and Very hard at 0.6. Every later shot increases
speed by 5% at every level. Reaction/hold delays and bot error chances decrease
at each level. `Difficulty::PROFILES` is the shared source of truth for table
choices, physics and bot parameters. Flight duration is
divided by the speed multiplier, rather than reduced by that percentage.
Each new rally resets the speed; there is no arbitrary gameplay speed floor.

The first server is randomly drawn once through a durable event. Service
changes after every two completed points, including deuce and across sets.
Every set requires at least 7 points and a two-point lead. The table selects
one, two or three won sets. Between sets there is a five-second pause, followed
by the next ordinal set announcement. Ordinary points use the Pong-style
5.7-second restart pause for recorded score presentation, measured from the
agreed goal preview rather than starting over at the durable write. A write
longer than the initial three seconds still leaves 2.7 seconds for the score.
The five-second set break continues to start at the durable result. Speech never acts
as a network-readiness barrier.

Creation uses the existing privacy control, followed by mode (Classic only),
difficulty and sets to win. There is no 7/11 choice and no generic bot-delay
option for this real-time game. Unfinished matches cannot be saved.

## Audio and speech

By default the listener is on the right and the opponent on the left. Incoming
flights move left to right, outgoing flights right to left. Ctrl+P opens local
settings, storing `audio_ball.listening_side` as `right` or `left` in the existing
settings JSON. Choosing left mirrors both flight and preparation, including
an already playing sound, without restarting the stream or changing physics,
player indexes or scores. Each shot has a distinct loop; the original three
are mono. Preparation and successful defence have one-shot cues. Sound
position and game volume update without restarting. The optional Audiodisc
pack replaces the three loops, preparation, defence and goal effect, retaining
the supplied stereo channels. Both packs use the same gameplay event path.

The personal dialog continues realtime ticks and networking while it is open.
Gameplay commands and warnings are blocked during the dialog; queued and held
navigation keys are cleared on exit, including exceptions, until released.

Goal effects, goal voices, the score introduction and numbers reuse Axel Pong
assets and its announcement sequencing. Recorded numbers cover 0 through 21;
if either score is outside that range or a required recording is missing,
Elten speech reads the complete own-first score. Observers use table order.
Pong's personal announcer-volume preference does not affect Audio Ball; the
shared Game Room game-volume controls still apply to all these recordings.
Set, warning and server information remains synthesized; queued announcements
are not cut by rally reset, view detach or the final replay. Ticking continues
on the finished screen; close cancels and releases resources. No speech
completion barrier controls gameplay. English and Polish strings are included,
with `stop: false` and `break_sequence: false` for synthesized messages.
Accepted-point announcements are deduplicated across frames and reconnections.
Provenance, transformations and license status of current recordings are in
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

## Runtime ownership and event route

1. After an opponent hit, a fresh playfield direction arms a local lane for
   that incoming flight only. Frame contact passes the current-flight choice
   to the existing Engine defense path. Prepare and attack presses still use
   the ordinary Engine transitions.
2. Only accepted prepare, hit, defend or miss transitions enter EventChannel.
3. The authenticated actor sends directly through the shared Communications
   relay to the other participants (`audio-ball-peer-2`, peer routing).
4. Receivers check match, generation, rally, side and transition order before
   applying the event and updating audio. Only the recipient of a flight
   decides its timely defense or miss. The table owner controls bot sides,
   never remote human input merely because a bot is present.
5. Replaceable status/snapshots retain the existing owner-star route. The
   owner waits for all human participants to agree on the goal and turn.
6. The agreed value enters `context_data`, then the normal GameScreen
   automatic-action path, `action_for`, GameRepository and durable replay.
   The client never writes scores directly.
7. Once everyone agrees, the owner sends a reliable `point` presentation event.
   Receivers authenticate the owner and match the current rally, turn and local
   goal. Its effect plays once without waiting for LiveSessions; scores, set and
   match results remain durable-only. Repeated confirmations do not replay it.

T distinguishes waiting for a durable point, ordinary point/set breaks, and
connection/readiness waits. These statuses are not automatic speech.

The durable start and point records are owner-authored and reject duplicates,
wrong sequence and foreign authors. This is not an independent anti-cheat
proof against a malicious owner. Reliable buffers are bounded. Missing or
stale participants pause clocks; recovery discards unconfirmed play but keeps
an already agreed pending point. A participant rejoining the same session after
transport failure requests an owner-authorized new generation and stays paused
until it is agreed; it cannot silently keep a lost warning only on its own copy.
A spectator instead resumes after validating and restoring a fresh owner
snapshot, without resetting the players' match. Late spectators restore the
current snapshot rather than waiting for unavailable historical transitions.

## Local sound packs

Ctrl+P saves `audio_ball.sound_pack` (`default` / `audiodisc`) in local
settings; cancel preserves the current pack and malformed values use default.
This is not a table option. Switching packs does not restart score announcements
or send game events. Managed streams are cached outside the frame loop and
released on close. Only an accepted, deduplicated defense plays the stop cue.

| Cue | Default ID | Audiodisc ID |
| --- | --- | --- |
| Up | audio_ball_up | audio_ball_audiodisc_up |
| Left | audio_ball_left | audio_ball_audiodisc_center |
| Down | audio_ball_down | audio_ball_audiodisc_down |
| Prepare | audio_ball_prepare | audio_ball_audiodisc_ready |
| Defense | audio_ball_stopped | audio_ball_audiodisc_stop |
| Goal | Pong effect variants | audio_ball_audiodisc_goal |

## Ordered keyboard input and reload

The local Keyboard observer attaches at most 32 ordered game-key events,
modifiers and the held state of the same sample to the native result.
It neither rewrites host fields nor records chat. Release/repress is a new
input; autorepeat and a second down without up are not. Focus, modifiers,
help and suppression still block gameplay input. A backend without ordered
events uses a limited fallback. Defense remains scoped to the incoming flight.

`Keyboard.install` rebinds the existing host extension to the current runtime
on reload, including old boolean installation markers. It does not accumulate
wrappers, retain old closures or replay stale input. Validate old-to-new and
repeated reloads in one process through `test/games/audio_ball/keyboard_reload_test.rb`;
a clean start does not cover this lifecycle. Other Audio Ball regressions are
in the same directory. Native tests require final ELTEN 3.0.4 via
`ELTEN_HOST_SOURCE`; fake sound handles and relay fixtures do not verify
physical audio or multiplayer on different networks.
