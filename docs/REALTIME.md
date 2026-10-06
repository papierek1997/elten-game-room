# Real-time games

Pong and Audio Ball have their own client lifecycle (`session_runner? false`).
`Channel` and `EventChannel` share the Communications connection, queues,
ping and delivery. The game client is responsible for physics, resetting its
own fields and transition legality. LiveSessions stores the table, game start
and durable outcomes.

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

## Pauses, timers and presentation

The timer uses the native `FormTimer` lifecycle with the match-cadence gate
described in [HOST_API.md](HOST_API.md). It does not catch up on missed frames.
A ready important action does not wait for the next periodic packet or frame.

Pong's serving-pair announcement is ordinary speech. The end of speech
synthesis is not a readiness barrier. After a point, the score schedule and
the usual 2.7 s preparation period apply; a late announcement does not start
another countdown. Network readiness is still required. Verification includes
a synthesizer that never returns the final index, as well as interrupted speech.

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
