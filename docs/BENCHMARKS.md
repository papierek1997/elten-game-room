# Local benchmarks

```console
mkdir tmp
ruby tools/benchmark-runtime.rb --iterations 20 --output tmp/benchmark.json
ruby tools/benchmark-runtime.rb --games spades,monopoly,uno --iterations 20 --output tmp/subset.json
```

Create `tmp/` if it does not already exist; its contents are ignored by Git.

The input is the versioned corpus `test/fixtures/contracts/v1/histories.json`.
The report records its hash, the Ruby version and the platform. Each phase has a warm-up,
an iteration count, CPU time, wall-clock time and an allocation count. Replay, deep copying,
view-specification construction, legal actions and bot decisions are measured separately.
The decision digest includes the selected action and the subsequent RNG state;
a speed comparison is meaningful only after these results are confirmed to match.

The empty-lock measurement is a separate item. It does not measure waiting for
the planner, network, disk, host or speech synthesizer. Do not subtract it from RTT or
interpret local CPU time as player-perceived latency. Queues and the relay
require separate realtime scenarios, and genuinely different connections require
tests with clients using those connections.

Compare the same Ruby version, platform, corpus and iteration count, across several
runs without a concurrent runner. The absence of a timing threshold in CI is intentional:
shared-host variability must not masquerade as a regression in game rules.
The report contains the last iteration's result; expected decisions and replays are
checked separately by `model_contract_test.rb` and `test/games/spades/decision_contract_test.rb`.
