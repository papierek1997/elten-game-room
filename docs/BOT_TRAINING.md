# Training and evaluating bot strategies

Code in `tools/training/` runs outside the application and is not included in the installer.
Training results are not automatically transferred to the strategies used by players.

## Spades

One CLI handles training and independent evaluation of selected profiles:

```console
ruby tools/spades.rb train --help
ruby tools/spades.rb train --profiles standard_team_p4_t2 --output tmp/candidate.json
ruby tools/spades.rb evaluate --report tmp/candidate.json --profiles standard_team_p4_t2 --output tmp/evaluation.json
```

Create the ignored `tmp/` directory if needed and choose new output names when
rerunning a comparison. These reports are private working artifacts, not runtime
profiles to commit. See [benchmark setup](BENCHMARKS.md).

Profile names come from `SpadesLearning::ARRANGEMENT_PROFILES` in
`spades_training.rb`. Without `--profiles`, training covers all arrangements,
and evaluation covers all profiles in the report. `evaluate` compares the candidate
with the current runtime profiles using different seeds; by default, it also performs
a separate calibration of both strategies. It does not reproduce historical builds.

`train` retains campaigns, validation and the final holdout set. An unfinished
match in the holdout blocks acceptance of the candidate. An incomplete final evaluation
or its calibration exits with code 2; an argument error exits with code 1. JSON output
goes to stdout or a new `--output` file; an existing file is not
overwritten. Progress messages go to stderr.

`spades_workflow.rb` shares comparisons, acceptance criteria and report
formatting. `spades_training.rb` contains the scenario matrix, arena and training.
Changing production weights requires a separate edit and verification; the CLI does not write them.

Planner cache identities may contain binary digests. Compose their other string
components as binary copies too; joining a UTF-8 participant name directly with
arbitrary digest bytes can raise and silently select a fallback policy. Preserve
the original actor's encoding and the existing digest/bounds. Compare actual
same-deal plans, not just successful key creation. Ordinary named bots use ASCII
technical IDs; a Unicode-actor fixture alone does not prove a named-bot incident.

## Bouillabaisse

The runtime policy uses the acting seat's own hand, public cards, scoring and
hand sizes. Only the current deal contributes void deductions. The planner
compares legal moves in the same bounded set of hypothetical deals, uses the
real scoring function, and searches a short tail when there are few cards
left. The former rank-only policy remains available only in the benchmark.
If public voids and hand sizes uniquely determine a short final-deal tail,
the exact search prefers winning or tying the match to improving the gap
against a trailing opponent. Uncertain deals retain the sampled evaluation.

```console
ruby tools/bouillabaisse.rb --players 2,3,4,5,6,7,8 --seeds 4 --output tmp/bouillabaisse-rank.json
ruby tools/bouillabaisse.rb --players 2,3,4 --reference tactics --opponents tactics --output tmp/bouillabaisse-tactics.json
```

Each pair uses identical six deals, the same seat and the same opposing
policies; each tested player count rotates the measured policy through every
seat, with and without all or nothing. A positive margin gain means the
candidate finished closer to, or farther ahead of, its best rival. Lower
scores are better. Timing measures decisions with more than one legal card,
excluding observation construction, user pacing and networking. Use fresh
seed ranges for final comparisons after tuning. No benchmark writes to the
live game or changes production policy weights.

## Scopa

The policy estimates the risk of exposing a sweep or the seven of diamonds,
then compares a bounded number of possible continuations in seat order. It
samples from the deck minus public cards and its own hand. The same samples
are used for every candidate; the two-player endgame is solved exactly when
there are no unknown stock or discarded cards and at most eight cards are left.
Completed simulations use the production round awards, including Muerto
and partnerships. Incomplete ones estimate the three contested majorities.
The ideas of card counting and playing from an information set follow
[Di Palma and Lanzi's Scopone study](https://arxiv.org/abs/1807.06813);
the project's capture and scoring rules take precedence.

## Mahjong

The policy counts copies of tiles that would improve its own hand, excluding
public discards, revealed melds, dora indicators and the hand itself. Ready
hands are evaluated with the appropriate scoring engine, not only their shape.
Among similarly live ready hands, the policy also considers the actual expected
payment from that variant's scoring/payment modules. Dora and a legally available
Riichi declaration may change that value; a structural completion without the
required scoring conditions still has no value. Public match points adjust
late-match risk. A cheap narrow wait does not automatically justify pushing
against a declared threat. Only Riichi has the public-discard furiten safety
rule; do not treat a previous Hong Kong/MCR discard as guaranteed safe.
Memoizing suit decompositions within the decision bounds the cost of trying
draws. The bot can declare Riichi with live waits, defend with known safe
discards, and claim a set when it makes sufficient progress toward a scoring
hand. It never reads the wall order or opponents' waits. For the Riichi
strategy background see [Daina Chiba, Riichi Book I](https://dainachiba.github.io/RiichiBooks/).

## Bridge

Play uses the public cards, observed failures to follow suit, the controller's
hand and dummy only after it is visible. The planner compares common sampled
deals and models follow-suit, overruffs and entries, with an exact short search
only for a deducible distribution. Simulated players do not see the other
sampled hands. Hypothetical hidden hands are softly weighted by the natural
auction's expected strength, announced lengths and balanced openings. An unusual
human auction remains possible; it never becomes a hard card-ownership claim.
The same interpretation is exposed by `BridgeBidding#partner_evidence`, not a
second bidding system in the sampler. This follows the information-set approach
discussed in [Ginsberg's GIB paper](https://www.cs.cmu.edu/afs/cs/project/jair/pub/volume14/ginsberg01a.pdf).
The natural bidding policy distinguishes weak twos and
overcalls from opening strength. It separates simple raises, invitations
and raises forced higher by an opponent, and uses announced suit lengths,
stoppers and vulnerability to find a legal alternative. There are no new
artificial conventions. See the ACBL lessons on
[planning the play](https://cdn.acbl.org/assets/documents/teachers/Teacher-Manuals/Defense-in-the-21st-Century-Lesson-8.pdf)
and [responding to a suit opening](https://cdn.acbl.org/assets/documents/teachers/Teacher-Manuals/Bidding-in-the-21st-Century-Lesson-4.pdf).

For bidding comparisons, run
`ruby tools/benchmark-bridge-bidding.rb --seed 20261107 --boards 8000 f76d73a`
against that trusted local revision. Each deal is played with the same
dealer and vulnerability, switching one partnership's bidder at a time.
The common card evaluator sees the final contract but not the auction.
Use `--planner` on a smaller sample to score with the full play planner
instead of the faster play heuristics. Report both IMP differences and
defeated contracts: bidding too cautiously can also miss a playable game.
Against `f76d73a`, the full-planner check used 160 boards at seed 914
and 224 boards at each of seeds 916–919. Across those 1,056 boards the
new bidder gained 0.39 IMP per comparison, with 207/1,017 defeated
contracts instead of 322/1,037 and 214 games made instead of 216.

For paired comparisons, keep the deal and evaluated seat fixed, vary the
seats across the campaign, and report the actual round score and decision
latency separately. In Bridge, holding the auction fixed isolates card
play. Mahjong variants use different scoring scales; report them separately.
Strategy regressions are under `test/games/scopa/`, `test/games/mahjong/`,
`test/games/bridge/` and `test/games/bouillabaisse/`.

## Bounded planning contracts

Reuse the existing observation, `SearchBudget`, hypothetical-deal sampler and
normal action executor. Planning must not consume the live game's entropy or
read actual hidden hands, future draws, a sealed answer or an unannounced deal.
Opponent hand sizes are usable only when that game's rules make them public;
even library size is hidden in Biblios. A possible world is a hypothesis, not
permission to reveal its other hands to simulated players.

Current bounded mechanisms include:

| Game | Decision model and scope |
| --- | --- |
| Backgammon | Complete legal use of the current dice, memoized through `BackgammonRules.legal/apply`; 6,000 search nodes. Sparse contact tails with at most four active checkers also enumerate actual composed opponent rolls, including doubles and bar entry, within 2,000 reply nodes. Exhaustion uses the cheap exposure model. This is not a full cubeful rollout. |
| Hearts | Joint three-card passing and full-deal continuation in up to 16 common worlds; at most seven root cards and 8,000 nodes. Public plays, voids and the acting player's known passed cards condition samples. Merely collecting the queen is not evidence that a moon attempt is viable. |
| Jass, Belote, French Tarot, 3-5-8 | `GameRoomTrickForecast` compares at most four roots in up to 12 common worlds once the acting hand has at most four cards; 4,096 nodes. Games supply production legality, winner and scoring callbacks. A candidate must not lose against the fallback in any sampled world. Long-deal speculative rollouts do not override the normal opening policy. |
| Cribbage | Every discard uses the same 192 conditioned full-crib samples and all possible starters for the retained hand. Pegging compares 96 common possible rival hands: the rival chooses a legal reply, including an immediate public-score finish, rather than receiving a random reply card. The second discard reuses the plan for the same original six cards. |
| Bridge | At most 20 proposed worlds are softly auction-weighted, retaining up to five. Public voids remain hard constraints. A deducible short tail keeps its existing exact solve. |
| Poker | The existing 64 common equity worlds remain bounded. `poker_opponents.rb` uses at most 2,048 typed public history entries to smooth fold/aggression rates and revealed final-street weak aggression by actual account identity. Street and relative-call-size evidence shrink toward the global prior; an unseen context stays neutral. It adapts fold equity and range credibility, not the rules or hidden cards. |
| Dice Poker | A cached distribution models retaining dice across the allowed throws, rather than the best of independent full rerolls. It uses the same rank evaluator and a neutral percentile-maximizing policy; it is an estimate of a rival, not a read of their hidden dice. |
| 99 | Each accepted search depth compares every root in the same worlds. On budget exhaustion use the last completed iteration, never a mixture of root depths. The default fair sampler remains distinct from the existing explicitly selected omniscient variant; this change does not expand either one's information access. |
| Cat/head/tail | A reused small Bellman table models the real eight-sided outcomes, including immediately banked twos, repeating sevens and signed eights. Match-ending decisions still take precedence. |
| Reversi | The existing alpha-beta uses at most eight plies in a finite tail of eight empty squares when voluntary passing is disabled. With 9–10 empty squares and at most three root choices it may complete ten plies, retaining the same 55,000-node limit and last-completed-iteration fallback. Its fast adapter uses real placement/settlement. An exhausted budget or voluntary passing is not an exact solve. |
| Yahtzee, Balut, General | `GameRoomFiveDiceScoreTail` compares the last one/two entries and their actual next three-roll turn. Each game supplies real legal choices, recording, total and bonus functions. Known final rival totals use expected outcome first and expected own points only to break ties. General does not predict competitive column bonuses across an unknown intervening rival turn. |
| UNO, Makao | `GameRoomBots::OwnContinuations` proves only continuations using owned cards and known skipped turns. Stop at an unknown draw, transfer or rival response. UNO uses at most 256 nodes (32 in interception variants); actual interceptions, straights and urgent declarations bypass this planner. Makao uses 128 nodes. This does not change configured bot pacing. |
| Rummy | Up to 18 owned cards get a complete 8,000-node packing attempt with the real meld candidates, first-entry threshold and outstanding debts. Exhaustion retains the existing beam search; never claim a partial packing is optimal. |
| Battleship | Up to three unambiguously remaining ships are allocated jointly against all public hits, misses and no-touch constraints. The 20,000-node complete-or-fallback model never uses the actual hidden fleet. Large or ambiguous touching fleets retain the approximate density model. |
| Farkle | A known last player's deficit up to 500 uses a finite final-turn value table rather than a fixed future-roll horizon. Every positive keep raises the total and overtaking the public target terminates the tail; ordinary rounds retain the bounded model. |
| Ludo | One guaranteed own roll after a six is compared over the six outcomes, including the configured third-six rule. This is not an assumption that all opponents' future threats occur simultaneously or that their turns disappear. |
| Chess | The fast search adapter uses the same move, castling, en-passant, promotion, check/mate and draw helpers as the reducer. Preserve last-move metadata for recapture extensions and the complete repetition state. Depth and node limits are unchanged. |
| Go | Score the result of accepting a pass and check an immediate legal capture of the newly connected group. Atari capture is a terminal objective, not merely another fixed stone bonus. Superko remains authoritative. |

General also estimates retention of already earned/immediately available bonuses
before school forces a zero. Its owned `GeneralSchoolStrategy` targets each
remaining school row through three throws and lets failed attempts consume the
finite remaining combination boxes. It models reserve transitions and caps a
reserve's value at what the remaining entries can use (at most two reserve dice
per entry). The final entry cannot create valuable reserve. This conditional
policy ignores lucky cross-row assignments; it is not an exact full-match solve
or a prediction of an opponent's future bonus claim. Survival/row caches are
bounded to 128/512 entries with vectors bounded by the actual six-column option.
The existing exact short score tail still takes precedence when eligible.

Yahtzee and General share the immutable five-dice target-count distribution.
Yahtzee keeps its existing early upper-section estimate. With one/two upper
boxes left, it also values the finite other boxes available for retries before
abandoning the 35-point bonus. The fixed high-to-low face policy uses at most
74,624 scalar cache slots; it sees only the own sheet, never actual future dice.
It is an estimate, not a full optimal policy or a forecast of joker windfalls.
An already secured/impossible bonus adds no new incentive. Preserve legitimate
early low-face sacrifices, but test later high-face writes that would make 63
impossible while a cheap alternative box remains. Winning the game takes
precedence over obtaining the bonus for its own sake.

Balut's progress uses the production `row_points_possible?` boundary: an impossible numeric bonus
must not accumulate fictitious progress. Losing that bonus does not make future
raw points worthless, so retain their separate opportunity cost. A more detailed
probability model is not automatically stronger; compare it on fresh paired
matches before replacing the bounded existing policy.

Belote's contract settlement and Tarot's Excuse distribution are shared between
the reducer and forecast. Do not copy their rules into a separate planner.
Tarot discards belong to declarer's scoring pile: banking an unprotected court
card can be preferable to retaining it. Jass feeds a winning partner only once
the trick is secured. Domino and Mexican Train use the shared tile helper:
up to 12 tiles get a 4,096-node attempt to follow a real sequence of exposed
ends, rather than every branch of a connected component. Long/exhausted hands
use component reachability. This forecasts owned connectivity, not unchanged
opponent turns; Mexican Train's own double series may use other open trains.
Biblios allocates unknown category cards jointly within neutral estimated rival
library capacities and the physical inventory, with a 20,000-node exact attempt.
Hidden library sizes are still not inputs. Exhaustion retains the independent
marginal estimate; do not label the estimated libraries as known real hands.
Blackjack removes owned/exposed cards from the actual fresh six-pack shoe
(one deck in social mode); its subsequent fixed-composition draw model is still
an approximation, not a no-replacement shoe solve. Duck Racing's
numeric bot uses its own public view and completed announced totals; an initial
unannounced 21 must remain private. Its replacement-style draw expectation is
an approximation, not an exact remaining-deck solve. Race movement values own
harmful traps too: only an owner's feather-stealing traps are ignored. Known
independent chance-field effects use their public probabilities, not saved RNG.

Poker profiles are match-local and account-specific. Historical authors are
not relabelled when a seat changes occupant. Only ordinary revealed showdowns
calibrate weak aggression; an earlier value bet followed by a missed draw is
not proof of a bluff. The same card samples are retained when comparing changes
in profile weights. Raising considers public fold/call response subsets,
including partial folds at multi-player tables; dead contributions remain in
their pots. At most seven opponents produce 128 response cases. Subset equity
is cached against the same card samples, not recalculated for every bet size.
This follows the selective-simulation design in
[Billings et al., Using Selective-Sampling Simulations in Poker](https://poker.cs.ualberta.ca/publications/AAAISS99.pdf).
The method is inspired by public-observation opponent
modelling, such as [Bayes' Bluff](https://arxiv.org/abs/1207.1411), not an
implementation of its complete inference algorithm or a Nash/CFR solver.

Keep caches local and bounded. `DealtCardGame#incremental_replay` mutates an
existing replay. Identity and actor alone are not a revision: also include the
accepted-event count (and any other independently changing input). Test a
second turn of the same player on the same object and a new replay with matching
counters. Immutable sampling inputs and equivalent-world memoization avoid
recomputing the same continuation without sharing mutable branches.

Spades caches only the owned, value-keyed team assignment used repeatedly in
one decision. Options/roster changes invalidate it. Do not replace this with a
mutable replay-identity-only cache or change sampling budgets merely because a
cache made the current analysis cheaper.

For a proposed expansion, keep a separate candidate and fresh validation seeds.
Reject a more expensive candidate when its stated gain does not survive that
check; a larger search is not an implementation requirement by itself. Record
whether the evidence is an exact counterexample, model expectation, paired
completed matches, or a live synchronization check. These are not interchangeable.

### Required strategy checks

- Retain a reproducible counterexample and an independent score/probability or
  legal-continuation oracle. Verify the proposed action through production rules.
- Compare identical seeds, deals, seats and opposing policies; use fresh seeds
  after tuning. Distinguish a whole match from one deal, a forced endgame result,
  an inference error or an expected-value experiment with synthetic rival styles.
- Keep unsuccessful candidates and helper failures in the local report. Passing
  legality tests does not establish stronger play; withdraw/revise candidates
  that lose in paired comparisons. Do not turn a small sample into a general
  win-rate guarantee.
- Poison actual foreign cards/future decks without changing the allowed
  observation. Check current-deal chronology after participant replacement,
  nonmutation, cached/uncached decisions and cold/warm computation limits.
- Check selected-game dependencies and the registered production bot path.
  Transport, UI, private-card protocol or ownership changes also need their
  appropriate live-account scenarios; do not call local reducers a live test.
- Check a resource after its final usable slot, surplus beyond remaining
  capacity, impossible versus merely unlikely bonuses, and actual retry budgets.
  A late failure in a replay can expose missing earlier obligation planning;
  the failed roll alone does not prove that every earlier choice was wrong.
  Literal reserve dice, expected future points and a slot's opportunity cost
  are different quantities. Do not remove one because another became worthless.

Focused regressions include `trick_bot_revision_test.rb`,
`hearts/strategy_context_test.rb`, `backgammon/turn_planning_test.rb`,
`mahjong/strategy_value_test.rb`, `bridge/auction_sampling_test.rb`,
`poker/opponent_learning_test.rb`, `ninety_nine/root_budget_test.rb`,
`cat_head_tail/turn_expectation_test.rb`, `domino/connection_strategy_test.rb`,
`biblios/category_model_test.rb`, `french_tarot/discard_plan_test.rb`, and
`reversi/{endgame_strategy,search_transition}_test.rb` under `test/models/` or
`test/games/` as appropriate. Use the targeted runner described in
[TESTING.md](TESTING.md), not the entire suite by default.

## Shared libraries

- `match_runner.rb`: a complete match in `GameRoomSimulation::Environment`,
  strategies assigned to participants and an explicit reason for termination.
- `game_training.rb`: a decision-value table, self-play and a tournament with
  seat rotation and result reports; the policy supports JSON serialization.
- `learned_strategy.rb`: a learning strategy used by self-play,
  unavailable when only the runtime is loaded.

Only completed matches call `finish_episode` and update learned values/visits.
Action limits, missing legal continuations and invalid strategy actions are
unfinished attempts, not zero-reward draws; the runner discards their actor
trajectories through `reset_episode`. This also matters when one learner is
reused across several matches. Reports keep unfinished attempts separate from
completed results and Elo ratings.

These libraries are neither games nor separate CLI commands. Regression scenarios
are in `test/tooling/training_test.rb`, `test/games/spades/learning_test.rb`,
`test/games/spades/tool_test.rb` and the simulation tests. The Tysiąc audit helper
belongs in `test/support/tysiac_audit.rb`.
