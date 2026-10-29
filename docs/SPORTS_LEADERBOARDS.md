# Axel Pong and Audio Ball player statistics

Both games opt into the shared player-statistics capability through
`GameRoomSportsRankings::Game`. Their existing tournament result and goal
exports supply the outcome; this module does not run a second scorekeeper.
Singles and doubles are separate. Each teammate receives the full team score.
Audio Ball exports goals across all accepted sets, not set wins or only the
last set. Only a terminal human-only roster is eligible; an earlier bot does
not disqualify it. Later replacements cannot change the winning-point roster.

## Identity and persistence

Ordinary results use the existing statistical match identity; rematches get a
new identity. Tournament results use the canonical publication, schedule,
fixture and leg. The ordinary observer skips tournament-bound sessions: the
confirmed result/administrative receipt supplies that outcome exactly once.
An all-zero settlement or a draw does not create a win. Technical forfeits use
the same goal scores as the tournament, with no separately invented target.
Legacy games missing an identity or score cannot acquire guessed results.

`sports_match_results` is a public append-only table containing one whole
match per report. Multiple clients can race to report the same match. The
lowest server row ID is canonical; retries acknowledge that existing result.
The original date stays canonical if append acknowledgement and server replay
timestamps differ. Different participants, outcome, mode or goal scores are
conflicts, not another match. These are client-reported results, not an
anti-cheat or a server-authoritative game implementation.

Terminal callbacks copy bounded scalar records into memory. The existing
analytics worker framework persists `sports-rankings-pending.json` and uploads
it, with account/runtime guards, atomic storage, bounded passes and the same
retry policy. No result request or file write is made during an ongoing match.
A statistics failure must not stop play or invalidate a confirmed tournament
result. Player statistics use the same `analytics_enabled?` development-mode
opt-out as general statistics: no service/queue construction, collection,
reading or upload while the host's actual `$developer_mode` is true, even
for the application author. Captured observers and workers recheck that
predicate. Previously queued normal-mode results remain intact and can be
sent after normal mode resumes; development-mode games are not queued for later.

## Navigation and presentation

These games do not opt into leaderboards. The shared Statistics menu offers
General for the existing application activity screen, followed by games with
`supports_player_statistics?`. Each game supplies its own client through
`build_player_statistics_client`; there is no game-ID branch in the menu.
The sports client offers singles/doubles and seven read-only counters: matches
played, wins, losses, match balance, goals scored, goals conceded and goal
balance. There are no ranking points, weights or places. The store returns
unweighted totals in username order, not sporting order.

Below the counters, an opponents table lists everyone the shown player met
(an opposing pair in doubles; partners are not opponents), alphabetically,
with matches played, won and lost in the selected period; opponents not met
in that period are omitted. Enter opens that head-to-head for every period.
`Store#personal` replays the same canonical history through the pure
`GameRoomSportsRankings::Personal`, whose periods follow the screen's order.
The report and head-to-head reads share the bounded cache as separate scopes.

Dates use Europe/Warsaw. Seven- and thirty-day periods include today; the
half-year and year are calendar-month intervals ending today. The initial
view shows the signed-in player's whole recorded history. Period selection,
Choose player, My statistics and Refresh update the same text view and
opponents table.

Native background tasks keep reads and Refresh off the UI thread. Each read
rechecks the schema. Snapshots are bounded by a highest server ID; data and
canonical-group pagination continue after short nonempty pages. Manual Refresh
and every attempted write invalidate the 15-second/4096-match report cache.
Closing or changing accounts discards pending UI results without waiting on I/O.
While a request is pending, only the latest period/player selection is retained;
an older response must not replace it or move focus.

The existing table, result format, acknowledgement keys and pending-file path
remain unchanged. Existing data and unsent results need no migration or reset.
The internal `GameRoomSportsRankings` namespace and file names are retained
to avoid changing persistence and runtime identities merely for terminology.
Do not change stamp protection, notifications or file quotas for this UI change.
Tests: `test/statistics/sports_rankings_*_test.rb` and
`test/statistics/sports_statistics_screen_test.rb`, plus
`test/tournaments/sports_rankings_test.rb`.
