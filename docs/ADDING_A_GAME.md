# Adding a game

Read this guide with [the acceptance checklist](GAME_ACCEPTANCE.md). Ordinary
application features use the [contribution workflow](../CONTRIBUTING.md#adding-or-changing-an-application-feature)
instead; they should not acquire a game model just to reuse a form.

## Tested reference game

Use the existing Tic-tac-toe implementation as a small, complete vertical
example, not a copied starter framework or a second demonstration game to ship.
Read its pieces in this order:

| Part | Working reference | What it demonstrates |
| --- | --- | --- |
| Registration | [Catalog](../games/catalog.rb) and [registry](../games/registry.rb) | One game ID, construction and rulebook validation |
| Model | [TicTacToe](../games/tic_tac_toe.rb) | Identity, player limits, start, `replay`, `surface_spec`, `action_for`, legal moves and errors |
| Start randomness | `automatic_action` and `tic_tac_toe_start` in that model | One shared server recipe, no client-only first-player draw |
| Controls | `GridSpec` in that model and [surfaces](../lib/game_surfaces/specifications.rb) | A board description, not a private input loop; the shared layout adds chat/history/users/help |
| Presentation | `HistoryEntry`, `describe_event` and `event_sound_cues` | One accepted move becomes a player/field announcement and the existing `play2` cue |
| Rules | [English authored book](../tools/data/rulebooks/EN/tic_tac_toe.json), its other language editions and [source manifest](../tools/rulebook_sources.json) | Editable source, generated runtime rules and shared language dispatch |
| Bot | `bot_strategy`, `bot_search_key`, `bot_action_score` | Bounded shared search using the legal-action path |
| Executable example | [Contributor scenario](../test/integration/contributor_game_example_test.rb) | Registry → normal executor/start draw → two players' validated moves → replay/history/cue/result, including refusal |

Run the small example and the game's existing start/model regressions:

```console
ruby test/run.rb test/integration/contributor_game_example_test.rb test/games/tic_tac_toe/rules_test.rb test/games/tic_tac_toe/random_start_test.rb
```

The example uses the native API test harness with a local broker, not live
ELTEN accounts. It submits explicit player decisions through the normal session
executors and repository and checks both clients; it does not exercise physical
keys, actual listening or a live network. Shared native controls have their own tests; select them
from [the change-to-test map](TESTING.md#select-checks-from-the-change).
The separate exhaustive strategy test is not part of this quick example.

Tic-tac-toe does not teach private hands, card transfers, rounds, teams or
realtime physics. For those capabilities, follow the appropriate existing
contract and consumer, such as `DealtCardGame`, [private state](PRIVATE_STATE.md),
[teams](TEAMS_ROLES_AND_FOCUS.md) or [realtime](REALTIME.md). The steps below
define the actual integration requirements; the example is not a rule to
inherit from `TicTacToe` or copy its optional hooks.

## 1. Choose an existing model

Check the shared classes first. A board game with piece-to-square moves should
inherit from `GameRoomGames::TurnBasedBoardGame`. Other games inherit from
`GameRoomGames::Base`, but still use `GameSurfaces`, the layout, shortcuts,
history, scoring, rounds and bots.

Do not create a new layer just because one game needs an additional
action. First try extending the surface specification or adding a small,
reusable component to the existing framework.

`DealtCardGame` reuses `CardGame` for round-based games whose decisions are
single-card plays. Bouillabaisse and Scopa share its deal validation, hand
surface and shortcuts, public history and score exports. Each still owns its
deck, legal-card rule, round reducer and scoring. Its private adapter uses the
existing pool ledger, not a parallel transport or bot scheduler.

## 2. Implement the model

Create `games/<id>.rb` and implement at least:

- `id`, `name`, `short_description` and `rule_sections`;
- `minimum_players` and `maximum_players`;
- `option_definitions` if the game has variants;
- events that start a match;
- `replay`, which reconstructs the state deterministically;
- `surface_spec`, which describes the accessible interface;
- `action_for`, which validates turn order, action type and all rules;
- readable history entries and error messages.

Long matches can declare `session_history_capacity(options)` to request a
larger native history budget at table creation and saved-game restoration.
The default is `nil` (4,096 records); explicit requests must be integers from
4,096 to 32,768. The store closes and rejects a session if the server grants
less than an explicitly increased budget. This does not compact active games
or permit unlimited history. Keep this declaration in the game rather than
adding game IDs to the lobby or transport.

An event should contain the data needed to reproduce a move, but not data
that can safely be derived from the state. Private information, such as card
hands or answers before they are revealed, must use the existing
hidden-data mechanisms.

## 3. Connect the shared interface

Choose the appropriate surface from `lib/game_surfaces/`:

- `piece_board` for a board with pieces;
- `pawn_track` for a pawn track;
- `dice_tray` for dice;
- a card surface for a hand and pile;
- `answer_sheet` or `review_surface` for answers and scoring;
- `command_panel` for a small set of commands.

History, the user list, F1 help, Ctrl+F1 rules and the overall screen layout are
shared. Add shortcuts specific to a game family to the shared
framework only when their meaning is genuinely the same.

Use `GameShortcut` declarations for common action, number and choice prompts
rather than binding a second game-specific handler. A local single-choice
picker outside a shortcut uses `GameRoomUI.choose_index`; see the exact return,
cancellation and stale-view contract in [UI.md](UI.md#single-choice-modal-dialogs).
The game retains result semantics and revalidation after the picker closes.
Do not copy a bare ListBox/Form loop: it may miss Escape, speak twice or let
the closing key trigger the underlying game. Multiple-choice and timed forms
have additional requirements and are not equivalent to a simple picker.

Waiting-room local buttons use `waiting_view_spec` with `status_commands` and
the game's `run_room_command`; Krowa's gallery is a working example. The layout
owns their bindings and clears them on rebind. During play, declare
`game_shortcuts` through the existing shared shortcut/surface integration, not
a second waiting-room key dispatcher. Do not copy the retired empty
`room_shortcuts` hook from an older source snapshot.

Before implementing a new UI mechanism, inspect the current surface specs,
base hooks and [acceptance checklist](GAME_ACCEPTANCE.md). Reuse an existing
capability when its semantics match. If it needs extension, update real
consumers, the contract and native tests together; do not add a game-ID branch
to the screen or transport. Demonstrate the whole interaction, not just a
returned action, and state separately what was not verified on live accounts.

### Finding playable cards

An actual card hand should implement `playable_card_navigation` and
return `card_navigation_spec`. The specification provides the hand control's
identifier and groups all currently legal actions by the stable identifier
of the physical card. Do not group by move description: an ace counted as 1 or 11
is one card with two ways to use it.

The shared layer adds `Z` and `Shift+Z`, cycles through the specified
cards and announces the new position without refreshing the form or using the network.
The game also supplies the set of cards eligible for an automatic move. A move
is made only when there is exactly one playable physical card, exactly one
legal action and explicit permission from the game. Otherwise, only the
cursor changes.

Do not allow an automatic move if playing the card still requires choosing a color,
target, value, meld, declaration or packet. Return `nil` in phases where the aid
makes no sense or would give an advantage in a reaction race. Merely selecting
a card must not bypass `action_for`, change state or send a request.

A control that supports packets is not in itself a reason to disable automatic
play. If it represents an ordinary single card as a one-element
array, check the actual alternatives for the legal move. Makao blocks automatic play
when several cards can be played together or a declaration must be chosen; an ordinary,
sole playable card without these alternatives can be played automatically.
Z/Shift+Z navigation reads only the selected card, without the hand heading.

## 4. Optionally add a bot

Set `supports_bots?`, expose the full list of legal actions and register a
strategy. A bot may use heuristics or search, but the selected action must
go back through the ordinary `action_for`; the strategy must not append events itself.

Games retain `session_runner? == true`: the shared `GameRoomSessionRunner`
plans durable actions, checks freshness and writes the decision. Realtime
clients own their separate physics, input and bot loop, while the shared runner
still records agreed points and handles presence boundaries. Do not disable
that durable runner merely because a game has a realtime client, or add a
second executor to `GameScreen` or the game control. Keep reusable training
code in `tools/`, outside the installed runtime. One-off probes, reports and
audit results belong in ignored `tmp/`, not in tracked tools or game libraries.

Check separately:

- no legal move;
- the end of a round and the end of a match;
- several bots making consecutive moves;
- incomplete and complete information, if the game has an “oracle” bot variant.

## 5. Register the game

Add `require_relative` and the class to `GameRoomGames::CATALOG` in
`games/catalog.rb`. `__app.rb` uses the same catalog through
`GAME_REGISTRY`. The registry calls `rule_book`, so missing rules will be
detected at startup.

## Tournament results

The shared tournament runner uses game-owned results, not an independent game
rules implementation. The base result is sufficient for a single winning unit
or a complete draw. If the game's public result can name several winning units,
provide `tournament_winning_units_result(replay, options:)` in the game or its
shared family. It returns the same units/winners/draw/scores shape as the base
contract. Use `tournament_result_from_public_winners` when the game publicly
names winning people; that helper requires complete confirmed teams. TileGame
is a current example. Do not guess results from arbitrary private state fields.

New bindings use result policy v8. Existing v1-v7 bindings retain their earlier
hooks and exact exports, even if unfinished. Do not alter those historical
hooks or silently upgrade stored match identities to repair a new result.
Numeric small points remain a separate opt-in `tournament_small_point_policy`;
finishing places alone do not enable them. Test actual completed accepted
histories, shared winners, a full draw, teams, standings and the relevant
historical policies. See [the integration contract](TOURNAMENT_SERVER_INTEGRATION.md)
and `test/tournaments/tile_winning_units_policy_test.rb`.
Numeric score keys must name the same units as the result: one entry per team,
not one per teammate or the sum of repeated team totals. Count all accepted
sets when the public scoreboard resets between sets; preserve the game's
ordinary displayed score and personal statistics. The realtime regression in
`test/tournaments/realtime_small_scores_test.rb` covers both sports and layouts.

## Interface and rulebook translations

Before drafting the rules, read the
[game rulebook editorial guidelines](RULES_EDITORIAL.md) in full. Explain
the aim, normal play and its consequences in natural, connected prose.
Use their outline as a guide, not an identical template for every game.
Explain how to perform each main action alongside the rule, using the
actual key, button or short menu path; do not leave this only to the
shortcut reference. Keep these controls consistent with F1 help, and leave
shared application behaviour and implementation details out of the rules.
Remove unnecessary topics, not the explanation needed to understand a legal
move. Follow the guide's worked examples and walk through a first turn using
only the text; terse card-effect formulas are not a substitute for teaching.
Review the whole changed text in every affected language, not just a sample.

Mark English messages with `_`, `n_`, `p_` or `np_`, and enable
`using GameRoomLocalization::Translations` inside the file's root module.
For interface messages, `ruby tools/translations.rb update` updates the PO
catalogs; edit `locale/PL.po` or the relevant language's PO and compile it with
`ruby tools/translations.rb compile PL` (substitute the language code).
Do not edit generated MO or Ruby translation views.

The compiler needs both its root source/registration and the authored language
editions. For a new game:

1. Add `tools/data/rulebooks/<game>.json` with `source: "games/<game>.rb"`
   and the English fallback sections, following an existing root book's schema.
2. Register `<game>.json` in `tools/rulebook_sources.json` with `kind` (`class`
   or `module`), the exact Ruby container `class`, the same `source`, and
   `output: "games/generated/rulebooks/<game>.rb"`. The set of root files must
   exactly match the manifest; localized files alone cannot register a game.
3. Add complete editions in `tools/data/rulebooks/<LANG>/<game>.json` for EN,
   PL, CS, ES and RU, each with that same `source` and its `option_chapters`
   mapping. These books may have their own natural wording and chapter layout;
   edit them here, not in PO or generated Ruby. The root fallback's separate
   option mapping belongs in `tools/rulebook_option_chapters.json`.
4. Run `ruby tools/compile-rulebooks.rb`, require the generated file from the
   model (for example `require_relative 'generated/rulebooks/scopa'`), and have
   `rule_sections` return `generated_rule_sections` unless the shared family
   already supplies that method. `Base#rule_book` selects the localized edition;
   do not duplicate its language dispatch in the game. Verify the generated
   require and all editions using the registry/rulebook tests and
   `ruby tools/compile-rulebooks.rb --check`.

Root fallback text is a compiler input, not a second independent edition to
maintain instead of the authored language books. Keep its fallback rules
consistent when changing a rule, without duplicating authored prose in PO.
A new game needs a complete book in every supported
language. Write naturally for that language instead of copying another language's
sentence patterns. New rules follow the editorial guide regardless of author
credits. Preserve ready-to-use rules supplied or selected by the creator unless
editing is requested; distinguish them from reference material as the guide explains.
Do not add manually maintained interface JSON translation fragments.
Details: `docs/TRANSLATIONS.md`.

## 6. Write tests

The minimum set covers:

- a correct start at the minimum and maximum player counts;
- a legal and an illegal move;
- a match played through to completion;
- deterministic replay;
- the actual native surface and basic shortcuts, with selected defaults,
  Enter, Escape, editable text keys, stable focus and the ordered speech/cues;
- both directions of playable-card navigation, no move, list wrapping, and
  the cases of one and multiple actions for the same physical card;
- the bot, if supported;
- a regression for every bug being fixed.

These are categories of evidence, not permission to replace a native/live
walkthrough with an all-bot simulation. Complete the applicable
[acceptance checklist](GAME_ACCEPTANCE.md), including an ordinary player round,
waiting/observer behavior and the variant's distinct path. Check long-session
cost/resource lifetime if the implementation retains history, workers, timers
or search state. Use current `AGENTS.md` test-scope instructions: run affected
game/shared scenarios during development, and the full runner for a new-game
PR when that broader run is authorized. Report an unavailable dependency,
timeout, skipped scenario or unperformed live path explicitly, never as a pass.
