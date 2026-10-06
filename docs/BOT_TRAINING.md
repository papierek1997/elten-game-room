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
