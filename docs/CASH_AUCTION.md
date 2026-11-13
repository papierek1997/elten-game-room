# Cash Auction

Bid and pass effects use the existing optional player-seat HRTF policy.
Wheel, ante, question, answer, countdown and chest/gavel effects stay centred.
Discovery and invitation summaries use the selected Quiz language and set,
through the game's existing notification-option declarations.

Cash Auction (`cash_auction`, Polish name “Awantura o kasę”) is a project
adaptation of the rules requested by the user. It combines simultaneous
all-pay bidding, existing Quiz content and unopened prize chests. This is
not a claim to reproduce an official television rulebook.

## Model and settlement

The game accepts 2–8 participants, including bots. Defaults are 1000 starting
points, a 10-point ante, a 200-point penalty on every third pass across the
whole match, eight regular rounds, two seconds between calls and a 5% chance
of a chest instead of a category/question. Table controls admit starting
points 10–1000000, ante 1–starting points, penalty 0–1000000, rounds 8–32,
call intervals 1–5 seconds and chest chances 5–10%.

Every remaining participant pays the ante. Someone unable to pay is
permanently eliminated. An accepted bid is the bidder's total contribution
to this auction, excluding the ante. The reducer deducts only the difference
from that bidder's earlier bid. All bidders pay, and losing or passing does
not refund their contributions. The current leader cannot pass, but retains
the same bid editor and may raise voluntarily. All-in is the remaining cash
plus that participant's earlier bid contributions. Every third pass pays
the configured penalty into the pool, capped at the participant's balance.

The ordinary auction winner answers one four-choice question. A correct
answer receives the whole pool; a wrong answer leaves it to carry over.
A wrong answer with no cash left permanently eliminates the answerer.
There is no answer deadline. A chest auction instead adds an unopened chest
to its winner, leaves the pool untouched and ends the round.

After the configured rounds, or when at most one active participant remains,
all owned chests must be opened before settlement, including those belonging
to eliminated participants. Each chest independently chooses uniformly from
`[100, 2500, 10000, -100, -500, -1000, 'bankrupt']`. Numeric changes clamp the
balance at zero. Bankruptcy clears the balance and permanently eliminates;
later positive rewards do not revive a participant. The maximum surviving
balance wins. Tied survivors trigger another round for all active seats,
followed by any new chest openings and another comparison. No active seats
means a draw. The pool has no final automatic payout to a leader.

## Shared Quiz content

`Base::Options#content_pack_game_id` defaults to the game's own ID.
Cash Auction returns `quiz`, with `content_pack_kind == 'quiz'`. This affects
selection and support validation only: set, language, pack ID, version and
checksum retain their existing pinned meanings. The game does not rewrite
Quiz pack manifests, data or checksums.

`GameRoomCashAuction::QuestionBank.new(pack)` owns an immutable per-pack index
over the existing frozen question rows. `categories` returns stable integer
IDs `0...n`, ordered by category label within that pinned pack;
`category_label(id)` returns its original label. No copied question database
or process-wide unbounded cache is introduced.

`draw(category:, seed:, used: [])` accepts a native unsigned 128-bit seed and
returns resolver data containing the question ID, integer category, prompt,
shuffled four choices, correct index, pinned pack identity and next `used`
ledger. The caller assigns the returned ledger. It never mutates the input.
Questions do not repeat within a category until it is exhausted; exhaustion
clears only that category's IDs. The unique ledger cannot exceed the bank's
question count. `public_view(data)` copies only approved public fields and
excludes the answer key and internal ledger.

Wheel, question and chest randomness use the existing native seed commands
registered for this game. Question randomness is obtained only after the
auction is awarded; the public category draw cannot select its future
question. Cold replay uses the recorded seed and exact pinned pack to
reconstruct both question choice and answer order. These locally distributed
Quiz packs are not a cryptographic secret against a modified client. The
ordinary presentation exposes the question and ABCD choices to everyone only
after award; the correct index stays out of bot observations. Answer bots
score the four actions equally and choose randomly, while bidding uses a
budget based on public balances.

## Native controls and concurrent input

The auction uses the existing `QuestionSpec` text control, with no separate
submit button: type an amount or `A` and press Enter. Non-leaders also get
the native Pass button, reached with Tab and activated with Enter. Accepted
input clears only its matching `_text_input` edit receipt. Validation errors
preserve the draft. Another participant's bid keeps the local draft, cursor
and focus. The auction control identity contains the accepted game ID and
round, so a new round or game cannot inherit a stale bid or acknowledgement.

Questions use the shared read-only prompt and single-choice ABCD list. Down
enters the list, arrows select and Enter submits for the auction winner.
Other participants and spectators see the same question without submission
authority. Chest opening uses the existing `CommandPanelSpec`. S delegates
to the shared scores feature and reads full participant names, balances and
unopened chest counts.

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
deadline with three call intervals from that bid.

The first and second calls are local timer announcements, keyed by game,
round, bid revision and ordinal; historical reconstruction skips these
expired cues. Their low/high tones precede the respective spoken calls.
The third call is an accepted auction-close event with its recorded round,
bid revision and deadline. Its gavel is scheduled after the complete spoken
“for the third time. Sold!” announcement through the native speech sequence.
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
- `test/games/cash_auction/rules_test.rb`: bid contributions, recurring pass
  penalties, carried pools, permanent elimination, chests and final settlement.
- `test/games/cash_auction/runner_test.rb`: the active shared executor, native
  seed evidence, host-only automatic progression and concurrent bid admission.
- `test/games/cash_auction/native_surface_test.rb`: actual native bid field,
  all-in, Pass, protected text editing, selection, matching acknowledgement,
  concurrent refresh, new-round drafts, ABCD, chest commands and read-only
  viewers. Its listener captures actions without writing moves; it is not a
  live-server or listening test.

The game-owned model, authority and active-runner regressions are maintained
with the implementation. Missing dependencies, skipped cases and timeouts
are failures, not successful checks. Rulebook source editions live in
`tools/data/rulebooks/{EN,PL,CS,ES,RU}/cash_auction.json`, with the canonical
English fallback at `tools/data/rulebooks/cash_auction.json`. Generated Ruby
and interface catalogs are built separately by the integration coordinator.
