# Card hands

This contract applies only to controls marked as actual card hands. Boards,
dice, action lists and other lists retain their own navigation.

## Behavior

- Left/Right jumps immediately to the first displayed card of the next/previous
  suit or colour, cycling through present groups in the game's declared order,
  independently of the current sort, direction or first occurrence. It reads
  the group name and card once. Up/Down retains native whole-list navigation:
  it visits every displayed card in order, crossing suit/colour boundaries,
  including in an interleaved rank/acquisition order. Horizontal jumps never
  filter, sort, hide cards or restrict later vertical movement. Appended commands
  follow the hand's last displayed card; Up returns to that card, not the last
  card of a remembered suit. Home/End, PageUp/PageDown and modified arrows
  retain their native meaning; editors and non-hand lists are unaffected.
- After playing a card: select the nearest remaining card above it. If none
  exists, select the next one below. For A B C D: playing D selects C, B selects
  A, and A selects B.
- After playing a packet, skip all removed cards.
- Drawing takes precedence over playing in the same update; select the last
  card actually received, not the last card in the sort order.
- A `CardZoneSpec` may explicitly set `select_drawn: false` to preserve the
  selected physical card or command when drawing. Duck Racing uses this so
  its permanent bottom-row Roll command remains selected between turns.
  Removing a selected card still selects its nearest surviving neighbour;
  a new hand epoch still resets the selection. Other hands retain the default.
- Acquisition-order games preserve the remaining hand and append new cards at
  the bottom. Every marked game declares `default_sort` and `sort_modes`; sorted
  defaults stay active for received cards. Suit-sorted games declare `colour`,
  including Thousand, 3-5-8, Spades, Ninety-Nine, ordinary UNO
  and most of the dealt-card family. PacketCardSpec supports the same declaration
  for Makao and Poker exchange; MeldHandSpec declares it for Rummy.
  Cribbage and Scopa use `number`. An explicit player choice from that game's
  allowed modes always takes precedence.
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
- normal labels, action values and any sort keys;
- an explicit `CARD_HAND_ORDER` declaration on the registered game class,
  including games that preserve acquisition order; see the declaration below;
- `Card#navigation_group`: a `CardNavigationGroup` with a stable semantic `id`,
  localized `label` and unique integer `order` for each group, on every card,
  to enable suit/colour arrow navigation. All cards in one group agree on its
  order. Missing/conflicting orders disable these jumps for the whole list.
  `Base#standard_hand_navigation_group(rank:, suit:)` supplies ordinary suits
  and jokers; the CardGame and DealtCardGame hand helpers already use it.
  Other decks declare their own groups, including special cards (UNO wild
  cards, Tarot trumps/Excuse). Never infer groups from translated labels, rank
  sort keys or physical IDs in the control. A missing group on any card leaves
  native navigation active for the whole list, rather than stranding that card.
- `playable_card_navigation` with `card_navigation_spec`: the hand identifier,
  legal actions grouped by physical `Card#id`, and cards for which a single,
  unambiguous move may be performed automatically.

There is no need to copy cursor control, announcements or refresh handling.
`hand_order: nil` means an ordinary control outside this mechanism. Do not mark
public decks, action lists or dice as hands in future work. Changing only
the owner of the displayed hand also requires a different `hand_epoch`.

`CardHandListBox` implements suit navigation once for CardTable, packets and
meld hands in `card_hand_navigation.rb`. Its source callback reads the surface's
current displayed cards only on navigation/help, not during idle frames. A
temporary action/target picker or public-meld inspection returns nil, restoring
native list behavior and removing the suit-navigation tip until the hand returns.
The callback is installed once per control, not repeatedly on refresh. Navigation
does not emit a move or alter hand/packet IDs, epochs, selections or private state.
The native-control regression is `test/ui/card_suit_navigation_native_test.rb`;
real-game metadata coverage is `test/ui/card_suit_navigation_consumers_test.rb`.

A game must not mark a card as automatic if it requires a subsequent choice,
meld, declaration, target or packet construction. In these situations, the
shared mechanism only positions the cursor. UNO disables this feature entirely
for Straights, Interceptions, Super interceptions and Buzzer cards. Poker's
exchange-card selection and Monopoly do not use legal-play navigation.

The annotations exist in UNO, Ninety-Nine, Spades, Thousand, Makao and Poker's
exchange hand. Poker still advances to the next phase after exchange
confirmation: no hand list or cursor-driven card announcements are added to
the betting menu. Its separate deal announcement reads only the viewer's own
cards, after authenticated delivery in private-card games. It does not repeat
on refresh or cold reconstruction. The final view is not overridden by hand
announcements either.

For card-hand preservation, GameRoomLayout reuses a marked hand, including
when additional fields surround it. GameScreen queues the selected card's
announcement without interrupting previously announced events. Unmarked card
lists do not opt into this behavior. This is not a restriction on other
surface families: WordBoard, Taboo and DuckChallenge have their own reuse and
announcement contracts.

Manual sorting is declared through `hand_sorting_available?`, the policy's
`sort_modes` and the shared `hand_sort_shortcuts`. Cards provide semantic
`sort_keys` for the allowed modes, with physical receipt metadata retained
independently. Sorting the view does not change the game state, packet
selection order or default layout. Physical IDs and the cursor remain stable.

The dealt-card family shares `hand_for_display` and CardGame's
`hand_cards_for_display` between its default surface and headless H reminder.
Base derives `default_hand_sort`, `hand_sort_modes`, `hand_suit_order` and
`hand_rank_order` from the game's policy; `standard_hand_sort_keys` uses the
same semantic values for manual sorting, and suit navigation uses the suit declaration. Change the
policy, not three independent sorting routines. These helpers must not mutate
their inputs.
Hearts filters committed outgoing cards through `hand_for_display` until the
simultaneous exchange finishes. The original hand remains intact for the
exchange and private audit. Only the sender hears “Card passed” for a confirmed
pass event; refused actions and other players' passes do not emit it.
`hand_order` and the `none` sort keys always retain the actual received order,
and explicit manual sorting remains controlled by the shared surface.

## Declared game orders and live readouts

Every card game declares one immutable `GameRoomGames::CardHandOrder` as
`CARD_HAND_ORDER` on its concrete registered class. A standard game can use
`CARD_HAND_ORDER = PLAYROOM_HAND_ORDER`. For a distinct deck, declare its actual
presentation order, for example:

```ruby
CARD_HAND_ORDER = GameRoomGames::CardHandOrder.new(
  default_sort: 'number',
  sort_modes: %w[colour number],
  suits: %w[H S D C],
  ranks: %w[A 2 3 4 5 6 7 8 9 T]
)
```

`sort_modes` is a nonempty list drawn from `colour`, `number` and `none`, without
duplicates, and must include `default_sort`. Suit/colour and rank arrays contain
unique untranslated strings. The constructor copies and freezes all values.
`none` explicitly preserves physical acquisition order; the policy may still
declare ranks for optional manual sorting. `ACQUISITION_HAND_ORDER` is the
no-sort profile with empty keys, used by War's pile and Monopoly's deck helpers,
not permission to treat those decks as ordinary sortable hands. Non-card games
need no declaration and must not acquire card shortcuts through this contract.

The default is an initial choice of a real order, not a fourth sorting mode or
an extra user command duplicating colour/rank sorting. Variant-dependent games
override `card_hand_order(options:)` to select between immutable declared
profiles. UNO uses value order for Straights or enabled Super interceptions;
ordinary Interceptions retain colour then face, which groups exact matches.
Without those variants it keeps the existing colour order. An inactive Super
interceptions flag alone does not change the default. Pass the current game
options to `default_hand_sort(options:)` when building that hand. An explicit
allowed surface choice remains active across draws and refreshes and must not
be replaced by the variant default. Do not select an
order from the current top card or re-sort the model after every move.

Sorting shortcuts toggle against the effective active mode, including the
declared default before any manual choice. The first matching shortcut reverses
that initial order; the next restores ascending order. Switching to a different
mode starts ascending, while a command without `toggle` explicitly selects
ascending order. Acquisition order (`none`) is only restored, never reversed.
CardTable and PacketCardSurface share this decision in `CardSorting`; meld hands
inherit it. Preserve the physical cursor, prepared packet/meld order and one
direction announcement. Quiet refresh and reconstruction retain that direction.

`CardGame` rejects an absent declaration during registry validation; Base's
hand helpers also reject it instead of silently guessing. The
[catalog surface gate](../test/ui/catalog_surface_contract_test.rb) inspects
actual marked hands, including Base-derived card games: each concrete class
must declare a policy and every hand surface's `default_sort` and `sort_modes`
must agree with the policy for that replay's options. Keep this check for new
games and phases.
[Policy tests](../test/models/card_hand_order_test.rb) cover the catalog's
explicit declarations, immutable values and refusal of malformed policies.

Ordinary suits are Hearts, Spades, Diamonds, Clubs and ordinary ranks are 2–A.
Thousand, Belote and Jass deliberately retain that order regardless of trump
strength; do not move tens or trump jacks/nines to reflect trick rankings.
Bridge declares Spades, Hearts, Diamonds, Clubs and A–2 for both its own hand
and dummy. Tarot declares A–K with the knight, followed by trumps and Excuse.
Cribbage declares A–K and defaults to rank sorting; Scopa declares A–10 and
also defaults to rank sorting. Rummy declares A–K, groups by ordinary suits
and places jokers last. Scientific War retains rank order with Clubs, Diamonds,
Hearts, Spades as its equal-rank tie-break and jokers last. UNO retains its own
colour/action keys, with the variant defaults above. Blackjack,
1000 miles and Duck Racing retain acquisition-order defaults. Do not turn
War's actual pile order into a sorted hand or add sorting to Biblios pickers.

The ordinary sortable hands, including UNO, expose only `colour` and `number`.
1000 miles explicitly retains all three modes because its receipt order is a
useful separate choice. Blackjack, Duck Racing, War and Biblios retain their
existing receipt-order-only hands/pickers; Scientific War retains rank order.
A declaration does not enable a sorting UI in a game that has none.

Pass `sort_modes: hand_sort_modes` alongside `default_sort` to CardTableSpec,
PacketCardSpec and MeldHandSpec. The shared shortcuts omit disabled modes and
the surfaces reject them too, so an old callback cannot restore a removed
choice. Reconstructing or refreshing a hand drops a remembered forbidden mode
and uses its declared initial order, retaining physical cursor/packet identity.
This does not rewrite game history or add a new persistence format. Unmarked
framework fixtures may omit this metadata; real marked games may not.

Marked hand reminders carry `payload['hand_id']`. CardTable, packets and nested
composites expose `displayed_hand_cards` without replacing native controls or
including command rows; temporary pickers still return the actual underlying
hand, never their choices as cards. GameScreen asks the game's
`displayed_hand_announcement` to format these already displayed cards. This is
local presentation, not a move, server read, replay mutation or focus change.
Unmarked/absent/empty hands retain the existing announcement. Bridge preserves
its ordinary compact suit readout, honor points and public-dummy checks; a
custom interleaved order is read in that exact sequence. Blackjack retains its
chronological cards plus total, and Cribbage's public counting view is not a
substitute for the private-hand reminder. Poker's D uses the exchange hand
when present and its declared default order otherwise; H still lists players.

For example, rank order may display `2H, 3S, 4H, 5D, 6S`. Right from `4H`
selects `3S`, the first displayed Spade, even though it is above the cursor.
Down still visits the next actual row. Missing suits are skipped, and descending
or acquisition order never changes the game's horizontal suit cycle.

Regressions: `test/ui/default_hand_sorting_test.rb`,
`test/ui/hand_order_policies_native_test.rb` and
`test/ui/card_suit_navigation_native_test.rb` cover received cards, explicit
overrides, native input/readout order, unchanged controls and model state.
The [UNO native variant regression](../test/games/uno/variant_hand_order_native_test.rb)
also covers interleaved colour navigation and a last-received card under a
manual override. The deck-level [UNO order test](../test/games/uno/sort_order_test.rb)
checks every combination of the three variant flags for all three decks.

## Required hand-order regression review

Check these after the final source edit, for each changed consumer rather than
only a generic surface fixture:

- Initial deal, draw, multi-card receipt, taking a kitty and another player's
  pass all follow the declared display order. `hand_order` and `none` keys still
  represent actual received order. The last received physical ID is selected,
  including duplicate labels, except an explicit `select_drawn: false` policy.
- Colour and rank keys reflect presentation, not trick strength or card points.
  Check aces, tens, face cards, duplicate decks, jokers and special deck groups.
  Changing display order must not change legal moves, bot observations, RNG,
  authoritative hands, private audit evidence or saved event payloads.
- H and other marked hand reminders follow the currently displayed list after
  either manual sort direction and any allowed acquisition order. Preserve
  game-specific information, such as Blackjack totals, Bridge honor points and dummy privacy;
  do not replace a private hand with a public counting/target picker.
- Use Left/Right on rank-sorted and deliberately interleaved acquisition hands,
  not just contiguous colour blocks. Verify the declared cycle in both
  directions, missing groups and the first displayed matching card. Up/Down
  must still visit the entire actual list and reach appended commands.
- A quiet update reuses the native control and preserves focus, current card,
  chat/history editors and explicit sort. It neither repeats speech nor emits
  a move. The next deliberate navigation still speaks once. Selection, packet
  and meld preparation use physical IDs; sorting never reorders a prepared
  submission. A new deal, owner/dummy or hand epoch clears only stale drafts.
- When passing simultaneous cards, hide a confirmed outgoing card from the
  sender's displayed hand, not the authoritative hand needed by the exchange
  and private audit. Test refusal, partial commitment and completion; do not
  announce another player's hidden card or treat passing as drawing.
- Update affected existing tests when an approved default changes. A card-action
  fixture should select the intended physical ID, not yesterday's list index;
  separate explicit order assertions must still catch ordering regressions.
  Never make all assertions order-independent merely to turn the suite green.
- A mode omitted by the policy is absent from shortcuts, context menus and
  rulebook references. Test direct/retained commands and reconstructed local
  state too; rejecting a mode must not change focus, a prepared packet or the
  current allowed order. See [sort permissions](../test/ui/card_sort_modes_test.rb).
- Test the first sorting shortcut on a fresh default-sorted hand as well as
  repeated manual toggles: it must reverse the active default, not announce an
  unchanged ascending order. Cover both colour and rank defaults, a different
  mode, receipt-order restoration, refresh and reconstruction. The native UNO
  variant test exercises the actual key binding and its single announcement.

Captured native speech and simulated key snapshots establish control behavior,
not physical input or listening. Report live-account checks separately when the
changed risk depends on actual delivery; local-only ordering needs no unrelated
network or complete-match campaign.

## Confirming card actions

`CardZoneSpec#leading_rows` optionally supplies typed `CardListRow(id:, label:)`
information above the hand in the same native list. IDs must be nonempty and
unique within these rows; labels must be nonempty and localized. Rows have no
physical card IDs or individual actions. They remain above sorted cards and
outside `hand_order`, hand readouts, packets and legal-card navigation.
Initial focus is the first own card; Up reaches the preceding information.
The shared surface translates native row offsets before selecting a card,
opening/restoring its choices or activating an appended command. It retains a
selected informational row by ID on quiet refresh, unless a newly received
card should take focus. Only an explicit zone-wide `activation_action` applies
Enter there; otherwise the row is inert. Empty hands can still display these
rows, without becoming another player's hand. Blackjack uses them for public
dealer cards. Regressions: `test/ui/card_leading_rows_test.rb` and
`test/games/blackjack/hand_controls_native_test.rb`.

For a passive hand whose Enter decision concerns the whole hand rather than
an individual card, a zone may declare `activation_action` as a typed surface
`Action` and `activation_tip` as localized F1 help. Ordinary card activation
then emits that one action through the existing guard and executor. Without
it, card selection is unchanged; explicit card choices and appended commands
retain their own actions. Refresh replaces/clears the action and help without
replacing the control, and a temporary card-choice picker hides the default
tip. This does not bind Enter on chat, room buttons or other zones. Blackjack
uses it to stand on the current hand without a second actions list. Its cards,
physical IDs, acquisition metadata and received-card cursor still use CardTable.
See `test/ui/card_actions_test.rb` and Blackjack's native control regression.

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
