# Cash Auction

Bid effects use the existing optional player-seat HRTF policy.
Wheel, ante, question, answer, countdown and chest/gavel effects stay centred.
Discovery and invitation summaries use the selected Quiz language and sets,
through the game's existing notification-option declarations.

Cash Auction (`cash_auction`, Polish name “Awantura o kasę”) is a project
adaptation of the rules requested by the user. It combines simultaneous
all-pay bidding, existing Quiz content and unopened prize chests. This is
not a claim to reproduce an official television rulebook.

## Model and settlement

New games use `auction_rules_version = 5`. The game accepts 2–8 participants,
including bots. Defaults are 10000 starting points, a 100-point ante, a
fixed 5% penalty after three consecutive auctions without a bid, eight
answered questions, three seconds between calls and a 10% chance of a chest
instead of a category/question. Table controls admit starting
points 10–1000000, ante 1–starting points, rounds 8–32,
call intervals 1–5 seconds and chest chances 5–15%.

Every remaining participant pays the ante. Someone unable to pay is
permanently eliminated. An accepted bid is the bidder's total contribution
to this auction, excluding the ante. The reducer deducts only the difference
from that bidder's earlier bid. All bidders pay, and losing does
not refund their contributions. There is no withdrawal action in current games;
the bid editor remains available until the auction closes. All-in is the remaining cash
plus that participant's earlier bid contributions. Every bid, including
all-in, must exceed the current highest offer and cannot exceed that available
total. An accepted all-in ends the auction immediately and awards its question
or unopened chest. Typing the full available total has the same effect as A.

V2 has three calls followed by one final interval before closure. A higher
bid resets the calls. The third call is announced while bidding remains
open, not as text attached to a committed closure. The closing event still
binds the exact bid revision and deadline and cannot overrule a newer bid.
A storage ACK alone is not game acceptance: the shared human-action runner
checks the confirmed local reducer projection before reporting success,
without another poll. Declining to bid requires no action or server event.

For each participant eligible after the ante, an auction without any accepted
bid increments the consecutive non-bidding count. The ante is not a bid.
Any accepted bid resets the count even if its author later loses. At closure, the third consecutive missed
auction deducts 5% of that participant's balance at closure, after the ante,
rounded up to a whole point, and resets the count to zero. A zero balance owes
zero. The rate is fixed, not a table setting; saved `pass_penalty` values are
ignored in v5. The production reducer and bot budget use the same penalty
helper. At a question auction the deduction enters the question pool; at a
chest auction it leaves the game. This applies at timed and immediate all-in
closure. Fixed v1–v4 games retain their recorded flat-penalty rule and options.

The ordinary auction winner answers one four-choice question. A correct
answer receives the whole pool; a wrong answer leaves it to carry over.
A wrong answer with no cash left permanently eliminates the answerer.
There is no answer deadline. Each accepted answer increments the answered
question counter exactly once, whether correct or wrong. A chest auction
instead adds an unopened chest to its winner and preserves the prior question
pool. Since v4, chest antes, bid increments and inactivity penalties are still
deducted from participants but leave the game rather than increasing that pool.
The following question adds only its own payments to the preserved pool.
Chest auctions and empty auctions do not increment the question counter.

The answerer may buy one hint removing two wrong answers. It costs 10% of
their remaining balance, rounded up and at least one point. The button shows
the price; a zero balance cannot buy it. Payment leaves the game, not the
pool. A native seed chooses the surviving wrong answer, so the remaining
positions do not disclose the right choice. Choice IDs stay unchanged when
the list shrinks. Planning and replay reject removed answers, repeated hints
and another player's hint. This is a project adaptation, not the official
TV price: the television presenter negotiates the price of a hint.

After the configured number of questions have been answered, or when at most one active participant
remains,
all owned chests are opened automatically five logical seconds later, including
those belonging to eliminated participants. V3 uses the weighted percentage
settlement below. Historical v2 chooses uniformly from
`[100, 500, 1000, 2500, 5000, 7500, 10000]`. These positive prizes are recorded
separately in `bonus_prizes`, never added to the match score. They cannot
eliminate anyone, revive them or change the winner. V1 keeps its historical
chest outcomes. The maximum surviving
balance wins. At this settlement boundary, no new wheel draw or result is
allowed while any owned chest remains unopened. An exact tie at the highest
surviving balance sets the next
question target to one more accepted answer; all active seats remain eligible.
Chest and empty auctions cannot complete that extra question round. After
the next answer, open any new chests before another comparison, unless the
at-most-one-survivor boundary was reached earlier. No active seats
means a draw. The pool has no final automatic payout to a leader.

The version marker is part of normalized game options. A new ordinary start
uses v5; an already bound tournament match uses its fixed published version.
V3 retains its original pool accounting and percentage chest settlement;
v4 keeps that settlement but separates chest payments from the question pool.
Unmarked historical sessions retain v1, including their original single-pack
identity, defaults, cumulative pass penalties, auction-counted rounds and
earlier bid/all-in transition semantics. Reading or resuming them must not
upgrade their options or reinterpret their accepted events.

## Percentage chests

V3 replaces the separate fixed-value prizes with score adjustments.

Each chest has a 60% chance of a positive change, a 30% chance of a negative
change and a 10% chance of no change. For either nonzero sign, draw the
magnitude with the same decreasing weights:

| Balance change magnitude | Weight |
| --- | ---: |
| 5% | 49 |
| 10% | 36 |
| 15% | 25 |
| 20% | 16 |
| 25% | 9 |
| 30% | 4 |
| 35% | 1 |

The weights total 140 and are the squares of 7 through 1. Thus a particular
positive outcome has probability `0.60 * weight / 140`; its negative counterpart
has probability `0.30 * weight / 140`. The mean change per chest is +3.6% of
the base balance before considering its auction cost.

Use each participant's balance at settlement, before any chest adjustment,
as the common base for all their chests. Sum their signed percentages rather
than compounding them, round the final adjusted balance once to whole points
and do not let it fall below zero. Apply all chest adjustments before choosing
the winner. Opening order must not affect the result; for example, +20% and
-10% on a base of 10000 produce 11000 in either order.

The ordinary executor requests one native `open_chests` seed at
`open_chests_at`, five seconds after the settlement boundary. One accepted
event opens the complete batch in seat order; there is no player readiness,
manual button, per-chest network request or additional timer. The shared
presentation queue speaks the opening announcement, allows one second for that
short cue, plays `auction_chest` once and waits for its handle to finish.
It then reads the contents and adjusted balances, and holds the final result
for four seconds. Cold reconstruction does not replay those effects or pauses.
Eliminated players remain eliminated, even when their chest adjustment is positive.

## Shared Quiz content

`Base::Options#content_pack_game_id` defaults to the game's own ID.
Cash Auction returns `quiz`, with `content_pack_kind == 'quiz'`. This affects
selection and support validation only: language, pack ID, version and
checksum retain their existing pinned meanings. The game does not rewrite
Quiz pack manifests, data or checksums.

The revised `content_pack_ids` multiple-value control selects one to three sets
from one Quiz language. New table defaults check only that language's general
knowledge set; specialist topics stay unchecked. The creator's interface language
chooses the question language, with the existing English fallback when unavailable.
Changing language also selects only its general set. If that set is missing,
leave the checklist empty for the creator to repair rather than selecting a
specialist topic silently. Question-set checklists and their language are not
remembered between new tables; older saved preferences are ignored without
changing another game's preferences. Explicit table/preset selections are retained,
including empty or unavailable choices which must be repaired before submission.
The immutable `content_pack_manifest` pins every selected member with
`id`, `set`, `language`, `version` and `checksum`. Selection and replay validate
the complete pinned combination, rather than replacing it with whichever
packs are currently available. Legacy single-pack fields remain authoritative
for v1, including already fixed v1 publications.

`GameRoomCashAuction::QuestionBank` indexes the selected frozen question rows.
Each integer category identifies one `(pack_id, category name)` pair, sorted
by category name and then pack ID. Equal names from different sets stay separate.
`category_label(id)` returns the bare category; `include_set: true` adds its
one source's title for the wheel announcement. `category_pack_id(id)` exposes
that exact metadata identity. Display labels are prepared once per bank, not
by rescanning the question rows on each replay event. A question stays in the
category's own set, and exhaustion clears only that pair's ledger entries.
No copied question database or process-wide unbounded cache is introduced.

`draw(category:, seed:, used: [])` accepts a native unsigned 128-bit seed and
returns resolver data containing the question ID, integer category, prompt,
shuffled four choices, correct index, pinned source identity and next `used`
ledger. The caller assigns the returned ledger. It never mutates the input.
Questions do not repeat within a category until it is exhausted; exhaustion
clears only that category's IDs. The unique ledger cannot exceed the bank's
question count. `public_view(data)` copies only approved public fields and
excludes the answer key and internal ledger.

Wheel, question, hint and chest randomness use the existing native seed commands
registered for this game. Question randomness is obtained only after the
auction is awarded; the public category draw cannot select its future
question. Cold replay uses the recorded seed and exact pinned combination to
reconstruct both question choice and answer order. These locally distributed
Quiz packs are not a cryptographic secret against a modified client. The
ordinary presentation exposes the question and ABCD choices to everyone only
after award; the correct index stays out of bot observations. Answer bots
score the four actions equally and choose randomly, while bidding uses a
budget based on public balances. In v2 the pool component excludes every
bid contribution, using only the carried pool and antes. Those inputs stay
fixed during bidding, so other players cannot inflate a previously declined
bot's budget by raising. The game-owned `BiddingStrategy` retains
shared heuristic selection but returns nil when no bid fits that budget.
The ordinary coordinator can then try another actor; the existing clock still
closes the auction. Waiting does not withdraw a bot or write a move, and a new
auction state lets it reconsider. Never replace a refused bid with an
over-budget one merely because the former Pass alternative has been removed.

## Native controls and concurrent input

The auction uses the existing `QuestionSpec` text control, with no separate
submit or withdrawal button: type an amount or `A` and press Enter. Accepted
input clears only its matching `_text_input` edit receipt. Validation errors
preserve the draft. Another participant's bid keeps the local draft, cursor
and focus. The auction control identity contains the accepted game ID and
round, so a new round or game cannot inherit a stale bid or acknowledgement.

Questions use the shared read-only prompt and single-choice ABCD list. Down
enters the list, arrows select and Enter submits for the auction winner.
Other participants and spectators see the same question without submission
authority. V3 chest opening needs no control or player action; historical
manual openings keep their existing `CommandPanelSpec`. S reads scores
outside the auction, including while answering; Shift+S reads them during
the auction without taking the letter S from the bid editor. Readouts retain
full participant names, balances and unopened chest counts. P reads the pool,
T the pending decision, H each player’s current bid, D the viewer's points
and Shift+D other players' points. During an auction, the turn readout explains
that all eligible participants may bid simultaneously.

The game opts into concurrent session input only within the same game,
auction phase and round. Fresh reduction still checks the actor, accepted
input identity, amount, current balance, current leader and deadline. This
exception does not authorize an earlier question or a finished auction.

## Clock, audio and replay

The ordinary `GameRoomSessionRunner` is the sole executor. `automatic_action`
uses the existing logical session clock to advance the wheel, begin auctions,
close them and obtain post-award questions. There is no game-specific timer
thread, polling loop or UI work on the worker. Accepted native event time is
monotonic within the game. Each accepted higher bid replaces the auction
deadline with four call intervals from that bid in v2 (three in historical v1).
All-in bypasses the calls:
one accepted `all_in` event both pays the valid higher bid and awards the auction.
The first accepted all-in closes admission for later offers; no second executor
or timer is introduced. Versioned reduction keeps earlier `bid` and `all_in`
records under their original rules, so accepted historical closings remain
valid in cold replay.

All three v2 calls are local timer announcements, keyed by game,
round, bid revision and ordinal; historical reconstruction skips these
expired cues. Their low/high tones precede the respective spoken calls.
The final interval after the third call still accepts higher bids. Only the
accepted auction-close event awards the auction, binding its recorded round,
bid revision and deadline. Its gavel follows the separate sold announcement
through the native speech sequence. Historical v1 retains its original close.
An immediate all-in uses its winning announcement followed by the same gavel.
User interruption may cancel a pending cue; sound completion does not hold
the model or create a game-clock barrier. Application sounds keep the normal
effect buffering.

Cold and incremental reconstruction use the shared authenticated replay
cache, not another game-owned history cache. Native seed evidence and
accepted events remain the source of replay authority. No hidden-answer
commitment protocol is needed for the single public question answer.

## Targeted checks

The integration coordinator runs checks through the active ELTEN MCP client.
The source tests relevant to the shared adapter and native controls are:

- `test/models/game_content_test.rb`: provider identity, existing Quiz
  selection and pin validation without pack changes.
- `test/games/cash_auction/question_bank_test.rb`: category IDs, exhaustion,
  deterministic question/choice order, invalid inputs, public views and an
  actual registered pack.
- `test/games/cash_auction/setup_test.rb`: supported seats, published defaults,
  option bounds, Quiz content reuse and simultaneous human input.
- `test/games/cash_auction/presenter_start_test.rb`: the real shared presenter
  entering its first foreground/covered auction, a missing previous replay and
  deduplicated pending-decision alerts.
- `test/games/cash_auction/rules_test.rb`: original bid contributions,
  cumulative pass penalties, carried pools, elimination and settlement.
- `test/games/cash_auction/revised_rounds_test.rb`: v2 consecutive non-bidding
  penalties, strict all-in, eight answered questions, deferred chest results
  and an additional answered question after a tie.
- `test/games/cash_auction/percentage_chests_test.rb`: exact weighted
  probabilities, native automatic batch opening at five seconds, one common
  balance/rounding, deductions capped at zero, elimination, cold replay and
  ordered announcement/sound/rewards with a four-second result pause.
- `test/games/cash_auction/all_in_test.rb`: historical immediate question/chest
  awards, numeric maximums and shorter-stack behavior, late/forged refusal and
  unchanged accepted histories.
- `test/games/cash_auction/runner_test.rb`: the active shared executor, native
  seed evidence, host-only automatic progression and concurrent bid admission.
- `test/games/cash_auction/native_surface_test.rb`: actual native bid field,
  all-in, no withdrawal button, protected text editing, selection, matching acknowledgement,
  concurrent refresh, new-round drafts, ABCD, chest commands and read-only
  viewers. Its listener captures actions without writing moves; it is not a
  live-server or listening test.
- `test/games/cash_auction/bid_ack_native_test.rb`: the actual GameScreen,
  network-task and runner acknowledgement path, invalid drafts and newer edits.
- `test/games/cash_auction/bid_shortcuts_native_test.rb`: native information
  keys, editable text, plain S and the absence of move writes from readouts.
- `test/games/cash_auction/content_options_test.rb`,
  `test/games/cash_auction/content_question_bank_test.rb` and
  `test/games/cash_auction/content_tournament_test.rb`: complete pinned
  combinations, provenance, strict publication types and ordinary/fixed starts.
- `test/games/cash_auction/category_sources_test.rb`: source-qualified category
  announcements in five interface languages, no early question and cold replay.
- `test/games/cash_auction/withdrawal_removed_test.rb`: no current withdrawal
  action, refused retained/native requests, silent bot waiting, a later bid,
  the ordinary deadline and unchanged no-bid accounting.
- `test/games/cash_auction/content_editor_native_test.rb`: Space, Enter,
  Escape, one/two/three-set selection, empty validation, language changes and cancelled drafts.
- `test/games/cash_auction/table_defaults_native_test.rb`: fresh forms in all
  five UI languages, ignored former checklists, no source-preference writes,
  the default 100-point ante and unchanged explicit/fixed settings.
- `test/localization/content_language_defaults_test.rb`: all five interface
  languages, default-only general sets, native creation, presets and unchanged explicit choices.

The game-owned model, authority and active-runner regressions are maintained
with the implementation. Missing dependencies, skipped cases and timeouts
are failures, not successful checks. Rulebook source editions live in
`tools/data/rulebooks/{EN,PL,CS,ES,RU}/cash_auction.json`, with the canonical
English fallback at `tools/data/rulebooks/cash_auction.json`. Generated Ruby
and interface catalogs are built separately by the integration coordinator.
