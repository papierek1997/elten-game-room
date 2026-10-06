# Tests

The directory structure is described relative to `test/`; run commands from
the repository root. Scenarios are grouped by the owner of the behavior.
Each of the 32 games
has a `games/<id>/` directory; filenames inside it do not repeat the game ID.
Tests of a game's rules, bots, interface, translations and tools are kept together.

| Directory | Scope |
| --- | --- |
| `games/` | Game-specific scenarios, such as `games/spades/planner_test.rb` |
| `models/` | Shared replays, bots, simulation, RNG and state ownership |
| `session/` | Match executor, automatic policies, deadlines and clocks |
| `transport/` | LiveSessions, writes, discovery, synchronization and recovery |
| `realtime/` | Communications channels, delivery, routing, ping and P2P |
| `ui/` | Shared forms, surfaces, history, cards, sounds and shortcuts |
| `room/` | Lobby, table, participants, widget, invitations and notifications |
| `persistence/` | Archives, save restoration and private-answer stores |
| `statistics/` | Statistics, telemetry and presence |
| `localization/` | Shared catalog, encoding, translations and rulebook text |
| `host/` | Native application lifecycle, scenes and host-extension reloads |
| `tooling/` | Runner, generators, compilers, training and packaging boundaries |
| `integration/` | Shared contracts and scenarios spanning several games |
| `support/`, `fixtures/` | Stub definitions, helpers and data; no automatic execution |

The `test/` root contains only `run.rb`, `code_quality_test.rb`,
`game_imports_test.rb` and `model_contract_test.rb`: test execution,
code-boundary checks, runtime loading and the reference corpus for all games.

## Running tests

```console
ruby test/run.rb test/games/spades --report tmp/spades-results.json
ruby test/run.rb test/games/monopoly/staged_trade_screen_test.rb
ruby test/run.rb test/transport test/session --list
ruby test/run.rb --suite tooling --list
```

The runner accepts directories, file paths and patterns. It searches directories
recursively, excluding `support/` and `fixtures/`; overlapping selections of the
same scenario are merged. With no arguments, it selects all scenarios.
During the current cleanup, we run only targeted cases, as required by
the restriction in `AGENTS.md`.

Each script runs in a separate process. The default timeout is 180 s;
`--timeout` allows it to be changed. The runner continues after a failure and writes
a JSON report even for failed runs. A timeout, failure or skip produces
a nonzero result; `--allow-skip` explicitly permits skips but does not
relabel them as successes. Missing host sources or dependencies are not a success.
Host tests use a single `ELTEN_HOST_SOURCE`; the pin and gem installation
are described in [BUILDING.md](BUILDING.md).

The six disjoint CI suites (`models`, `transport`, `ui`, `native`,
`tooling`, `integration`) describe the execution layer. A game's directory
describes ownership, so one game can have tests in several CI suites.
Do not combine `--suite` with a list of paths. `tooling/runner_selection_test.rb`
checks suite completeness and disjointness, as well as default discovery.

## Adding and maintaining tests

Place a new scenario alongside the game or layer whose contract it checks.
Name it after the behavior, not a build number. Similar cases using
the same fixtures may share a file; do not combine scenarios
that require conflicting global stubs or a fresh process.

Helpers in `support/` do not execute scenarios on import. Extract shared
definitions from `*_test.rb`. Binary aggregates run their children
through the same runner, with separate processes, preloads and languages. In a coverage
report, the aggregate and its children are not independent additional tests.

The checks for one-off Quiz audits requiring external reports and the test
implementation of the old `TurnGate` have been removed. Current checksums,
corrected questions, the book-based Witcher set and the export are in `games/quiz/`.
Fixtures for the old keyboard and host extensions still serve same-process
update regressions; they are an active contract, not an abandoned backend.

Expected-behavior corpora are in `fixtures/contracts/`. The generator creates
Spades histories and decisions from an explicitly specified reference checkout:

```console
ruby test/fixtures/generate_contracts.rb --source REFERENCE_CHECKOUT --write NEW_DIRECTORY
```

It refuses to overwrite an existing directory. A new version requires a review of the differences;
we do not update expectations in response to a failing test. The quality check compares code
with `fixtures/quality_baseline.json`; the check itself is tested by `tooling/quality_checks_test.rb`.

The `contracts/v1` corpus comes from unchanged `0c86d03` (Ruby 4.0.5, EN).
It covers 30 turn-based games, up to the first 16 legal moves, synthetic participants,
seed 137 and a local secret store. Checkpoints verify replay fields,
action order, the executor and the next eight RNG values without consuming
the game's generator. Historical Categories/Quiz keys based on `String#hash`
are checked against their pattern and normalized to SHA-256 only for comparison.
Battleships, Categories, Krowa, Scrabble and Taboo have only an initial
checkpoint; they also require dedicated choice and data tests. The corpus
does not replace tests of UI, networking, realtime, complete matches or all options.

`fixtures/polish_messages.json` contains independent expected text for
translation regressions, grouped by the behavior being checked. It comes
from existing wording checks and release history; the translation CLI never
regenerates it. It is loaded by `support/translation_reference.rb`.
`fixtures/changelog_checksums.json` preserves the exact wording and order
of EN/PL entries for releases 238–240 as SHA-256 checksums of JSON arrays. Older releases
have expected text in `polish_messages.json`. Changing an expectation requires a review
of the specific entries; compiling translations does not update this data.
The contract for catalogs, manifests and both native ELTEN builders is checked by
`tooling/locale_build_contract_test.rb` using a temporary test application.

`fixtures/quiz/questions.json` stores approved counts, versions, logical
question checksums, excluded IDs and selected media assignments.
`fixtures/audio_ball/recordings.json` ties current recordings to source
files and checksums; licenses are described in `THIRD_PARTY_NOTICES.md`. These expectations
replace the tests' dependency on old reports; they are not automatically
updated when a test fails.
