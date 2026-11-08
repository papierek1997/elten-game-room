# Acceptance checklist for new and changed games

Use this for new games and variants, including contributed PRs. Agree on the
rules before changing mechanics. Review the implementation and the actual
player experience before declaring it ready, even if a simulation finishes.
Apply the sections relevant to the change; record any unverified path.

## Walk through a round

Start a default table. From each seat, follow the first decision, the next
player's decision, the change of phase, settlement and the first decision of
the next round. Play one meaningful variant and one exceptional outcome
(such as a tie, fold, bust, forced pass, elimination or split pot). Use a
spectator or an uninvolved player too. Where supported, exercise the changed
path with bots, in a tournament, after return or host change, and after
restoring a saved game. Test the variant's distinct behavior, not just the
same move at more tables.

## Speech, history and access to actions

- Read or listen to the exact sequence from the player's perspective. Can
  they tell who acted, what happened, what changed, and what they can do
  next? Announce action and result, not the wording of a menu item. Name
  the recipient of a point or payment and distinguish a single winner from
  a tie. Give simultaneous or automatic phases their own status; a worker
  owned by the host is not the host's turn.
- Put information at the moment it helps: an opening hand before the
  decision, a new score after the move, a hand reveal only when the rules
  allow it. Do not repeat the same cards, instruction or result in multiple
  spoken messages. Use complete, separate history lines for separate actions.
  Ensure refresh, catch-up and switching focus do not replay live cues.
- Prefer existing native lists, cards, dice, grids, edit controls and shortcuts.
  Compare at least one established game with the same action. For example,
  use the shared Space-to-draw binding when a card game offers an ordinary
  draw. A list entry can remain discoverable without being the only way to
  perform a common action. Keep focus on the relevant control, show available
  actions only, and check F1 and the context menu. Do not consume text-editing
  keys in chat, history or other edit fields.
- Check default and alternate phases, active player, waiting player and
  spectator. A shortcut and its equivalent list action must go through the
  same validation. Check stale input after the phase or active player changes.
- Translate the complete phrases, including singular, plural and ties, in
  every supported language. Read representative native UI and history text;
  do not rely on English wording or a format-only localization check.

## Sound

Map each consequential action or outcome to a cue before shipping. Compare an
existing game: for example, check, call, raise, fold and all-in in Poker,
drawing in a card game, or throwing in a dice game. Reuse compatible assets
and the shared event presenter; verify that the event actually emits the
cue and that the asset is present in the manifest. Test compound moves too:
a raise that ends betting or a draw that ends a hand must not lose its
own cue. Do not use a draw sound for receiving points, capturing a card
or collecting a pot. Respect mute, spectator and background behavior.
If listening is possible, check volume, overlap and the order of speech and
effects. A selected sound identifier is evidence of routing, not of audible
playback or intelligibility.

## Bots

Choose moves for a reason grounded in the rules. Before writing a heuristic,
name cases in which a reasonable player would choose differently: a safe
winning stand versus catching up, which cards or dice to keep, when to
pass, and when a cost is too high. Use the variant, score, available actions,
public history and only the bot's own private information. Never consult
another hand, hidden die, dealer hole card, unrevealed answer or future
randomness. When possible, prove this by changing hidden inputs while
preserving the bot's view and comparing the chosen move and random state.

Reuse the standard bot executor, legal-action path and configured delay.
Optional actions must not become compulsory because a bot has no other
legal action at that instant. Keep planning bounded on realistic and maximum
table sizes. Test decisions on fixed informative positions, including an
obvious blunder and a case where a different action is right. Compare with
the former policy when improving an existing strategy, and finish representative
matches to check the real action, replay and result paths. An all-bot match
alone demonstrates legality, not competence.

## Rulebook and verification

Read [the editorial template](RULES_EDITORIAL.md) in full. Verify the default
game and variants against the implementation, then read the whole authorised
rulebook in each language as a new player. Follow a first turn using the
text alone; teach the necessary key beside each action. Put variants after
ordinary play, and keep technical, compatibility and release notes out of
the player instructions. Preserve author-selected wording and credits under
the template's author-text policy. Regenerate the rulebooks and translations.

Update affected tests and fixtures in the same change. Test specific
communications, legal actions, shortcuts and cue sequences as well as
mechanics. Cover replay, common presentation and the affected native
control path. For changes whose risk depends on the real service, perform
authorised live tests with the relevant accounts. Report the build or source,
scenarios, assertions, and any gaps separately: model, native-handler,
live-account, physical keyboard and listening are different kinds of evidence.
