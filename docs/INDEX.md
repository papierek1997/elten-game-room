# Documentation

The [tournament administrator handoff](TOURNAMENT_ADMIN_HANDOFF.md) describes
the clean official client, package contents and server deployment boundaries.

Technical and contributor documentation is maintained in English, in the
existing files. Player guides and game rules remain multilingual; their
translations must be kept up to date together.

## Start here for contributors and AI assistants

Read [AGENTS.md](../AGENTS.md) and [CONTRIBUTING.md](../CONTRIBUTING.md) first.
The contribution guide routes games, application features, UI fixes, bots and
content work to their existing contracts; it does not replace reading them.

- [New games](ADDING_A_GAME.md#tested-reference-game): a complete existing
  reference game, an executable two-player scenario and capability-specific steps.
- [Application features](../CONTRIBUTING.md#adding-or-changing-an-application-feature):
  entry points, reuse, validation, failure, lifetime, presentation and completion.
- [Interaction examples](GAME_ACCEPTANCE.md#record-the-interaction-not-just-the-result)
  and [native modal](UI.md#single-choice-modal-dialogs): defaults, ordered speech,
  confirmation, cancellation and return, not only a submitted action.
- [Change-to-test map](TESTING.md#select-checks-from-the-change): select affected
  scenarios and existing dependent tests; distinguish local, native and live proof.
- [PR evidence template](../.github/pull_request_template.md): scope, exact
  verification, player-visible behavior and remaining gaps.
- [Question](QUIZ_EDITORIAL.md) and [rulebook](RULES_EDITORIAL.md) templates:
  mandatory source and full language review; natural target-language writing,
  not mechanically filled sentences or literal translation.

## For players

- [Power Games — user guide](../content/readme/EN.md): getting started,
  tables, invitations, the widget, settings, saved games and key shortcuts.
  The [Polish guide](../README.md) and the other translations in
  [content/readme/](../content/readme/) remain available.

## Implementation and audit plans

These dated plans record agreed scope, past decisions and status at their last
update. They are not a competing current API specification or instructions to
restart old work. For new contributions, use the maintained contracts below and
the current code; confirm any unresolved decision before changing behavior.

- [Extended Power Games audit — 11 November 2026](AUDIT_PLAN_2026_11_11.md):
  correctness, cumulative costs, complete native interactions and speech,
  menu/shortcut consistency, concurrency/recovery and proven dead-code cleanup.
  Includes an independent precision/consistency review of contributor and AI
  guidance, not limited to documentation of newly extracted shared code.
  Started with one primary auditor, one independent code/test reviewer and an
  additional read-only game-model/cost analyst authorized by the maintainer;
  changed-path live verification and one final clean full source pass.
  Completed on 12 November after a clean full source pass and independent
  evidence check. Includes instructions for a fresh run and hash-checked continuation.
- [Partnerships, conferences and Audio Ball doubles — 23 October 2026](FIXES_PLAN_2026_10_23.md):
  partner invitation and notification design, automatic pairing at tournament
  start, actionable start failures, table-conference leave/microphone behavior
  and doubles with ordinary listening and wrong-turn goals. Implemented in
  working sources; the plan records scoped verification and its limits.
- [Power Games audit — 22 October 2026](AUDIT_PLAN_2026_10_22.md):
  proposed whole-project source review for correctness, performance and cleanup;
  targeted local checks and live trials of changed runtime paths and their
  actual dependencies, not a repeat of every game campaign. One primary auditor
  and one independent code/test reviewer; completion requires one full audit
  pass without new defects or further source improvements. Started.
- [Power Games fixes — 21 October 2026](FIXES_PLAN_2026_10_21.md):
  selected game declarations, technical scores, an all-participants-zero
  decision, small-point visibility and a table voice-chat button with
  in-app invitations and no unsolicited dialogs, plus a one-second default
  bot delay in every game and category changes in Countries and Cities
  (Drink, Tool, Known actor, Known writer and Known athlete), plus investigation
  of reported Mahjong slowdown over successive hands; implementation started,
  with local and live-account verification required for every change.
- [New Game Room fixes plan](NEXT_FIXES_PLAN.md):
  implementation scope and explicitly marked questions still to be settled.
- [Duck Racing implementation plan](DUCK_RACING_PLAN.md):
  implementation in progress, starting with Peaceful Pond; agreed rules and
  required local and live-game verification.

## Maintenance

- [Bingo](BINGO.md): variants, tickets, manual/automatic marking, native draws and sound licensing.
- [Dice poker and Liar's dice](DICE_GAMES.md): variants, ranking, hidden-roll protocol, controls and rule sources.
- [Go and roulette](GO_ROULETTE.md): boards, scoring agreement, wheels, bets, social pool and rule sources.
- [Local background music](BACKGROUND_MUSIC.md): general/game tracks, files, MIDI, volumes and lifecycle.
- [Blackjack games](BLACKJACK.md): card and dice variants, scoring, replay,
  virtual-chip boundaries and targeted verification.

- [Architecture](ARCHITECTURE.md): data flow, layers and their responsibilities.
- [Host API](HOST_API.md): the required final ELTEN 3.0.5 contract.
- [Building](BUILDING.md): dependencies, tests, generators and staging.
- [Adding a game](ADDING_A_GAME.md): integrating the model, UI, content and bots.
- [Snapshot ownership](SNAPSHOT_OWNERSHIP.md) and [benchmarks](BENCHMARKS.md).
- [Tools](TOOLS.md), [testing](TESTING.md)
  and [translations](TRANSLATIONS.md): current commands and directory layout.
- [Bot training](BOT_TRAINING.md): evaluating strategies and using the Spades tools.

## Feature contracts

- [Tournament integration](TOURNAMENT_SERVER_INTEGRATION.md): publication,
  participation, scheduling, invitations, match/results ownership and recovery;
  [administrator handoff](TOURNAMENT_ADMIN_HANDOFF.md) separates local code from
  authorized server deployment and diagnostic trials.
- [Mahjong integration](MAHJONG.md): variants, scoring profiles, shared UI,
  ordinary games, server-private tournament hands and finite history budgets.

- [Forms and help](UI.md), [card hands](CARD_HAND.md)
  and the [audio tutorial](AUDIO_TUTORIAL.md).
- [Background execution and presentation](BACKGROUND_GAME_EXECUTION.md).
- [Realtime](REALTIME.md) and [Audio Ball](AUDIO_BALL.md).
- [Private answers and saved games](PRIVATE_STATE.md).
- [Teams, roles and focus](TEAMS_ROLES_AND_FOCUS.md).
- [Interface languages](INTERFACE_LANGUAGES.md).
- [Statistics](STATISTICS.md) and their [schema fragment](STATISTICS_TABLES.json).
- [Sports player statistics](SPORTS_LEADERBOARDS.md): match results, goal totals and background persistence.
- [Question creator](QUIZ_CONTRIBUTIONS.md): private account drafts and
  proposals delivered through messages with a TXT/JSON attachment.
- [Monopoly board sources and limitations](MONOPOLY_REGIONAL_BOARDS.md).

## Maintained content

The [quiz editorial guidelines](QUIZ_EDITORIAL.md) are mandatory when creating,
importing, extending or translating question sets. They cover natural language,
sources, three plausible wrong answers, duplicates and a review of every item,
with guidance for Polish, English, Czech, Spanish, Russian and future languages.

The [game rulebook editorial guidelines](RULES_EDITORIAL.md) are mandatory
when writing, importing, revising or translating rules. They provide an
adaptable outline, worked editorial examples, professional references and a
first-turn walkthrough, and teach essential controls beside the actions they
perform. Remove irrelevant topics without compressing needed explanations
into formulas. A separate shortcut reference helps players recall keys;
general application help and
implementation details remain outside the rules.

[tools/data/rulebooks/](../tools/data/rulebooks/) contains rulebook sources for
the `tools/compile-rulebooks.rb` compiler. The game loads generated Ruby from
`games/generated/rulebooks/` and MO translations; JSON stays outside the package.
Only the Polish fallback text in root-level books is refreshed from PO.
Independently authored editions in the language subdirectories are edited there,
not in PO; see [the translation procedure](TRANSLATIONS.md).

The application's changelog has a single source:
[game_room_changelog.rb](../lib/game_room_changelog.rb), translated through PO/MO
and displayed in What's new. We do not maintain separate Markdown copies of
release notes.

The [readable quiz question lists](quiz-questions/) are exports from `content/`
for editorial review. The game reads Ruby packs in `content/`; TXT files are
not its data source. Each TXT corresponds to a set and contains a sequential
number, question, choices A–D and the correct answer, without technical IDs.
Numbering starts at 1 in each set; answer order is fixed and may differ from
the order during a game. The “Wiedźmin — książki” (The Witcher — books) set
replaces all previous Witcher sets; it excludes games and screen adaptations.
To report an error, provide the set name and question text. Edit the data in
`content/`, then run:

```console
ruby tools/export-quiz-text.rb
ruby tools/export-quiz-text.rb --check
```

Exports use UTF-8 and preserve each set's provenance and licensing information;
they are not included in the installer. `--check` verifies that they are up to
date without writing files.

Keep test reports, audits, measurements and one-off experiment reports in the
ignored `tmp/` directory or outside the repository. Git preserves the change
history; update current contracts in the documents listed above.

The [ordinary tournament team trial](TOURNAMENT_ORDINARY_TEAM_TRIAL.md) documents
native team bindings and shared result validation in the owned developer app,
including the boundaries that still require server support.

The [sporting phase trial and daily dates](TOURNAMENT_PHASE_TRIAL.md) describes
immutable shared round progression and local civil-day schedule editing.

The [manual forfeit trial](TOURNAMENT_FORFEIT_TRIAL.md) documents organizer
decisions for unstarted matches and the boundary for abandoned native games.

The [saved tournament match trial](TOURNAMENT_SAVED_MATCH_TRIAL.md) describes
authenticated continuations across saved-game restoration into a new table.
