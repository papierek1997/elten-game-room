# Blackjack games

`blackjack` and `blackjack_dice` are separate, game-owned models registered in
`games/catalog.rb`. Both use ordinary LiveSessions tables, accepted-event replay,
the shared session runner, shared surfaces and the existing bot executor.
No server schema changes or new backend are required.

## Card game

Two to six players compete against an automatic dealer. Table options select
Simple (hit/stand) or Extended (also double and one split), rounds (1–100),
initial chips (10–10000) and a positive opening contribution not exceeding initial chips.
Defaults: Simple, ten rounds, 100 chips and a stake of ten.

Before every deal, the standard runner writes the forced opening contributions:
the configured amount from every active player, capped at their available balance.
Players then check/call, raise, fold or go all-in. C checks/calls, F folds, A goes
all-in, and R or B enters a custom raise increment (plus any outstanding call).
The shared game-owned auction follows Poker's full-raise reopening rule and
bounded candidate lists. No cards exist until betting closes; the executor then
requests the deal's server seed. Folded players lose their paid contribution;
remaining players face the dealer on their actual hand stakes. Doubling and
splitting use that stake. No second executor or UI input loop is introduced.

Each round shuffles six fresh decks using one authenticated server seed.
Physical IDs combine deck index and rank/suit. Hands keep acquisition order and
an owner/round/hand epoch through the shared card-hand surface. Cards themselves
have no play action; decisions belong to a separate actions zone.

Aces count 1/11. The dealer stands on all 17s. A natural is an unsplit original
two-card 21. Naturals pay 3:2, ordinary wins 1:1, equal surviving totals push,
and player busts lose immediately. Historical games use integer half-chip units;
new auctions retain rational half-chip units when a short fractional all-in wins
a 3:2 payout, avoiding loss of quarter chips or smaller fractions. Dyadic payment
values use a compact numerator and power-of-two exponent within the native
64-character event limit. In Extended, doubling takes exactly one card
and ends that hand. Only matching ranks split; no resplitting or doubling after
splitting. Split aces take one card each and stop. No insurance or surrender.

New auctions allow any positive balance to enter a short all-in. Final bankrolls
determine the winner, with a draw for tied highest balances. The dealer is not
a participant or a selectable controller. Automatic deals and settlement pass
through `action_for` and the standard runner, including a spectator host.
New ordinary starts record `blackjack_betting_version: 2`. Ordinary replays
without it retain their original fixed-stake rules; version 1 retains individual
pre-deal bets. A tournament binding without an explicit version uses the same
current auction as a new table without changing the binding's option identity.

Player cards are public, as in the referenced face-up rules. The ordinary UI
conceals the dealer's hole card until the dealer event; bot observations exclude
that card and the future deck. The shared deterministic seed is **not secrecy
against a modified client**, including in tournaments. This is a virtual-chip
game and does not use the tournament private-deal protocol.

After an authenticated tournament departure, an unsettled round is dealt
again for the remaining players. All unsettled contributions are returned,
including an extra stake from a split or double. Completed rounds remain
scored. If the game cannot continue, the tournament uses its standard
walkover boundary and the last completed score checkpoint.

## Social card variant

The social variant has no house hand: everyone plays for the shared pot, and
the dealing seat rotates among surviving participants. After ante and auction,
the human dealing player presses D (bots deal through the same action path).
The dealer acts last. Only hit/stand decisions are offered: no split, double or
natural payout bonus. Each covered pot layer goes to the highest eligible total
not exceeding 21, with ties split in seat order. All-bust layers are refunded.
Chip supply is conserved; a lone contender wins without a deal. New social
sessions require betting version 2. Earlier casino sessions keep their markers.

## Dice game

Two to eight players choose Two dice (two below 16, one from 16) or One die
(one throughout), and a target of 1–100 points, default ten. Players roll or,
after the first roll, stand. Exactly 21 and busts automatically end the turn.

After all seats have played, a unique highest total up to 21 earns one point,
or two for 21. Tied leaders, including tied 21s, and all-bust rounds earn none.
The starting seat rotates. The first player reaching the target wins.
The one-die option deliberately uses this match scoring instead of a playoff.
Round busts are not permanent elimination. Every roll requests the appropriate
number of native six-sided dice and validates the resulting event shape.

The optional Virtual chips settlement adds initial balances, an opening
contribution and a round limit. New starts use the same version 2 auction as
cards, before any dice. Main and side pots follow contribution levels, so a
short all-in can win only its covered layers. Each layer goes to its highest
eligible total up to 21, sharing tied maxima in round seat order. Uncalled
excesses and layers without an eligible non-bust result are refunded to their
contributors. One remaining contender wins without rolling. Exactly 21 has no
additional chip bonus. Total chips, including the current pot, are conserved.
Zero balance means elimination only after settlement. The match ends at the
round limit or when fewer than two players retain chips; highest balances win,
with a draw for a tied maximum. Point-mode options keep their original canonical
representation and historical replay contracts. Chip sessions without a betting
version retain the earlier single-setter common-stake rules.

## Sources and local verification

- [Bicycle: Blackjack](https://bicyclecards.com/how-to-play/blackjack/)
- [Pagat: Blackjack](https://www.pagat.com/banking/blackjack.html)
- Family Games Treasurehouse, *25 Family Dice Games* (2009), p. 22,
  [Blackjack Dice](https://www.party2geaux.com/wp-content/uploads/2017/12/dice-rules.pdf).
  The indexed rule text was available; the PDF endpoint returned HTTP 403.
- [Dice-play: Twenty One](https://dice-play.com/Games/TwentyOne.htm)

Rules and interface text cover EN, PL, CS, ES and RU through the existing
rulebook compiler and Gettext catalogs. `test/games/blackjack/` owns the targeted
regressions. Definition-only checks can also run in the loaded program namespace
through MCP `program_eval`. The shuffle simulation runs in a separate process,
never by changing Array in the live client. Live trials must use normal table
creation and the active executor; modifying a replay is not a live match test.
