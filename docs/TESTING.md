# Tests

The directory structure is described relative to `test/`; run commands from
the repository root. Scenarios are grouped by the owner of the behavior.
Each game has a `games/<id>/` directory; filenames inside it do not repeat the game ID.
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
| `tournaments/` | Tournament publication, participation, matches, results and recovery |
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
ruby test/run.rb --suite tournaments --shard 1/4 --report tmp/tournaments-1.json
```

The runner accepts directories, file paths and patterns. It searches directories
recursively, excluding `support/` and `fixtures/`; overlapping selections of the
same scenario are merged, including absolute and relative spellings. The first
spelling is kept in reports. Different arguments, environment or Ruby preloads
are distinct variants; omitted and empty defaults are equivalent. With no
arguments, it selects all scenarios.
During the current cleanup, we run only targeted cases, as required by
the restriction in `AGENTS.md`.

Each script runs in a separate process. The default timeout is 180 s;
`--timeout` allows it to be changed. The runner continues after a failure and writes
a JSON report even for failed runs. A timeout, failure or skip produces
a nonzero result; `--allow-skip` explicitly permits skips but does not
relabel them as successes. Missing host sources or dependencies are not a success.
Host tests use a single `ELTEN_HOST_SOURCE`; the pin and gem installation
are described in [BUILDING.md](BUILDING.md).

The seven disjoint CI suites (`models`, `transport`, `ui`, `native`,
`tooling`, `integration`, `tournaments`) describe the execution layer. A game's directory
describes ownership, so one game can have tests in several CI suites.
Do not combine `--suite` with a list of paths. `tooling/runner_selection_test.rb`
checks suite completeness and disjointness, as well as default discovery.

CI runs the tournament suite in four disjoint parts. `--shard INDEX/TOTAL`
assigns every selected scenario to exactly one part, balancing the declared
timeout budgets with stable path and complete scenario-identity tie-breaks.
Arguments, environment and preloads are retained and also distinguish variants
of the same file; changing enumeration or hash-key order does not change their
partition. Run all parts to cover the whole selection;
`--list` can inspect a part without executing it. Ordinary invocations without
`--shard` still run the complete selection. Full historical tournament simulations
have longer bounded timeouts in `test/support/suites.rb`; `--timeout` overrides them.

## Adding and maintaining tests

Place a new scenario alongside the game or layer whose contract it checks.
Name it after the behavior, not a build number. Similar cases using
the same fixtures may share a file; do not combine scenarios
that require conflicting global stubs or a fresh process.

Helpers in `support/` do not execute scenarios on import. Extract shared
definitions from `*_test.rb`. Binary aggregates run their children
through the same runner, with separate processes, preloads and languages. In a coverage
report, the aggregate and its children are not independent additional tests.

The owned-worker cleanup regression is a narrow test-subject exception: it loads
the two actual guarded parent definitions to exercise their cleanup, rather than
copying those methods. `tooling/test_fixture_isolation_test.rb` permits only those
two exact imports and rejects missing, duplicated or other scenario imports.
`tooling/local_table_import_boundary_test.rb` verifies no parent case executes on
import and that the direct selected entry point still works. This is not a
general exemption for importing a test as a fixture.

For workspace-local scratch data, require `support/temporary_directory.rb` and
use `GameRoomTest::TemporaryDirectory.create(prefix)`. It creates the ignored
`tmp/` parent itself; a scenario must also work as the first test in a fresh
checkout. Do not rely on a previous scenario to prepare directories. The block
form removes its own directory, while the non-block form retains diagnostic evidence.
Test local-time roundtrips against the current system clock, but use the shared
`support/tournament_time.rb` adapter for specific daylight-saving gaps and folds.
Those cases must run on UTC machines too, without changing Windows time-zone settings.

Tests owning Open3 children/readers use `GameRoomTest::OwnedProcessCleanup.run`
around their body, passing the arrays they populate. The scope records its own
primary exception before cleanup; an unrelated caller's rescued exception must
not hide a cleanup failure after a successful body. The low-level `call` accepts
an explicitly owned primary error when needed, not an implicit ambient `$!`.
Cleanup still targets only those owned resources, joins them with bounds and
preserves the primary failure while reporting secondary failures.

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

The separate `v1/kosciane.json` and `v1/balut.json` references cover 16
reviewed transitions each: initial rolls, partial rerolls, third rolls and
scoring by both players. They were added with the new models, not used to
replace any older game's expected state. Complete matches, row/column bonuses,
joint wins, native randomness, saves and replacement remain separate tests in
`test/games/five_dice/`.

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

## Select checks from the change

Choose tests before implementation, then update the selection from the actual
diff and its callers. Follow a changed contract through its producer, executor,
consumer and persisted/generated representation. Search dependent fixtures too:
a new regression alone does not cover changed defaults or an older consumer.
The map below provides starting points, not a command to run every listed
directory for every task. Add the affected game's or feature's own scenarios.

| Changed behavior | Starting checks and dependencies | Owning documentation |
| --- | --- | --- |
| New game, rule or variant | The game's directory, a complete default/variant outcome, refusal and deterministic replay; [model contracts](../test/model_contract_test.rb) when the shared model shape changes; [reference scenario](../test/integration/contributor_game_example_test.rb) for the integration pattern | [Adding a game](ADDING_A_GAME.md), [acceptance](GAME_ACCEPTANCE.md), affected rules |
| Shared surface, layout or binding | [Surface framework](../test/ui/surface_framework_test.rb), [catalog surfaces](../test/ui/catalog_surface_contract_test.rb), [press snapshots](../test/ui/press_snapshot_native_test.rb), plus actual affected consumers and text-field scope | [UI](UI.md), [card hands](CARD_HAND.md), contextual help |
| Dialog, option or list action | [Native choices](../test/ui/choice_dialog_native_test.rb), [application consumers](../test/ui/app_choice_dialog_native_test.rb), or [native option editor](../test/ui/game_option_editor_native_test.rb), according to control; open/edit/confirm/cancel/return with speech counts | [UI](UI.md), [interaction example](GAME_ACCEPTANCE.md#record-the-interaction-not-just-the-result) |
| Execution, pending writes or background work | The owning `session/` or `transport/` cases and [pending-operation UI](../test/ui/game_screen_pending_operation_test.rb); concurrent input, own ACK, refusal/uncertainty, covered UI and close | [Architecture](ARCHITECTURE.md), [background execution](BACKGROUND_GAME_EXECUTION.md) |
| LiveSessions or randomness/private state | [Transport](../test/transport/transport_test.rb), [synchronization](../test/transport/game_sync_test.rb), relevant `live_sessions_*` cases and affected multi-client/game tests; random recipes/private lifecycle tests when those contracts change | [Host API](HOST_API.md), [private state](PRIVATE_STATE.md) |
| Archive, recording or other storage | The owner's `persistence/` cases: validate before side effects, roundtrip, failure/uncertain write, ownership, return/reopen and exact cleanup; also the relevant UI/transport consumer | [Private state](PRIVATE_STATE.md), [architecture](ARCHITECTURE.md), feature contract |
| Invitation, notification or statistics feature | The owner's `room/`, `statistics/` or `tournaments/` tests plus its actual native screen/delivery path; empty/waiting/failure states, identity, expiry, cancel and repeated refresh | [UI](UI.md), [statistics](STATISTICS.md), relevant feature contract in [the index](INDEX.md) |
| Sound or realtime presentation | Affected event/cue and client tests, [optional sound gating](../test/ui/optional_game_sounds_test.rb), manifest/licence checks if assets change; cue order, compound moves, background and resource closure | [Realtime](REALTIME.md), [audio tutorial](AUDIO_TUTORIAL.md), acceptance sound section |
| Bot strategy | Fixed informative positions and counterexamples using identical permitted views/seeds; legal executor decisions and representative completed matches, not just win rate; hidden-input independence where relevant | [Bot training](BOT_TRAINING.md), game's contract and rules |
| Cache, worker, cleanup or performance | The owning correctness tests plus repeated opens/rounds, growing realistic history/data, unchanged refresh, invalidation and failure→retry; compare bounded work/requests/resources as well as elapsed time | [Architecture](ARCHITECTURE.md), [ownership](SNAPSHOT_OWNERSHIP.md), [benchmarks](BENCHMARKS.md) |
| Questions, rules or translations | The respective editorial template in full, source/meaning and complete language review, then affected data, registration, generation/export and native readout if its layout changed | [Quiz template](QUIZ_EDITORIAL.md), [rulebook template](RULES_EDITORIAL.md), [translations](TRANSLATIONS.md) |
| Contributor docs or executable examples | [Documentation contracts](../test/tooling/contributor_documentation_test.rb) and each changed example's behavioral test; update local links and referenced commands together | This guide, [contributing](../CONTRIBUTING.md), [the index](INDEX.md) |

For runtime Ruby changes, include `test/code_quality_test.rb` and
`test/game_imports_test.rb` in the small common preflight. Resolve new quality
findings rather than increasing the baseline merely to accept them. Include
generated-content checks only for the inputs/consumers affected: for example
`ruby tools/compile-rulebooks.rb --check`, `ruby tools/translations.rb check`
or `ruby tools/export-quiz-text.rb --check`. Generation is a distinct step;
`--check` must not silently repair the sources being verified.

For a documentation-only change, start with:

```console
ruby test/run.rb test/tooling/contributor_documentation_test.rb --list
ruby test/run.rb test/tooling/contributor_documentation_test.rb
```

Use `--list` on the selected scope to catch a misspelled path, empty selection
or unexpected breadth before executing it. These checks cannot establish
factual accuracy, natural language or whether a new player understands a text;
those need the editorial review, not another regex or a prose score.

For each selection, record why the existing dependent tests apply and which
boundary requires native or authorized live evidence. A local broker is not
the live service. A captured native speech call is not an audible listening
test. If the risk depends on server authorization, real delivery or recovery,
use the relevant live-account scenario when authorized and disclose any gap.
Do not repeat unrelated game campaigns to inflate the evidence count.

Before pushing, rerun the affected checks after the last meaningful edit,
inspect the staged diff and report exact commands and outcomes. Keep CI suite
discovery complete when adding tests. Observe the remote result for the pushed
commit before calling CI successful; local success and matching Git SHAs do
not establish that result. If the run is queued or in progress, say so.
