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
