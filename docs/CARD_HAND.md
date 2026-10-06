# Card hands

This contract applies only to controls marked as actual card hands. Boards,
dice, action lists and other lists retain their own navigation.

## Behavior

- After playing a card: select the nearest remaining card above it. If none
  exists, select the next one below. For A B C D: playing D selects C, B selects
  A, and A selects B.
- After playing a packet, skip all removed cards.
- Drawing takes precedence over playing in the same update; select the last
  card actually received, not the last card in the sort order.
- Without an explicitly selected sort order, preserve the order of the remaining
  hand and append new cards at the bottom. UNO sorting remains active.
- Announcements follow the identity of the new card under the cursor. They do
  not add the label “dobrano” (“drawn”); they also cover a change to a different
  card with an identical name.
- An unchanged hand, another player's move and a technical refresh do not
  repeat the announcement. While chat, history or another field is active,
  there is no hand announcement, focus takeover or delayed message on
  returning to the hand.
- A new deal is not treated as a draw. A prepared packet or choice of how to
  play does not carry over to the next deal.
- A normal hand update preserves the existing list and form. Actual phase
  transitions retain their previous meaning and end-of-game handling.
- `Z` cycles to the next currently playable card, and `Shift+Z` to the previous
  one. The card under the cursor is spoken without rebuilding the form or
  making a network request. If there is no such card, a short message is given.
- If there is exactly one playable physical card, exactly one legal action
  for it and the game explicitly permits automation, the shortcut performs
  the same action as Enter through the normal `action_for`. Multiple ways to
  use the same card always mean cursor positioning only.

In 1000 miles with exactly two players, a playable attack has an unambiguous
opponent: Enter skips the target list, and navigation may automatically play
the only playable card under the rule above. With more players, target
selection remains explicit, even when only one opponent is currently
vulnerable to the attack. This does not apply to choosing a hazard for instant
repair or confirming a card discard. Every move still goes through the current
`action_for`.

## New games

The logic is implemented once in `lib/game_surfaces/card_hand_cursor.rb`.
CardTable and PacketCardSurface share it. A new game uses these controls
(or the `CardGame#card_hand_surface` helper) and supplies:

- unique, stable `Card#id` values for physical cards, including duplicates;
- `hand_order`: IDs in the actual hand order, with drawn cards appended at
  the end, independently of the displayed sort order;
- `hand_epoch`: the owner and deal identity, changed for a new deal;
- normal labels, action values and any sort keys.
- `playable_card_navigation` with `card_navigation_spec`: the hand identifier,
  legal actions grouped by physical `Card#id`, and cards for which a single,
  unambiguous move may be performed automatically.

There is no need to copy cursor control, announcements or refresh handling.
`hand_order: nil` means an ordinary control outside this mechanism. Do not mark
public decks, action lists or dice as hands in future work. Changing only
the owner of the displayed hand also requires a different `hand_epoch`.

A game must not mark a card as automatic if it requires a subsequent choice,
meld, declaration, target or packet construction. In these situations, the
shared mechanism only positions the cursor. UNO disables this feature entirely
for Straights, Interceptions, Super interceptions and Buzzer cards. Poker's
exchange-card selection and Monopoly do not use legal-play navigation.

The annotations exist in UNO, Ninety-Nine, Spades, Thousand, Makao and Poker's
exchange hand. Poker still advances to the next phase after exchange
confirmation: no new hand list was added to betting, nor automatic card
announcements in the betting menu. The final view is not overridden by hand
announcements either.

GameRoomLayout reuses only a marked hand, including when additional fields
surround it. GameScreen queues the selected card's announcement without
interrupting previously announced events. Other surfaces do not return such
an announcement and use the existing path.

Manual sorting is declared through `hand_sorting_available?` and the shared
`hand_sort_shortcuts`. Cards provide semantic `sort_keys` for
colour/number/none. Sorting the view does not change the game state, packet
selection order or default layout. Physical IDs and the cursor remain stable.

## Confirming card actions

The optional `Card#confirmation` supplies a ready-to-use question before the
normal Enter action. Without a question, other card games retain their
existing behavior. Confirmation uses `GameRoomUI::Form` with its `program:`
owner, defaults to “Nie” (“No”) and allows cancellation with Escape. Choosing
an opponent remains a separate step; discard confirmation does not replace it.

A `:surface` shortcut may call `selected_card_action`, passing
`hand_id`, an `actions` map keyed by physical IDs, a `confirmation` template
with a `%{card}` field, and a `shortcut` identifier. The shared surface finds
the card under the cursor after sorting, not by its label. If target selection
is open, it requires that selection to be completed or cancelled. After
confirmation, it returns one action to the normal screen path rather than
emitting it a second time.

The game declares only legal actions and does not treat confirmation as
permission to write: the current revision, runner and `action_for` are still
revalidated. In 1000 miles, Enter offers to discard only an unplayable card
that may be discarded in the current phase; J also allows a deliberate discard
of a playable card. This does not change Z navigation or other game models.

Regression tests: `test/ui/card_hand_cursor_test.rb`, `test/ui/card_actions_test.rb`,
`test/games/uno/sort_order_test.rb` and the affected card game's tests.
