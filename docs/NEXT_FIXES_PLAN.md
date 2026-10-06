# New Game Room fixes plan

Agreements from 1 October 2026. Status: all ten items implemented;
targeted tests and trials on live accounts completed. Release: 2.0.4.3/242.
Item 7 incorporates the user's corrections to the proposed notification scope.
Item 8 covers the approved team Thousand variant with a four-card talon
and scoring for surrendering a deal. Item 9 specifies the sound for an
invitation-rejection message. Item 10 provides for renaming the program
from “ELTEN Game Room” to “Power Games”.
This is a new plan, not a repeat of previously completed fixes.

### Implementation outcome

51 distinct targeted scripts have a successful final result (several stages,
not a full runner invocation). Initial failures were preserved in the reports.
Trials on four real accounts covered a full cycle of players sitting out in
Thousand, team games, bots, replacements, and saving and resuming in a new
session. The existing two- and three-player variants were also checked.

Live checks also covered Krowa's forms and restarting after both endings;
Pong and Audio Ball settings before and during a game; team selection;
reading settings without joining; changing settings and closing the selected
table; and public/private invitations and a new-table announcement.
Rejection played the new audio resource once for each sender.
Two accounts simultaneously received the same Daily Krowa assignment despite
opposite dictionary orders; history and the day boundary were checked separately.

This used one computer and one connection, input through native handlers and
forms, and the actual API/relay; it was not a listening check or physical
keyboard input on four computers. Rare scoring combinations (the barrel,
zeroes, successive surrenders) are covered by deterministic local tests,
not hours-long natural matches. The server retained its existing protection
and data; the final daily-assignment table was added, and the empty unused
measurement table and our own trial data were removed.
Private details: `diagnostics/power-games-plan-20261001/` in the workspace.

## 1. A fixed word assignment for each day

Krowa continues to use a single shared dictionary in all variants.
Each word has a stable identifier that does not change when more words are
added. The identifier must not be equated with a word's changing position
in the list.

In Daily Krowa, the word is assigned to a specific day once and remains the
same for all players. The day boundary is midnight in Polish time, determined
from server time rather than the player's computer clock. A dictionary update
during the day does not change an already assigned word.

New words participate immediately in the next draw:

- In Daily Krowa, when selecting the word for the next day.
- In other variants, at the next draw, for example when creating a game,
  drawing another word or starting the next round.

We are not creating a separate, frozen Daily Krowa dictionary or manual
activation dates for new words. A puzzle in progress retains its solution.

The leaderboard reads the saved day-to-word assignment rather than
recalculating it from the current number of words. Stable identifiers alone
are not enough: the draw's result must also be persisted. Before implementation,
establish a server-supported method for shared, durable storage that is safe
when several people start simultaneously. It must not reveal today's solution
in the ordinary interface. The user accepted an encrypted record read by
the client: this protects against accidental disclosure, but not against
someone analysing the application's code and data.

When repairing existing history, do not guess the solution from the current
dictionary. Older versions may have selected different words for the same
day; a correction requires confirmation of the puzzle actually played.

Areas to change: the word repository and daily-puzzle provider in
`games/krowa_support/`, storage of daily data and leaderboard reads.
Preserve the existing storage of the secret for an ongoing game and the
one-daily-game limit.

## 2. Krowa settings under Ctrl+P and in the table menu

Open Krowa's settings with Ctrl+P and a table-menu item, in the same place
and according to the same principle as in Axel Pong and Audio Ball.
Remove the settings button from the Tab order and replace the previous
Ctrl+D shortcut. Both new entry points open the same form.

Update the help and controls description. Use the shared mechanism for local
game settings without adding a separate Krowa-only path.
The entry points are currently in `games/krowa.rb`,
`games/krowa_support/presentation.rb` and `client.rb`.

## 3. The gallery outside an ongoing game

Krowa's gallery is available before a game starts and after it ends.
It cannot be opened during an active game, so that it cannot serve as a
source of hints. This restriction covers every entry path, not merely the
button's visibility. It does not remove collected words or change the rules
for saving new gallery entries.

## 4. Restarting Krowa at the same table

After guessing the word or surrendering in the Random word variant,
“Start game” must be available. The next game starts at the same table,
without having to create the room again.

Also check Krowa's other endings and variants so that the button is available
wherever another game may be started. Do not bypass Daily Krowa's restriction
or other intentional variant restrictions. The new game has its own word
and attempts, without carrying over the completed puzzle.

Starting point: the `restartable` flag in
`games/krowa_support/presentation.rb` and the shared game-start handling.

## 5. Clear stages of team selection

The fix concerns the shared interface for team games, not adding teams to
Krowa. When the line-up still needs to be confirmed, the sequence and labels
must be as follows:

1. At the table: “Wybierz drużyny” (“Choose teams”), instead of the misleading
   “Rozpocznij grę” (“Start game”).
2. In the selection window: “Zaakceptuj drużyny” (“Accept teams”), instead of
   “Przyjmij” (“Accept”).
3. After confirmation and returning to the table: “Rozpocznij grę” (“Start game”).

Confirming teams saves the line-up but does not itself start the game.
Preserve random and manual team selection and the remembered line-up after
the game ends. If the line-up is still valid and confirmed, do not require
another selection before every start.

Reference: the shared team form and the contract described in
[Teams, roles and focus](TEAMS_ROLES_AND_FOCUS.md).

## 6. Ctrl+R before joining a table

Ctrl+R reads the selected table's variant and settings in the widget and in
the table list under “Join a table” after a game is selected. The user can
learn the table's rules before joining.

Use the same way of describing the variant and settings as Ctrl+R inside
a table, without creating separate descriptions for each list. The readout
does not join the user to the table, change the selection or alter the
existing description of the list entry. If no table is selected, the table
has disappeared or its settings are unavailable, provide the appropriate
message without guessing values. Fetching missing data must not block the
interface or cause extra requests on every arrow-key movement.

Add the new shortcut to the help for both lists.

## 7. A short variant description in table notifications and invitations

A new-table notification and an invitation use the same short variant
description. It includes only the specified information; it is not a copy
of the full Ctrl+R readout or the current summary of all settings.
Full settings remain available on demand under Ctrl+R, including before
joining thanks to item 6.

Scope corrections specified by the user:

- Spades: only the variant, e.g. “Quicksand”. No mention of teams, score
  limits or bots.
- Poker: only the variant, e.g. “Texas Hold'em” or draw poker. No betting
  structure, stakes or token count.
- Categories: only the answer language, without the category set.
- No additional description: Mexican Train, War, Scientific War,
  Battleships, Ludo, Reversi, Yahtzee and Biblios.

“No additional description” does not remove the notification itself, the
game name, sender or indication of whether it is a new table or an invitation.
Do not replace omitted details with “standard rules”.

The remaining games retain the scope from the last proposal:

- Makao: the selected ruleset, e.g. “extended” or “custom rules”.
- UNO: Classic, Flip or No Mercy deck, and with or without interception.
- Axel Pong: singles or doubles, classic or arcade mode, and difficulty.
- Audio Ball: difficulty; do not add “classic”, currently its only mode.
- Krowa: the variant and word length if that variant allows it to be selected.
- Checkers: board size; the size alone does not declare a complete standard
  ruleset.
- Thousand: the selected variant; for two players, also the talon size.
  After implementing item 8, also include the four-player and team variants
  without elaborating on their rules in the notification.
- Rummy: ordinary or elimination, and with or without meld manipulation.
- Dominos: the tile set and individual or team play.
- Quiz and Taboo: the language of play and the set name, without the number
  of questions or cards.
- Scrabble: dictionary language.
- Monopoly: selected board.
- Mancala: variant name.
- Farkle and Cat, Head, Tail: score limit.
- 99: starting token count.
- 3-5-8: with or without card exchange.
- Chess, Four in a Row and Tic Tac Toe: no additional description.

Do not automatically add every non-default option. Do not include bot delay,
transport/P2P, sound settings or the full list of penalties and limits.
Do not call modified rules “classic” merely because they do not fit in the
short description. Limit length by selecting complete pieces of information,
not by cutting text off in the middle of a word.

Example announcement in Polish: “Papierek, Axel Pong, debel, arcade,
trudny. Nowy stół”. In an invitation, the same short description supplements
the existing information about the inviter and table. Preserve the distinction
between an ordinary invitation and resuming a saved game, and do not repeat
the game name or notification type.

During implementation, each game identifies its most important existing
settings, and the shared mechanism formats the description for both
notification types in the recipient's language. Send the necessary non-secret
values with the notification. Receiving, reading and displaying it must not
trigger another table fetch or block the interface. The description reflects
settings at the time of sending; Ctrl+R checks the current settings.
Missing data does not imply the default variant. Preserve the existing
notification filters, sounds, validity and cleanup.

## 8. Four-player and team Thousand

Add two separate variants, preserving the existing two- and three-player ones.

The four-player variant works like the current three-player game, but one
person sits out each deal. The next person sits out each successive deal;
after a full cycle, everyone has sat out once. The other three players use
the existing rules for dealing, the talon, bidding, passing cards, playing
tricks and scoring.

The person sitting out remains a player at the table, not a spectator.
They do not take part in decisions for the current deal. The interface and
messages should clearly indicate who is sitting out and account for their
return in the next deal. Do not add separate bonuses for sitting out without
agreement.

The team variant has two fixed teams of two, seated alternately.
All four participate in every deal; nobody sits out. Each sees only their
own cards. Use the existing shared team selection to set up pairs.
The user approved these rules:

- Deal 5 cards to each player and set 4 cards aside as the talon. The winning
  bidder takes the whole talon, then passes one card to each other person,
  including their partner. Everyone has 6 cards for trick play.
- All four people bid. The winning bidder commits their team to scoring the
  bid number of points. Their partner may outbid them; the existing passing
  rules remain. The bidding limit depends on marriages in the bidder's own
  hand, without counting the partner's hidden cards.
- The pair has a shared score. Add both players' points from tricks and
  marriages. The winning bidder's team gains the contract value if it fulfils
  the contract, or loses that value if it fails. The opponents add their own
  earned points using the existing rounding. Record the score once for the
  team, not separately and twice for each partner. Example: a contract of
  150 with 170 earned gives +150; earning 140 gives -150.
- Preserve the current rules: follow suit, or, if unable to do so, play a
  trump if available. There is no obligation to play a higher card.
  This also applies when the partner is winning the trick; the user explicitly
  confirmed that the existing rules must remain in the team variant.
- A marriage requires the king and queen to be in one person's hand, and
  declaring it remains subject to the existing conditions for the player
  leading. Do not form a marriage from two partners' cards or automatically
  transfer the right to declare one from one partner to the other.
- The barrel and zero counter are shared by the team. One partner scoring
  no points is not a team zero if the other scored. The target score and
  victory apply to the pair, not an individual.

The approved scoring for surrendering a deal treats the team as one
participant:

- The winning bidder may surrender after seeing the talon but before
  passing the first card.
- The opposing team receives half the bid value, at least 60 points,
  rounded up to a multiple of five. Award the bonus once to the whole
  pair, without multiplying it by the number of partners.
- The first and second surrenders do not deduct points from the surrendering
  team. Every third surrender means -120 points. The counter is shared by
  the pair, regardless of which partner won the bidding and surrendered
  the deal. Do not also deduct the value of an unfulfilled contract.
- A team on the barrel cannot surrender a deal. Opponents on the barrel
  receive no bonus, and the surrender does not consume their barrel chance.
- Do not additionally count a surrender as a zero-score deal.

Example: surrendering a contract of 150 gives the opponents 75 points
unless they are on the barrel. The surrendering pair keeps its score unless
this is its third surrender in the cycle, in which case it loses 120 points.

During implementation, extend the existing game rather than creating a
second Thousand implementation. Separate the fixed table line-up from the
participants in a particular deal; account for bots, saving and restoring,
and changes to the person occupying a seat. Update variant selection,
rules, help and the settings description.

## 9. Sound for an invitation-rejection message

When the sender is informed that an invitation was rejected, play the file
selected by the user:

`C:/Users/mateu/Documents/Freesound/110931_error2_preview-hq-ogg.ogg`

The sound must accompany the existing rejection event and its history entry.
Do not create a new system notification or an empty entry for this purpose.
Do not change the sounds for receiving an invitation or a new-table
notification. Play it once when the rejection is received, respecting volume
and mute settings, not again when refreshing or reading history.
During implementation, prepare the resource according to the project's
current audio rules; do not overwrite the specified source recording.

## 10. Renaming the program to Power Games

Change the user-visible name from “ELTEN Game Room” to “Power Games”.
Use the same name in every interface language. Cover both manifests
(`manifest.json` and the `__app.rb` header), ELTEN's program menu,
window titles, widget name, messages, help and current program descriptions.
In the next release, use the new name in the package filename and the
published program's metadata, keeping both manifests consistent.

This renames the existing application; it does not create a new program.
Preserve its identifier, author and signature, server associations, tables,
statistics, subscriptions, settings and saved games. Do not change technical
class names, setting keys or data directories for this reason. Do not blindly
replace every occurrence of “Game Room”: historical entries, external project
names and addresses remain valid. Renaming the GitHub repository or ELTEN group
is outside this item.

## Checks during implementation

Check each affected mechanism locally and on live accounts, using enough
accounts for the scenario. In particular:

- Adding words does not change today's puzzle, games in progress or previous
  assignments. New words become candidates from the next draw. Two accounts
  receive the same daily puzzle, including when starting simultaneously.
  Check the day boundary and that the solution is not revealed early.
- Ctrl+P and the table menu open the same Krowa settings; Tab does not visit
  the removed button. Pong and Audio Ball shortcuts and settings still work.
- The gallery works before and after a game, but cannot be opened during play.
- After guessing the word and after surrendering, another random puzzle can
  be started without leaving the table. Daily Krowa still enforces its start limit.
- Team selection, cancellation and confirmation have the correct labels and
  effects; accepting teams does not start a match, and a valid line-up is
  remembered.
- Ctrl+R in the widget and “Join a table” reads the correct table's settings,
  matching the readout after joining. Also check a settings change by the
  host, an empty list and a disappearing table. The readout itself does not
  create membership or change focus.
- For item 7, check both notification types, public and private invitations,
  and resuming a game. The same configuration's description must be consistent,
  short and translated for the recipient. Check missing data, long set names,
  settings changes after sending and the absence of new network work during
  notification presentation. Games marked “no additional description” must
  not receive details through the generic formatter; Spades must not add
  teams, Poker bidding details, or Categories the category set.
- Four-player Thousand: a full cycle of four deals with each player sitting out in turn,
  skipping the resting player in bidding and tricks, scoring and the next
  game. Check players and bots, saving/restoring and participant replacement.
  Separately confirm unchanged behaviour of the two- and three-player variants.
- Team Thousand: four people, 5 cards each and a 4-card talon, then 6 cards
  each without losing or duplicating any card. Check passing to the partner
  as well, outbidding them, passing, following suit and playing trump without
  an obligation to play a higher card, and marriages from one's own hand only.
  Confirm the sum of the pair's points, fulfilled and failed contracts,
  rounding of the opponents' score, the shared barrel, zeroes and victory.
  Bots must account for cooperation without access to their partner's hidden
  hand. Check saving/restoring and replacement of a human or bot without
  changing the team assigned to the seat. For surrender, check the minimum
  of 60, half the contract and rounding up, the shared counter when partners
  alternate surrendering, the penalty on every third surrender, both barrel
  cases and no additional zero or failed-contract penalty. Individual variants
  still count scores separately.
- Rejection of a public or private invitation reaches the sender with the
  correct sound and history entry, without a new system notification.
  Check one-time playback, volume and mute settings, and no repeated sound
  after refreshing or returning. Receiving an invitation and a new-table
  announcement retain their sounds.
- Power Games is the name of the same application after updating, not a second
  installation. Check both manifests, menus, widget, windows and translations;
  preservation of existing settings, macros, subscriptions, statistics and
  saved games; and launching and joining through the widget and invitations.

During implementation, update the relevant PL/EN text and help. After the
tests, rebuild and sign version 2.0.4.3, build 242, and update the changelog.
