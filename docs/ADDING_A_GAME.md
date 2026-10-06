# Adding a game

## 1. Choose an existing model

Check the shared classes first. A board game with piece-to-square moves should
inherit from `GameRoomGames::TurnBasedBoardGame`. Other games inherit from
`GameRoomGames::Base`, but still use `GameSurfaces`, the layout, shortcuts,
history, scoring, rounds and bots.

Do not create a new layer just because one game needs an additional
action. First try extending the surface specification or adding a small,
reusable component to the existing framework.

## 2. Implement the model

Create `games/<id>.rb` and implement at least:

- `id`, `name` and `rule_sections`;
- `minimum_players` and `maximum_players`;
- `option_definitions` if the game has variants;
- events that start a match;
- `replay`, which reconstructs the state deterministically;
- `surface_spec`, which describes the accessible interface;
- `action_for`, which validates turn order, action type and all rules;
- readable history entries and error messages.

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

A turn-based game leaves `session_runner? == true`: the shared
`GameRoomSessionRunner` plans, checks freshness and writes the decision.
Do not add a second executor to `GameScreen` or the game control.
A realtime game disables this runner only when its client has its own
physics and bot loop; automatic point writes still pass through the ordinary
action-commit boundary. Keep training tools and reports in `tools/`,
not in libraries loaded by the installed game.

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

## Interface and rulebook translations

Mark English messages with `_`, `n_`, `p_` or `np_`, and enable
`using GameRoomLocalization::Translations` inside the file's root module. Rulebooks have a separate
English structure in `tools/data/rulebooks` and an option-to-chapter mapping
in `tools/rulebook_option_chapters.json`; generate them with
`ruby tools/compile-rulebooks.rb`. Then `ruby tools/translations.rb update`
adds messages to the catalogs. Translators edit only `locale/PL.po`
or another language's PO; `compile PL` creates MO and the Polish compatibility views.
Do not add new manually maintained JSON translation fragments.
Details: `docs/TRANSLATIONS.md`.

## 6. Write tests

The minimum set covers:

- a correct start at the minimum and maximum player counts;
- a legal and an illegal move;
- a match played through to completion;
- deterministic replay;
- the surface and basic shortcuts;
- both directions of playable-card navigation, no move, list wrapping, and
  the cases of one and multiple actions for the same physical card;
- the bot, if supported;
- a regression for every bug being fixed.

Finally, run `ruby test/run.rb`.
