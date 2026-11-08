# Dice poker and Liar's dice

Both games use the ordinary LiveSessions game/action/replay path, shared
SessionRunner, bot coordinator, history, context help and sound output. No
separate scheduler or UI loop is introduced. Both support 2–8 seats.

## Dice poker

Five public six-sided dice; choose two or three throws and 1–20 rounds.
The default is three throws, three rounds, sixes high, with straights.
Hands descend: five equal, four equal, full house, straight, three equal,
two pairs, pair, high die. Compare repeated faces first, then kickers.
The two straights are 1–5 and 2–6; the latter is higher. Other table variants
omit straights or also make ones aces above sixes. No flush is possible.
An optional opener limit gives later seats at most the throws used by the
round's first player. The opener rotates. These are independent settings.

Sources:

- [GLD Products manual, page 16](https://s7d2.scene7.com/is/content/academy/10584905):
  three throws, retaining dice, sixes as aces, complete ranking with straights.
- [Dice Game Depot rules](https://www.dicegamedepot.com/poker-dice-rules/):
  no-straight variant and ones high.
- [Poker dice rule collection](https://officialpokerrules.com/poker-dice/):
  two-throw variant and alternative conventions.
- [Nordic Dice Games](https://nordicdicegames.com/games/poker-dice):
  the optional opener throw limit.

Power Games awards each round's strongest hand one point. Exact ties each
receive one point; equal final totals draw. This is the declared match format,
when point scoring is selected. The optional chip mode collects ante from every
seat (or their shorter all-in), then runs the shared poker-style auction before
throws and again after all contenders keep their hands. Folded seats skip dice;
all-in seats still throw. Main/side pots follow covered contribution levels and
eligible hand ranks, with tied layers divided in seat order and uncalled excess
refunded. A sole contender wins immediately. Balances plus pot are conserved;
zero balance is permanent elimination only after settlement. The match ends at
the round limit or with one solvent seat. B/R enters a custom raise, C checks
or calls, F folds, A goes all-in. All rolls use native server dice, retaining
the selected values. The existing RollAndScore surface handles dice selection.
Enter rolls; 1–6 select values for reroll, Shift+1–6 keeps them, K stands,
Space reads the dice, S reads scores. No card-hand metadata is used.

## Liar's dice

Choose Classic (no wilds), Red Dead style (no wilds plus exact calls), or
Perudo (wild ones, half/double conversions). Start with 1–5 dice, default five.
The bid covers all cups. A successful bluff challenge removes the bidder's die;
otherwise the challenger loses one. In Red Dead style a successful exact call
removes one die from every opponent; a failed call removes the caller's die.

Perudo cannot ordinarily open on ones. Switch to ones with half the old count,
rounded up; switch back with double plus one. Optional Palifico lasts only the
round immediately following a first loss down to one die, with more than two
survivors. Ones stop being wild. Only players who have declared Palifico may
change the face, using normal numeric increases. Optional Calza can be called
by any living participant except the bidder before the next accepted bid. A
correct call recovers one die up to the initial limit; a wrong call loses one.

Sources:

- [Asmodee Perudo rulebook](https://cdn.svc.asmodee.net/production-asmodeees/uploads/2023/12/perudoclassic_es_rules_compressed.pdf):
  ordinary bids, wild ones, conversions, Palifico and optional Calza.
- [Rockstar game tips reproduced by iRedDead](https://www.ireddead.com/rdr/news/rdr-gaming-tips-be-unpredictable-in-liars-dice):
  the Red Dead Redemption minigame. The original Rockstar page was unavailable.
- [Red Dead walkthrough](https://gamefaqs.gamespot.com/xbox360/957922-red-dead-redemption/faqs/82257):
  corroborates the exact-call outcome.

An ordinary loss starts the next round with the loser, or the next surviving
seat if eliminated. A successful Red Dead exact caller starts next; a successful
Calza uses the last losing seat. There are no chips or copied commercial assets.
B opens the quantity/face form, K challenges, D calls exact, V reads one's own
cup, L reads the bid. The main list shows at most six minimum bids plus calls;
the bot's legal set retains every genuinely legal quantity/face pair.

## Private-roll protocol

1. Every living participant saves a 128-bit secret and nonce through the shared
   HiddenSubmissions vault and publishes its SHA-256 commitment bound to the
   round and seat, preserving authenticated participant replacement and archive
   restore to another table. Vault access remains scoped to the live session.
2. Only after every commitment is accepted, the ordinary elected executor
   publishes one native server seed for that exact round.
3. A domain-separated SHA-256 stream combines that seed with each private
   secret. Rejection of bytes 252–255 maps independent bytes to faces 1–6
   without modulo bias. The public seed alone does not disclose a cup, and
   a participant cannot select its secret after seeing that seed.
4. A challenge fixes the bid and caller. Participants reveal secrets/nonces;
   replay checks the prior commitments, regenerates dice and settles only
   after all living cups are authenticated. Verified receipts drive the
   existing owned-vault cleanup. Retries retain the original envelope.

Commit/reveal values fit the existing 64-byte dialect. Private phase actions
share one executor and are concurrent only inside the same phase and round.
Guest executors disclose only their own secret; a host can control its bots.
Host handover and saving are blocked while secrets are pending. Replacing a
person is blocked only for that person's pending secret. No game-specific
invitation, transfer bypass, transport, polling or global keyboard patch exists.
Use the same profile to retain a pending secret; the model reports missing
data and storage failures. Public replay never stores private values before
the challenge. UI and bot views are separate, bounded, viewer-scoped copies.
The bot uses only its own cup and public counts, with an explicit replay-only
strategy contract. Permanent loss of the final die uses the shared elimination hook.
