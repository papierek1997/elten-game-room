# Real-time games

Pong and Audio Ball have their own client lifecycle for physics and input.
They also use the shared `GameRoomSessionRunner` (`session_runner? true`) for
durable model events and tournament presence; `tournament_execution_kind`
identifies their separate real-time execution. The runner does not simulate
the ball or run a second real-time bot loop. `Channel` and `EventChannel`
share the Communications connection, queues, ping and delivery. The game
client is responsible for physics, resetting its own fields and transition
legality. LiveSessions stores the table, game start and durable outcomes.

A background-capable client may be created by an active covering UI before its
game view is visible again. `attach_view` must adopt the current UI thread for
the client's own coverage checks as well as attach its progress driver. Retain
the ongoing practice/game, not the old UI owner. Test both return-to-view input
presentation and suppression behind a different form; an isolated progress
driver test cannot prove the client's separate presentation gate is correct.
Regression: `test/games/mania_pisania/reattach_owner_native_test.rb`.

## Action path and authority

1. The active game field accepts fresh input; the engine validates the transition.
2. An accepted action goes straight to a bounded background send queue.
3. Communications broadcasts it to participants without an extra hop through
   the table host when the sender has authority to decide the outcome.
4. Before applying and presenting it, the recipient checks the authenticated
   sender, seat, match, generation, ordering and duplicates.
5. The table host reconciles the point with all required human participants.
   Only matching acknowledgements permit a point-presentation event. The score
   and game end are committed through the normal `action_for`, repository and
   replay path.

In Pong, a human player determines their own serve, hit and miss. The table
host runs the bots, including when observing; it does not take over human
paddles. Replaceable positions and snapshots have a separate path coordinated
by the table host. A remote observer reconstructs a full snapshot after checking
the sender and epoch; it does not try to replay from scratch a history of hits
that it never received. [Audio Ball](AUDIO_BALL.md) describes its own transitions
and the flight recipient's authority to determine the defense outcome.

Important actions require full delivery acknowledgement. A temporarily absent
recipient is not removed from the requirements. Positions may retain only the
latest value; actions must not be lost when packets are coalesced. Waiting for
the network or disk does not belong in the UI frame. A new game creates a new
client; old tasks, channel closures and repeated invitations must not disrupt
the new connection. Reconnect restores ping registration and channel settings
without requiring Enter.

Current session capacity is not a bound on historical account names. Invitation
retry/order metadata follows the current Power Games roster. Sequence watermarks
must instead survive departure and return within an epoch: a delayed authenticated
packet can still arrive after rejoining. Each lane remembers at most 256 account
names; a new 257th name requests the ordinary generation-safe reconnect before
admission. Do not prune replay authority on leave or replace name authorization
with an unproven current-native-participant-ID gate: the host can decrypt and ACK
a valid sender before its local participant list catches up. Preserve current
sender, match/epoch, sequence and delivery checks during recovery. Regression:
`test/realtime/channel_roster_history_test.rb`.

Pong's Inferno difficulty adds `-inferno-1` to its existing event dialect,
including mixed and doubles matches. Earlier clients normalize an unknown
difficulty to Normal and cannot simulate this ball speed; their invitations
must not pass the channel gate. Levels 1–6 retain their existing dialects and
physics profiles. Custom and unlimited point targets keep their independent
`-targets-2` capability suffix.

## Pauses, timers and presentation

The timer uses the native `FormTimer` lifecycle with the match-cadence gate
described in [HOST_API.md](HOST_API.md). It does not catch up on missed frames.
A ready important action does not wait for the next periodic packet or frame.

Pong's serving-pair announcement is ordinary speech. The end of speech
synthesis is not a readiness barrier. After a point, the score schedule and
the usual 2.7 s preparation period apply; a late announcement does not start
another countdown. Network readiness is still required. Verification includes
a synthesizer that never returns the final index, as well as interrupted speech.

Automatic notices, including the serve warning, use `announce_progress` rather
than direct speech. This applies the shared background-speech preference and
keeps an enabled background notice from interrupting the foreground reader.
Suppressing presentation never cancels the warning deadline or queues speech
to be replayed on return.

Agreed point presentation may precede the durable write. It cannot change the
score by itself or repeat the effect after the later write. A connection pause
stops the game clock; replay does not treat an unconfirmed rally as a point.
Help and settings respect input blocking and key-release handling.

## P2P and measurements

Optional full P2P uses the native `p2p: :full` and
`p2p_participants_limit`. It is off by default; the limit is 8 participants,
and 0 means no limit. Observers count toward the limit; bot seats do not.
Without a direct connection, transport stays on the relay. Game Room does not
change ELTEN's global P2P consent. `routing: :peers` specifies recipients;
it does not prove that a physical direct connection exists.

Ctrl+F4 distinguishes HTTP, UDP to the relay and RTT for individual P2P
participants. The path state comes from `Session#p2p_status`, not the table
options. Expired RTT is not a current measurement; mixed connections require
separate descriptions. Reading the status does not send probes or start
connections or callbacks.

Measure HTTP, relay RTT, queues/UI, action application and durable writes
separately. Do not subtract raw clocks from different computers. Scenarios
should cover humans, bots, an observing table host, replacements, rematches,
background operation, reconnect, loss, duplication and reordering. Four
processes on one computer are not a substitute for different network links.
Regression tests are in `test/realtime/`, `test/games/axel_pong/` and
`test/games/audio_ball/`.
