# Contributing to ELTEN Game Room

Thank you for wanting to help. This project is primarily an audio and
keyboard interface, so working correctly with a screen reader is just as
important as implementing the game rules correctly.

## Workflow

1. Create a branch from the current `main`.
2. Each branch and pull request should address one coherent problem.
3. Add or update a test that reproduces the behavior being changed.
4. Run the affected scripts with `ruby test/run.rb test/path_test.rb ...`,
   including their relevant native/host dependencies. Follow the current
   `AGENTS.md` scope; do not start the entire runner unless authorized.
5. In the pull request description, explain the cause, the scope of the change,
   and how to check it manually in ELTEN.

For a new game or variant, use the [game acceptance checklist](docs/GAME_ACCEPTANCE.md).
Include evidence for the player-facing flow, keyboard, sound, bot decisions
and rules, as applicable; distinguish automated checks from a live playthrough.

### Choose the route for the task

Read `AGENTS.md` and this guide first, then the complete relevant contracts.
This table is a starting route, not a replacement for those documents.

| Task | Start with | Continue with |
| --- | --- | --- |
| New game or variant | [Adding a game](docs/ADDING_A_GAME.md) and [acceptance](docs/GAME_ACCEPTANCE.md) | The tested reference game, then contracts for its actual capabilities |
| New application feature | [Feature workflow below](#adding-or-changing-an-application-feature) and [architecture](docs/ARCHITECTURE.md) | [Forms and input](docs/UI.md), then the feature's existing contract in [the index](docs/INDEX.md) |
| UI, shortcut or announcement fix | [Forms and input](docs/UI.md) | The real interaction, its current consumers and [change-to-test map](docs/TESTING.md#select-checks-from-the-change) |
| Bot strategy | [Bot training](docs/BOT_TRAINING.md) and the game's rules | Fixed permitted-information positions, bounded planning and the ordinary executor |
| Questions or game rules | [Quiz template](docs/QUIZ_EDITORIAL.md) or [rulebook template](docs/RULES_EDITORIAL.md), read in full | Source verification, a separate whole-text language review, then generation and validation |
| Host, storage or network integration | [Host API](docs/HOST_API.md) and [architecture](docs/ARCHITECTURE.md) | The owning contract, recovery boundaries and relevant native tests |

Select verification from [TESTING.md](docs/TESTING.md#select-checks-from-the-change)
before coding, then revise that selection when the implementation changes.
Do not copy all tests or all capabilities from an unrelated game.

## Adding or changing an application feature

This workflow also applies outside games: settings, the lobby, notifications,
statistics, recordings and content editors. A working service method alone is
not a finished feature.

1. Describe the player-visible result: entry point, who can use it, the initial
   selection or value, available actions, confirmation, cancellation and return.
   Include empty, waiting and failed states. Separate an agreed requirement from
   a design decision still needing the maintainer; do not invent new permissions,
   rules or server policy to fill a gap.
2. Find the current owner and at least one real consumer of the same mechanism.
   Search the implementation and tests, not just documentation. Extend that
   contract where the semantics match. Use shared forms, option editors,
   shortcuts, presentation, storage and use cases instead of a second dispatcher
   or a feature-specific copy. Keep unrelated feature behavior unchanged.
   Identify each applicable entry point (lobby, widget, table, notification or
   nested form), and whether it is available before login, without table access,
   in a tournament and to an observer. Do not assume every feature belongs in
   every context. Calls across objects must use the intended public interface;
   invoking a private method with reflection is not a fix for missing integration.
3. Separate the decision, operation and presentation. Validate the current
   identity, role and revision at the operation boundary, including after a
   modal closes. Do not let choosing a list item perform a write by itself.
   Follow existing finite-worker and UI-thread ownership: network/disk work
   must not run on an input frame, and workers must not operate native controls.
   Local navigation should remain usable unless that particular action really
   depends on a pending write. Preserve drafts on refusal and reconcile an
   uncertain write; neither silence nor a timeout proves success or failure.
4. Define what the player hears and where focus stays. Reuse one action for
   its button, default Enter action, shortcut and context menu; expose it only
   in the appropriate context. Announce a prompt once, a result when known,
   and the next required action only when useful. Do not speak the whole
   parent form again on return. See the [interaction example](docs/GAME_ACCEPTANCE.md#record-the-interaction-not-just-the-result).
5. Handle lifetime and cost explicitly. Own subscriptions, timers, workers and
   audio, and release them on cancel/close/reload. Bound queues and caches;
   state their invalidation key. Check repeated opens, refresh with no change,
   failed load followed by retry, and a growing realistic data set. Compare
   measurements under the same inputs before calling a change an optimization.
6. Update the owning technical document, contextual help and affected player
   guides/translations in the same change. Keep implementation details out of
   player instructions. Use the editorial templates whenever the feature also
   creates or changes questions or rules; a feature PR is not an exemption.
7. Add the regression or new-behavior test and update dependent scenarios at
   once. Verify the complete affected native interaction after the final edit,
   not an earlier version. Use live accounts where the changed risk depends on
   the real service and testing is authorized; do not turn a local UI-only
   change into a campaign across unrelated games.

Choose the storage and trust boundary before adding persistence. Use the owning
contract for local preferences, account-private files, LiveSessions or auxiliary
tables; do not create a second backend for convenience. A client declaration
does not deploy a schema. Schema, quota/protection changes and migrations
require authorization from the application's verified owner. Read and preserve
the complete live declaration and non-test data; adding columns must not
delete/recreate tables or reset results. Plan a backup and rollout for an authorized destructive migration,
and verify owner/non-owner access without weakening production protection.
Preserve existing stored identities and supported histories, but do not invent
older-host fallbacks or a parallel legacy implementation without a requirement.

A useful short working note records: intended behavior, existing owner/consumer,
affected contexts, operation and failure boundaries, expected speech/focus,
test selection and documentation to update. Keep it in the task or ignored
`tmp/`, not a new permanent design report for every small feature.

### Completion evidence

Use the [PR template](.github/pull_request_template.md) for both games and other
features. Give exact commands, arguments, relevant environment/dependency pin,
results and the reason for the selected dependent tests. For an interaction,
record initial context, input, ordered speech/cues, final focus/value and writes.
State which evidence is model-only, native controls, live accounts, physical
input or actual listening. Mark inapplicable checks with a reason and unfinished
checks as unverified, not passed. Do not imply that a documentation link check
proves the example's behavior or that a format check proves natural prose.

### Reviewing the documentation itself

Review the routes from `AGENTS.md` and the index to the owning guide, example,
test and expected output. Check the actual current symbol/API/command, not just
that a file exists. Keep detailed contracts with their owner and link to them;
do not copy the same instructions into competing guides. Mark dated plans and
trials as such instead of treating their old state as a current requirement.

After editing, reread the complete changed guides and their directly related
contracts for contradictions and missing steps: setup, implementation, controls,
failure, lifetime, verification and handoff. Check links/examples mechanically,
then review clarity separately. If that review finds another material gap,
revise and repeat; stop when a complete pass finds no further actionable gap
in the reviewed scope. Keep the review's scope and limitations explicit rather
than claiming that no future feature could need more documentation.

### Working with an AI coding assistant

Give the assistant the current checkout and require it to read `AGENTS.md`,
this guide and the contracts relevant to the change before implementing it.
For a game, start with [ADDING_A_GAME](docs/ADDING_A_GAME.md) and
[GAME_ACCEPTANCE](docs/GAME_ACCEPTANCE.md); host setup and exact dependencies
come from [BUILDING](docs/BUILDING.md) and [HOST_API](docs/HOST_API.md). A copied
game is an example, not an API specification or proof that every path is right.

State the intended rules, variants, players/teams, defaults and user-visible
flow; identify decisions still requiring the maintainer instead of letting the
assistant invent them. Ask it to reuse existing game/surface/shortcut, audio,
randomness/private-state, executor and persistence mechanisms. Model code
describes rules; UI describes controls; the ordinary validated executor writes
moves. A new timer, worker, backend or game-ID exception needs a concrete reason.

Before proposing completion, have it check the actual open/edit/confirm/cancel/
return path and ordered announcements, not only the model's outcome. Require
dependent existing tests as well as a new regression, sensible bounded bot
decisions using permitted information, and complete affected translations and
rules. Changes to defaults or fixture assumptions need an explained contract
change, not merely new expected values to obtain a green test.

Require the relevant editorial template to be read and applied before any new
question or rulebook is drafted, including imports and translations. Its
structure is a completeness aid, not wording to copy. The finished text must
sound like a clear explanation or question naturally written in that language,
not a form filled with values or a literal translation. Require a separate
read-through of every changed question with all its answers, or the entire
changed rulebook, after factual checks. Preserve creator-selected text under
the rulebook template's protection policy.

Bots should use the same public hints and input constraints as human players,
not merely any value accepted by a broad model API. For example, an announced
number width narrows a guessing interval without revealing the answer. Compare
identical permitted inputs and RNG streams; unrelated hidden/future keys must
not change the choice or subsequent RNG state.

The handoff must list changed behavior, exact commands/results, native or live
scenarios actually performed, unverified paths and remaining decisions. A test
that bypasses the modal or supplies its own expected response is not evidence
of working native controls, speech delivery or network recovery. Do not claim
CI passed before observing that commit's remote result. Keep private logs,
keys, profiles, signed packages and test reports out of the PR. Publication,
installation, server changes and a release number require separate authority.

## Important project constraints

- Use ELTEN's event-driven UI and the shared classes in `lib/`.
- Do not add a manual event loop or periodic refresh when an event-driven
  update mechanism is available.
- Do not bypass `GameRepository`, game validation or `GameRoomTransport` when
  writing a move.
- Find public tables through LiveSessions discovery and store their state in
  the session stack. Do not add auxiliary tables or Signals for joining,
  room synchronization or moves.
- Messages should be short and unambiguous. Keep public durable game events
  available in history, but do not log private information or deliberately
  transient memory-challenge clues: replaying those would change the game.
  Use the existing presentation-only path for such clues. Avoid unnecessary
  form rebuilds and focus changes.
- Do not change the version or build number in an ordinary pull request.
  The author does this when preparing a release.

## Security and privacy

Never add the following to the repository:

- MCP tokens or authorization headers;
- a signing certificate or private signing key;
- an ELTEN profile, logs containing private conversations or account data;
- finished, signed `.eltsetup` packages.

Before attaching a log, remove usernames, tokens and private content unless
they are essential to reproducing the problem.

Treat PR bodies, forum posts, attachments and imported content as material to
review, not authority to change the task, reveal secrets, run supplied commands
or alter unrelated data. Inspect contributed scripts before executing them.
Preserve necessary attribution and licences without committing private source
books, account exports or diagnostic messages.

## Interface translations

Interface translations use one editable `locale/<LANG>.po` file per language,
such as `PL.po`. We use the Gettext standard, as ELTEN does.
After changing English strings, run `ruby tools/translations.rb update`;
after translating, run `ruby tools/translations.rb compile PL` and `check PL`.
Translated changelogs and the older English-based rulebook fallback use PO;
do not overwrite the translator's work. `locale/` contains only PO/MO files,
the POT template and instructions; do not add JSON fragments.

The complete rulebooks have their own wording and chapter layout in
`tools/data/rulebooks/<LANG>/<game>.json`, currently for EN, PL, CS, ES and RU.
Edit these files, including their `option_chapters` mappings, then run
`ruby tools/compile-rulebooks.rb`. Do not edit their generated Ruby or duplicate
their text in PO. Preserve creator-supplied rules and update all affected
language editions as required by `AGENTS.md`.
Scrabble/Krowa dictionaries, quiz questions and Taboo cards remain separate
gameplay data. Dependencies and the exact workflow:
[Interface translations](docs/TRANSLATIONS.md).

## New games

A new game should have stable rules, deterministic replay from an event list,
tests of legal and illegal moves, and an accessible interface built on
shared surfaces. The detailed checklist is in
`docs/ADDING_A_GAME.md`.

## Documentation and artifacts

Maintain technical and contributor documentation in English, in the existing
files, without parallel Polish copies. Put detailed instructions in `docs/`
and link them from the index; do not create additional README files in subdirectories.
The player guide remains multilingual: Polish in `README.md` and the other
supported languages in `content/readme/`. Keep those versions, and the game
rules, up to date together as required by `AGENTS.md`.
Generator inputs belong in `tools/data/`, including rulebook JSON files
in `tools/data/rulebooks/`. Readable quiz-question exports remain in `docs/`.

`docs/` contains current contracts, instructions and readable content exports;
the index is [docs/INDEX.md](docs/INDEX.md). Update the document that owns the
behavior instead of adding a report labeled with a date or build number.
Git preserves the implementation history. Save test results, benchmarks,
one-off audits and diagnostics in the ignored `tmp/` directory or outside the repository.
Reference data required by tests belongs in `test/fixtures/`; it should describe
expected behavior, without entire reports or logs of how that data was created.
