# Training and evaluating bot strategies

Code in `tools/training/` runs outside the application and is not included in the installer.
Training results are not automatically transferred to the strategies used by players.

## Spades

One CLI handles training and independent evaluation of selected profiles:

```console
ruby tools/spades.rb train --help
ruby tools/spades.rb train --profiles standard_team_p4_t2 --output candidate.json
ruby tools/spades.rb evaluate --report candidate.json --profiles standard_team_p4_t2 --output evaluation.json
```

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
sampled hands. The natural bidding policy distinguishes weak twos from
opening strength and considers fit and stoppers. See the ACBL lessons on
[planning the play](https://cdn.acbl.org/assets/documents/teachers/Teacher-Manuals/Defense-in-the-21st-Century-Lesson-8.pdf)
and [weak two-bids](https://cdn.acbl.org/assets/documents/teachers/Teacher-Manuals/Commonly-Used-Conventions-Lesson-7.pdf).

For paired comparisons, keep the deal and evaluated seat fixed, vary the
seats across the campaign, and report the actual round score and decision
latency separately. In Bridge, holding the auction fixed isolates card
play. Mahjong variants use different scoring scales; report them separately.
Strategy regressions are under `test/games/scopa/`, `test/games/mahjong/`,
`test/games/bridge/` and `test/games/bouillabaisse/`.

## Shared libraries

- `match_runner.rb`: a complete match in `GameRoomSimulation::Environment`,
  strategies assigned to participants and an explicit reason for termination.
- `game_training.rb`: a decision-value table, self-play and a tournament with
  seat rotation and result reports; the policy supports JSON serialization.
- `learned_strategy.rb`: a learning strategy used by self-play,
  unavailable when only the runtime is loaded.

These libraries are neither games nor separate CLI commands. Regression scenarios
are in `test/tooling/training_test.rb`, `test/games/spades/learning_test.rb`,
`test/games/spades/tool_test.rb` and the simulation tests. The Tysiąc audit helper
belongs in `test/support/tysiac_audit.rb`.
