# Ordinary native team match trial

Scope: the explicitly invoked developer pilot described below. Its entry,
coordination and verification limits are not a substitute for the
[current public tournament flow](TOURNAMENT_SERVER_INTEGRATION.md).

The owned developer server trial can bind one ordinary native game to a fixture
between two fixed teams. It uses the existing append-only plan-document table;
it is an explicitly operated trial with a trusted result author, not a global
dispatcher or a server-authoritative result service.

`OrdinaryTeamPlayers` validates the complete membership against the roster and
the selected fixture, then asks the game's existing team contract to validate
its size, options and native seat template. It does not select games by ID.
The first leg uses the planned team sides; a return leg swaps the sides while
preserving each team's members. The first physical seat determines the native
table creator and authenticated binding/result document author.

The binding stores the prepared options and canonical account/team/seat rows.
Starting requires the current source, exact participant accounts and planned
seat template. Native usernames retain their current spelling. Only the saved
team-player spelling is canonicalized for result option comparison; team seats,
other options and planned memberships must still agree. The existing game
executor and history exporter produce the result. The receipt contains team IDs
as participants/winners/small-score keys; the shared view maps them to member
names. A cold client verifies binding and receipt before computing 2/1/0.

The ordinary pilot still excludes private-table-only variants. Its shared
sporting phases now support knockout win series; see
[the phase trial](TOURNAMENT_PHASE_TRIAL.md). Native games own their rules and private phases.
There are no automatic invitations, readiness changes, global reservations,
timers or additional game schedulers in this path. The result creator must be
online to export the finished history. Multi-computer atomic coordination and
server verification remain separate requirements.

Validation: `ordinary_team_match_test.rb` runs four native clients through
completed Domino first and return fixtures with private deals driven by each
client's existing executor. It checks creator/seat changes, authenticated shared
receipts, team small scores, cold standings, wrong participant/seat rejection,
individual-winner receipt rejection and source-generation races.
`team_binding_pilot_test.rb` additionally checks actual native entry for Spades
teams of two and three, immutable input and duplicate membership rejection;
it does not claim completed Spades matches. Native shared-view tests cover all
five UI languages.
