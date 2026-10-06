# Contributing to ELTEN Game Room

Thank you for wanting to help. This project is primarily an audio and
keyboard interface, so working correctly with a screen reader is just as
important as implementing the game rules correctly.

## Workflow

1. Create a branch from the current `main`.
2. Each branch and pull request should address one coherent problem.
3. Add or update a test that reproduces the behavior being changed.
4. Run `ruby test/run.rb`.
5. In the pull request description, explain the cause, the scope of the change,
   and how to check it manually in ELTEN.

## Important project constraints

- Use ELTEN's event-driven UI and the shared classes in `lib/`.
- Do not add a manual event loop or periodic refresh when an event-driven
  update mechanism is available.
- Do not bypass `GameRepository`, game validation or `GameRoomTransport` when
  writing a move.
- Find public tables through LiveSessions discovery and store their state in
  the session stack. Do not add auxiliary tables or Signals for joining,
  room synchronization or moves.
- Messages should be short, unambiguous and available for review in the
  history. Avoid unnecessary form rebuilds and focus changes.
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

The only editable translation source for a language is its
`locale/<LANG>.po` file, such as `PL.po`. We use the GetText standard, as ELTEN does.
After changing English strings, run `ruby tools/translations.rb update`;
after translating, run `ruby tools/translations.rb compile PL` and `check PL`.
Polish rulebook fields and Polish changelogs are generated from PO and must not
overwrite the translator's work. `locale/` contains only PO/MO files, the POT
template and instructions; do not add JSON fragments. Scrabble/Krowa dictionaries,
quiz questions and Taboo cards remain separate gameplay data.
Dependencies and the exact workflow: `docs/TRANSLATIONS.md`.

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
