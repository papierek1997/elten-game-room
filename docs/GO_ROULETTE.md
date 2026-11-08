# Go and roulette

Both games use the ordinary LiveSessions actions, deterministic replay,
SessionRunner, bot coordinator, shared controls and history. They add no
transport, polling or game-specific executor.

## Go

Two seats; boards 9, 13 or 19 intersections per side. Black starts. Orthogonal
groups share liberties; capture precedes the suicide check. Suicide and any
placement repeating an earlier complete board position are forbidden
(positional superko; passes are exempt).

- Chinese-style area: living stones plus singly enclosed empty regions.
- Territory: empty territory plus captures and agreed dead opponents.
- Atari Go: first capture wins; two passes without a capture draw.

Komi is selectable (0, 0.5, 5.5, 6.5, 7.5). Territory mode is an explicitly
agreed scoring variant, not a claim to implement all official Japanese
life-and-death exceptions. There is no automatic bent-four adjudication.
After two passes players alternate marking entire dead groups or neutral empty
regions (including seki). Changing marks resets approvals; changing dead groups
also resets neutral regions. Two approvals of the same proposal finish play.
Either player may instead resume with the original stones present; the other
seat moves next. Resignation is separate from a numeric score.

Arrows/Enter browse and place/mark. P passes, A agrees, R resumes, Q resigns,
S reads points. Bots use a basic capture/liberty heuristic, not a trained Go
engine. There is no external dependency or engine download.

Sources: [British Go Association's rule comparison](https://www.britgo.org/rules/compare.html),
[BGA rules and scoring agreement](https://www.britgo.org/rules/agarules.html),
[BGA interpretation of disputes](https://www.britgo.org/rules/bgainterpretation.html),
[Atari Go overview](https://www.classic.game/go/terms/atari-go).
The chosen positional-superko convention and agreed territorial scoring are
documented deviations, not silently substituted official tournament rules.

## Roulette

Casino tables allow 1–8 seats; social tables require 2–8. Bets use whole virtual
chips, balances use exact integer half-chip units. Each player may add multiple
bets, clear them or finish betting. All players finish before a single native
server draw (37 or 38 outcomes). Casino spins are automatic; the social spinner
rotates among solvent seats and explicitly spins. Zero/double zero are outside
all even-money groups.

Wheels: European single zero, American 0/00, French single zero with la partage
(half of even-money stakes returned on zero). Standard number, split, street,
trio, corner, six-line, dozen, column and outside bets are generated from the
layout. American first-five pays 6:1. Profit odds are otherwise 35/17/11/8/5/2/1
to one; casino returns include the original stake. En prison, neighbour and
announced sector bets are not offered.

The casino has a virtual bank, not a bank financed by another player. Social
mode is the Power Games house format: nominal gross casino returns weight
shares of the whole players' pool; they are not guaranteed payouts. If nobody
wins, all stakes are refunded. Integer division leaves at most one half-chip
per winning seat; remainder follows the round's seat order. Total player chips
are conserved. The match ends at its spin limit or when the mode lacks enough
solvent players. Highest balance wins; tied maxima draw. A half-chip balance
alone cannot fund a whole-chip bet. Each individual bet is bounded at one
billion chips to keep the native event representation bounded.

B opens the shared choice/amount form; the list offers quick bets up to ten
chips. R finishes betting, C clears, V reads bets, S balances; Space spins in
social mode. F1 and Ctrl+F1 use the common help/rules controls.

Payout source: [Singapore Gambling Regulatory Authority, RWS Roulette v2](https://www.gra.gov.sg/docs/default-source/game-rules/rws/roulette-games/rws_roulette_v2.pdf?sfvrsn=9f3ff898_3)
(the indexed payout table was readable; direct PDF retrieval required JavaScript),
corroborated by [New Jersey roulette regulations](https://www.nj.gov/oag/ge/docs/Regulations/CHAPTER69F.pdf).
The two local sound effects and their edits are documented in
[ROULETTE-SOUNDS.txt](../LICENSES/ROULETTE-SOUNDS.txt).

Targeted checks: `test/games/go/`, `test/games/roulette/`,
`added_games_runner_test.rb`, `added_games_surfaces_test.rb`, plus explicit
Go/roulette model-contract fixtures. Tests run via the ELTEN MCP developer
endpoint, without NVDA automation.
