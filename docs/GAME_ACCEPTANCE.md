# Acceptance checklist for new and changed games

Use this for new games and variants, including contributed PRs. Agree on the
rules before changing mechanics. Review the implementation and the actual
player experience before declaring it ready, even if a simulation finishes.
Apply the sections relevant to the change; record any unverified path.
For application features rather than games, use the same interaction checks
with the [feature workflow](../CONTRIBUTING.md#adding-or-changing-an-application-feature).

## Record the interaction, not just the result

For each changed path, write the expected interaction before testing and compare
the actual ordered output after the fix. This example is a local single-choice
dialog over an existing list; exact spoken strings belong to that control's
language and native tests, not a universal transcript to paste into every UI.

| Step | Expected behavior | A defect to catch |
| --- | --- | --- |
| Open from the selected parent item | One prompt; the intended default is selected | Header and focus both announce the same prompt |
| Move to another choice | The newly selected choice is read | Whole parent status is read; selection jumps back |
| Confirm | Return the actual selected value, including index zero | Selection writes immediately or a false/nil check loses the first item |
| Cancel in a fresh attempt | No action or write; preserve the parent cursor/draft | Escape leaves the table or accepts the default underneath |
| Return | Same relevant parent field; closing key is consumed | Prompt repeats or Enter activates a second action |
| Context changes while open | Revalidate current token, role and authority before use | The old dialog submits a decision for a newer phase |

The [native modal example](UI.md#single-choice-modal-dialogs) and
[its regression](../test/ui/choice_dialog_native_test.rb) demonstrate this path.
Numeric or text entry also needs native edit/copy/navigation checks, invalid
input followed by correction, and confirmation without duplicate announcements.
Use [the option-editor regression](../test/ui/game_option_editor_native_test.rb)
for that different control, rather than treating a successful picker as proof.
For asynchronous features add completion after cancel/close, refusal, retry
and unchanged refresh. Record writes and cues as well as speech and focus.

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
- Recheck the complete changed interaction after a fix, including the real
  modal control, not a mocked return value. Inspect the ordered speech log:
  one opening prompt, the edited/selected default, confirmation or Escape,
  and return to the same list item. Local menu navigation must not repeat
  the whole table status or interrupt the next prompt. Count announcements
  as well as checking that the expected words appear. Retain this as a
  targeted native regression; captured speech is not an audible listening test.
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

## Recurring integration risks

Previous game and feature integrations exposed failures outside a successful
startup or model match. Use the applicable rows below when planning and reviewing
a contribution. Inspect the complete diff against the agreed scope, not only the
files described in the PR. Do not reintroduce removed features or silently treat
a new design choice as a bug fix.

| Risk | Required targeted evidence |
| --- | --- |
| Tests use a parallel model, not the registered game | Drive the production reducer through its normal executor, legal actions, settlement and next round. A stand-alone Round/Match passing does not establish the table's behavior. Compare ordinary and private paths where the adapters differ. |
| An early result skips consequences | Follow the last action through mandatory payments, penalties, captures or disclosures before declaring the result. Check all-in, pass, simultaneous winners and partial ties, not just one ordinary winner. Assert conservation and the actual named recipients. |
| A special phase assumes an ordinary player turn | Exercise initial `nil`/missing state, automatic phases, an observing host, waiting players and unsupported bots/saves. Do not invent state fields or enable unsupported capabilities to satisfy a shared hook. |
| A valid native receipt is mistaken for a legal move | Use genuinely authenticated but rule-invalid claims/reveals, not an unauthenticated fake packet. Verify that hidden-hand obligations are audited before scoring, rejected moves do not alter the accepted sequence, and disclosure evidence survives refusal and cold replay. Follow [private state](PRIVATE_STATE.md). |
| A first round works but later ones fail or slow down | Reach a second meaningful deal/round through the real transition, including private-pool retirement, cache invalidation and reused UI. Compare equivalent decisions with growing history; verify that reconnect/cold replay does not fetch retired resources or reuse stale hands. See [benchmarks](BENCHMARKS.md). |
| An action succeeds but the native interaction is wrong | Reopen the final UI, edit/select, confirm, retry invalid input, cancel and return. Count ordered prompts, preserve the intended cursor/draft, consume closing keys and retain native text editing. A stubbed dialog result is insufficient. |
| A stored action is reported as successful after the game refused it | Race the native write against a deadline and another valid action. A stack acknowledgement proves storage, not reducer acceptance. Check the confirmed projection before clearing the matching draft or signalling success, without forcing a second server poll. Auction closing speech must not invite input after the model has already closed. |
| The same move means different things in different views | Compare both player perspectives, observer view, board/card labels, speech, history/export, user scores and tournament results. Keep coordinate orientation and player-visible score units consistent; a team total is not a per-member sum. |
| Default, manual and received-card orders diverge | Require the concrete game's `CARD_HAND_ORDER`; compare the initial hand, draws/kitty/passes, both manual directions and the current-list reminder. Use physical IDs for actions and retain independent order assertions. Follow the complete [hand-order review](CARD_HAND.md#required-hand-order-regression-review), including interleaved Left/Right, whole-list Up/Down and unchanged focus/drafts. |
| A new table silently restores old content selections or the wrong language | Reopen creation with a different interface language and a previous non-default selection. Verify the feature's agreed persistence policy, language-matched general set and English fallback when unavailable. Check cancelled edits, Back, re-entry and tournament-fixed settings separately; unrelated remembered options must not be reset. |
| An audio replacement adds a new event or changes unrelated games | For each family consumer, list its pre-existing triggering events and replace only those cues. Check zero/score/bonus/win/tie, compound cues, variants and optional-effect gates through actual playback. Reusing a helper does not authorize extra cues, a global level change or different rules. |
| A bot is legal but makes obvious mistakes or grows expensive | Use informative fixed positions, permitted-information comparisons and actual executor decisions. Include rational bids/passes/discards, variant-specific choices and bounded work over longer histories; an all-bot finish is not a strategy-quality test. |
| Audio or its package is incomplete | Check the event's actual cue sequence, compound consequences, sound semantics, settings/background behavior and resource cleanup. Verify that assets and their required attribution are included by the release allowlist, not merely present in the source tree. |
| A local integration silently changes stored data or shared behavior | Preserve declared options, identity and existing data. Review the affected framework consumers, failure/retry and same-process reload boundaries. Server schema changes need the separately authorized additive/deployment process in [Contributing](../CONTRIBUTING.md#adding-or-changing-an-application-feature), not a table recreation disguised as adding columns. |

Existing regressions demonstrate the required level of evidence:
[roulette's real stake dialog](../test/games/roulette/stake_speech_native_test.rb),
[Backgammon's perspective/speech/export agreement](../test/games/backgammon/perspective_screen_test.rb),
[French Tarot's private settlement audit](../test/games/french_tarot/private_audit_test.rb),
[score-sheet partial ties](../test/games/five_dice/shared_win_test.rb),
[typing's native executor lifecycle](../test/games/mania_pisania/runner_lifecycle_test.rb)
and [billiards' growing-history cost](../test/games/billiards/strategy_cost_test.rb).
Adapt their evidence to the changed risk; do not copy their implementation or
rerun unrelated game campaigns. Add a regression for a newly discovered failure,
update affected existing expectations for an approved change and recheck the
complete final interaction after fixing it.

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

The [text acceptance gate](TRANSLATIONS.md#required-acceptance-gate-for-text-changes)
is mandatory alongside these checks: complete and naturally edited rules and
translations, option/shortcut coverage and current generated files in all
affected languages. A failing content check blocks acceptance just as a failing
mechanics test does. Automated checks do not replace the whole-text language
review or prove that a new player can follow the instructions.
