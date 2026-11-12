# Private answers and saved games

## Local answer commitments

`ProgramStorage` skips writing unchanged state, including another `discard`
after an entry has been removed. The read–modify–write transaction is coordinated
across screens. The normal file is `hidden_submissions.json`; on an I/O error,
the store tries `hidden_submissions.json.recovery.json` in the same private
application directory. The host resolves and validates the path once per file
for each loaded application. Subsequent reads and writes use that path without
unpacking the installer again. The file contents are not cached. Writes go to
a temporary file, which replaces the destination only after the write has been
closed, just as in the host's native storage.

The snapshot contains an increasing `storage_revision`. Reads choose the newest
complete state, so an old primary file cannot undo a deletion confirmed in the
recovery copy. The next successful primary write replaces the older copy. A file
without a revision has revision 0. Do not delete or truncate the original to
force replacement.

A new answer reaches the game only after a durable write. Previous versions
and nonces remain available for an already accepted commitment. Failure of both
preparation paths returns a controlled error without an event plan. A cleanup
error returns `false` instead of interrupting game progress; the local entry may
remain until the next successful attempt. After both paths fail, writes have a
one-second backoff and a single warning until recovery, without sleeping or
adding another loop.

Coordination covers instances of the same native Program sharing a file within
one process. Separate ELTEN processes writing to one profile are not a supported
multi-writer setup. The local storage format does not change the commit/reveal
protocol or game outcomes.

## Boundaries for changing tables and participants

Transferring the table host role, replacing a player and leaving a table recheck
the private phase at the write boundary, including after the participant
selection dialog. Replacement distinguishes that participant's secret from
other participants' pending commitments. Accepting an invitation uses the same
safeguard as leaving normally.

## Server-private tournament hands

Tournament Mille Bornes, Spades, Bridge, Bouillabaisse, Scopa, Thousand, 3-5-8, 99, Poker, War, Rummy, Makao,
Domino, Mexican Train, Scrabble, Biblios, UNO and Taboo tables advertise
protocol 9 and `private_cards: 1`.
Normal tables use protocol 8 and a public server-generated shuffle seed, retaining
bots, seat replacement and archives. A protocol-9 start cannot omit private mode,
restore an archive or include a bot. Games opt in through `GameRoomPrivateCards`.
Unregistered games have not adopted private pools.
The ordinary tournament service still validates the binding; the native metadata
pointer alone is not authorisation to start or score a tournament match.
The bound tournament service permits one game session per native table; a rematch
uses a new table. Native pools therefore do not carry over to a different match.

The host creates a native range pool with private draws. Each player checks its
range and privacy before the initial deal, then takes their own cards. All accounts
derive the same public card-index mapping, but only the drawing account can fetch
its drawn indexes. Public take records contain counts and opaque draw IDs, not
values or shuffle seeds. Only a native reveal makes a played card public. Cards
passed between accounts are also revealed, because the API cannot transfer a
private receipt. That technical disclosure does not expose hands in the ordinary
UI or change game rules. Never
accept a client packet masquerading as an SDK `server_pool` record.

Normal takes and reveals attach their game command to the native operation, so
there is one write request rather than a separate game-stack push. During an open
safety reaction window only, a normal draw first writes `draw_intent`. That claim
orders the reaction against the irreversible take: a winning safety leaves the
other player's deck untouched. Stable operation IDs reconcile uncertain replies
without consuming another card. All network work stays in the existing worker.

Hands belong to accounts, not to the table host. Rejoining the same live table on
the same account reloads the private values; a new host, including an observer,
cannot fetch them. Player replacement and new-table saves are blocked. The host
role may change without rejecting an in-flight human card operation solely because
the control epoch changed; host-only commands still require the current owner.

Recycling uses a new pool over the public discard pile. Pools that still contain
held cards or undrawn stock must remain; only empty, fully revealed pools are retired. Retirement identities
are retained in replay so they are not repeatedly included in later requests.
Native sessions allow at most 32 simultaneous pools. An unusually long recycled
deal retaining cards from all 32 stops with an explicit message, without deleting
hands or reverting to public draws. A fresh deal retires the previous round's
pools. Ordered-slot games retain receipt order even after revealing all values;
their pools are retired at the next fresh deal rather than during an exchange.
Closing the live table loses the server-private continuation.

`GameRoomPrivateCardGame`, `GameRoomPrivateCardDealing`,
`GameRoomPrivateCardLedger` and `GameRoomPrivateCardDisclosure` reuse the normal
action planner, native transport, replay and session runner. Adapters declare
deal/draw/disclosure boundaries; they do not create another scheduler or queue.
Batch disclosure is limited to values belonging to one native draw. Poker uses
it for showdown and, only when the deck runs out, recycling discarded cards.
Exchanges publish positions, not the names of private discards. Holdem burns
remain private. Folded hands are not revealed at an uncontested finish.

Bridge reveals dummy through the same disclosure path after the opening lead.
The shared `private_event_hand_owner` hook chooses the publicly exposed hand
being played without changing the authenticated actor. The ordinary reducer
still checks declarer and the current seat; dummy's owner, an observer or a
different player cannot play it. At the end of a board, including four opening
passes, authenticated disclosures reconstruct the initial hands and replay every
call and play before scoring. No honours, rubber totals or HCP-reference points
are committed before that audit succeeds. The HCP reference is an estimate,
not a result from another table. Private dealing does not change its algorithm.

`GameRoomPrivateCardSelection` proves a selected packet across several receipts;
`GameRoomPrivateCardPayload` adapts the existing atomic payload format to that
same path. `GameRoomPrivateCardEffects` resumes the original pure rule applicator
with account-owned draws, necessary derived facts or disclosed hands. It does not
commit partial moves, histories or turn changes. Completion messages belong to
the final receipt, so the normal presentation and audio paths see them once.
Fact claims bind the originating event and input index. They authenticate the
account, not the truth of a hidden-hand predicate. Domino publishes a bounded
highest-tile rank for each player to retain the existing starter rule. War's
played face-down battle cards are technically disclosed too; ordinary UI still
keeps them face down. Do not claim those values remain secret from modified clients.

`GameRoomPrivateCardStock` keeps mixed-pool stock as opaque tickets. Scrabble
returns exchanged tiles before drawing, so receiving a returned tile remains
possible. A native public shuffle seed orders the tickets; account-owned pools
provide their private values. An explicitly addressed ticket keeps its original
pool. A normal replacement draw follows the active pool after recycling, not
the exhausted pool that was current when that draw was requested.

Biblios checks the pool on all accounts even though its opening hands are empty.
Gift packets, face-up cards, payments and final scoring use the same Effects
and Disclosure paths. UNO uses them for penalties, choosing a colour, Flip,
No Mercy, hand transfers and scoring. The first non-wild card is drawn after
dealing, as in ordinary UNO. The dealer temporarily owns any skipped wild-card
receipts at the front of the deck. That dealer knows those reserved cards; when
another player draws one, it must be technically disclosed. A 0/7 transfer
discloses the entire transferred hand, but does not add a hand-reveal UI.

A native reveal is irreversible even when its attached game move is rejected,
for example a late UNO interception. The ledger retains this authenticated
evidence in `private_known` separately from accepted use and `private_public`.
A later legal move reuses the evidence through the existing claim path, checking
the receipt owner, card positions and single use. Do not send another native
reveal for the same value: the server acknowledges a repeated reveal without
adding a stack record. Hand and turn changes still occur only for accepted moves.

Fresh rounds retire old pools, but replay still needs earlier public disclosures.
Reconstruct fully revealed, unordered historical draws from the authenticated
log without fetching retired pools. An account checks a derived fact against its
own cards only when those cards are available in that projection. Missing private
history is not evidence of a false claim. Ordered games retain their existing
position proofs rather than treating reveal order as draw order.

Snapshot cache lifetime follows the same evidence boundary on every account,
not only on the host that deletes a retired native pool. Remove cached unordered
draw values once their complete public reveals reconstruct them, and old-round
values only where the existing fresh-deal boundary already skips them. Keep
ordered current-round draws and unrevealed retained Taboo slots. A pool-state
validation cache is redundant past that same fresh-deal boundary, or once its
native remaining count is zero and every observed take is fully public.
This local cleanup performs no pool enumeration
or additional requests and must preserve unseen in-flight draws and replacement
memberships. It does not change native pool retirement or the history limit.

Rules depending on another player's hidden cards cannot be fully validated
immediately. Trick games audit the disclosed round before recording its score.
Bouillabaisse uses this audit at each of its six round boundaries, including
follow-suit validation and all-or-nothing scoring. Scopa uses one private pool
per round: the opening table is drawn publicly and later hands append receipts
from the same pool. Captures depend only on the played card and the public
table, so they do not require claims about the rest of a hidden hand.
Local Poker opening-hand checks remain in place, but are not a server-side
proof of an opening pair. Do not advertise the private-deal feature as complete
validation of hidden-information rules.

This protects unplayed card values from other clients; it is not server-side game
validation or full anti-cheat. A modified account can reveal its own cards, and
an authorised native owner can disrupt its table. Invalid deck counts stop replay
rather than inventing missing cards. Do not describe those limits as guarantees
against collusion, denial of service or modified game rules.

Targeted regressions: `test/transport/*private*test.rb` and
`test/tournaments/ordinary_start_catalog_test.rb`. Live evidence is kept outside
versioned sources; distinguish real network tests from UI/keyboard/audio tests.

## Public server randomness and remaining limits

`GameRoomServerRandom` registers each game's draw commands. The existing writer
attaches the game command to a native random operation; replay verifies the
authenticated metadata and the exact recipe. Shared text and atomic-payload
recipes preserve historical event formats, so ordinary archives remain readable.
Quiz categories/questions and Countries and cities letters use this path too.
The existing offline tournament simulator explicitly advertises `offline?` and
keeps its local-random protocol. Manual event dispatch (`local_view`) alone is
not an offline flag: a real native endpoint must still require server proofs.
Duck Racing uses a fresh native seed for each race action and each roll in Dice
Duel or Risky Dice, in addition to its start seed. Automatic challenge expiry
also receives a fresh seed, so waiting out the timer cannot select a roll
calculated from the already public challenge seed. The seed and command are one
authenticated operation. Challenge replay and bots retain the individual roll
seeds. Old archives without these seeds still use their original RNG sequence.
The published seed does not protect the duck hands or concealed challenge data;
this is fresh public randomness, not private cards or server-side game rules.

Do not expose a secret by substituting a public seed. The current native API
offers account-owned pool receipts, not durable private transfers or a private
draw with replacement. Duck Racing's unlimited, independent card draws cannot
be replaced with a finite deck without changing their distribution. Duck Racing
has therefore not adopted tournament-private cards. Krowa's secret
word and manually placed Battleship fleets retain their existing protocols.
Scientific War has deterministic hands rather than a shuffled deal; its hidden
selection protocol is unchanged. Quiz questions and correct answers remain in
the distributed content pack: server question selection does not hide them.

### Selectively shared Taboo phrases

Tournament Taboo uses the same native pool ledger and executor. Only the
describer draws a phrase. The game projects the current opposing team as the
permitted recipients; the shared snapshot worker sends that draw through native
addressed messages. Neither a request packet nor being the host grants access.
Public state contains opaque turn slots, not phrase indexes or a reconstructible
deck. A current guesser, including a host, cannot fetch the describer's draw.

The describer reveals all drawn phrases after the turn. Review and approval wait
for the authenticated native reveals. The shared messages are presentation data,
not proof of an answer or score. A modified describer can still lie or collude;
this mechanism is not a server referee. A missing account may prevent review
until it returns. A cold return requests the same phrase again, not another draw.
Previous pools remain readable until their phrases are revealed, including when
a turn crosses a reshuffle. Ordinary Taboo and its saved games are unchanged.

## Tournament Mahjong

Tournament Mahjong table variants use the same native private-pool ledger,
dealing and disclosure pipeline. Wall positions are assigned lazily; no host
receives a private copy of the future wall or dead wall. Public indicators use
public pool takes. A complete known-card hand audit gates score commitment;
see [MAHJONG.md](MAHJONG.md#current-livesessions-integration). Ordinary Mahjong
and its archives still use the public server-seed path.

## Account archive

`AccountSavedGames` saves the standard history through the account's private
files. `saved_game_schema_version` versions the format. A game defines
`save_game_error` for unsafe phases or disables saving through
`supports_saved_games?`. `restored_event_value` restores controller names in
specific event fields; do not replace arbitrary history text.

Closing the table and replacing participants require a confirmed archive
write. An uncertain result keeps the freeze in place. Releasing the freeze
requires the same game, the current table host and confirmation of the
operation's own write boundary; it does not unfreeze a newer operation.

The application consumes a saved game immediately after a confirmed restore,
not when creating the waiting table and not at the end of the resumed game.
The complete history and private data must be restored before deleting the
account resource. Cancellation, missing players and an unconfirmed restore
leave it intact. Storage/transport primitives remain non-consuming; this is
the shared application's resume policy. A deletion failure must not undo or
restart the accepted game: report it separately so the user can remove the
remaining saved copy. The private-file adapter reconciles a lost delete reply.

Regression tests for answer storage and archives are in `test/persistence/`;
private-phase scenarios are also covered by the Quiz, Categories and Battleship
tests.
