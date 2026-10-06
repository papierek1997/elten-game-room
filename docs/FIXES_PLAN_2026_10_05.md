# Power Games fixes plan — 5 October 2026

Status: all eight items implemented in the sources and checked locally and
in running copies of ELTEN. Version 2.0.4.4, build 243, was rebuilt and signed
following the user's later instruction. The limits of the trials are
described at the end of this document; this is not a claim that every
possible scenario has been exhausted.

The eight items were collected at the user's request.
After being shown the current descriptions, the user clarified item 3:
the number of sets in Audio Ball and points in Categories, Spades and UNO,
in a short form without additional sentences. Item 6 brings the same short
variant description to table lists as well. Item 7 adds a local toggle for
Scrabble letter announcements. Item 8 adds muting of game sounds alone
outside the table window, independent of speech and the separate own-turn
signal.

This is a separate document. The completed `NEXT_FIXES_PLAN.md` is not
being changed, and its completed items are not being reopened.

## 1. Krowa leaderboard search includes Daily Krowa

The search within leaderboards must also find words from Daily Krowa,
not just words from the other leaderboards.

Currently, `KrowaLeaderboardClient#search_words` uses `ranked_words`,
which fetches the ordinary leaderboard. Include the daily leaderboard data
in the search and allow the correct results to be opened for the day found.
Preserve the existing search for other variants.

Do not reveal today's solution before its scheduled release. Do not
recalculate past words from the current dictionary or guess a solution
that has no reliable record.

Work areas: `games/krowa_support/leaderboards.rb` and
`games/krowa_support/server_store.rb`, and their tests.

Do not combine this item with changes to Word Tower's attempt counting.
In the completed trials on live accounts, the accepted-guess counts matched
the game state, the server record and the displayed result. A low number
of attempts for a long word does not by itself prove a counter bug.

## 2. Known languages unchecked by default and correct priority for Polish

When no custom setting exists, the “Known languages” list must be empty:
no language is checked by default. Do not automatically inherit selections
from the language list in the user's ELTEN account.

The interface language remains a separate choice. It is still used to
translate the program, but does not force itself to be checked in the known
languages list. An empty list of additional languages must not break the
primary language or the existing English fallback text when a translation
is missing.

This concerns the default value, not erasing users' deliberately saved
choices. No bulk reset of existing settings was requested.

Work areas: `lib/game_room_localization.rb`,
`lib/game_room_screens.rb`, and settings and translation tests.

### Confirmed label bug in Cat, head, tail

The user reported the Czech “Bodový limit” instead of the Polish “Limit punktów”
after selecting Czech as a known language while keeping Polish as the primary
language. This was reproduced locally using the actual catalogues and the
method that builds the game's options: without Czech the label is Polish;
after adding Czech it is Czech. The shared Polish translation of “Score limit”
exists in both cases.

The cause is the separate translation method in `games/cat_head_tail.rb`.
It first searches for an entry in the `cat_head_tail` context across all
available languages and only falls back to the shared entry if that fails.
The contextual PL entry is empty; CS contains a translation. Finding the
Czech entry stops the search before the shared Polish “Limit punktów” is
checked. This is a lookup-order bug, not a missing Polish translation or a
change to the selected interface language. Merely unchecking the default
languages will not fix the cause when they are later checked manually.

Planned order: the game's specific entry in the primary language, then the
shared entry in that same language, and only then the equivalents in additional
known languages. Preserve the priority of existing author-provided game
translations within each language; do not replace them with translations
from other games. Keep fallback-language selection working when both primary
entries are missing.

Tests must cover this case, an existing author-provided Polish entry,
a genuinely missing Polish translation and Czech selected as the primary
language. Reproduction evidence: the local helper
`tmp/cat_head_tail_language_probe_20261005.rb`. The production fix is
part of the approved implementation.

## 3. Short variant descriptions in notifications

The improvement covers both new-table notifications and invitations.
Both use the shared variant description. Preserve the existing information
and append only the agreed number and unit at the end, after a comma.
At this stage, the scope covers four games:

| Game | Information to add | Example of the intended variant suffix in Polish |
| --- | --- | --- |
| Audio Ball | Number of sets needed to win (`sets_to_win`). | “Normalny, do 3 wygranych setów” |
| Categories | Target score (`target_score`). | “Polski, 100 punktów” |
| Spades | Score limit (`score_limit`). | “Quicksand, 300 punktów” |
| UNO | Elimination score limit (`score_limit`). | “Klasyczna talia UNO, z przechwytywaniem, 500 punktów” |

Replace the example numbers with the table's actual setting. In Audio Ball,
do not present the number of sets to win as the total number of sets in the
match: first to three sets can last more than three sets. Use short forms
such as “do 1 wygranego seta”, “do 2 wygranych setów” and “do 3 wygranych setów”.
For points, “100 punktów” is enough, without “Limit punktów wynosi” or other
sentences. Preserve correct inflection of units and translations.

Do not add team information to Spades or expand descriptions of other games
as part of this agreement. The table below remains a description of
pre-implementation behaviour, not a new specification of the changed behaviour.

Do not independently add every table setting. The description must remain
short. Do not change the full settings readout under Ctrl+R as a side effect.
Missing data in a received notification must not be replaced with guessed
default settings.

Work areas: `lib/table_variant.rb`, the games' `notification_option_keys`
and `notification_variant` methods, and the shared presentation in `__app.rb`.

### Current state, checked in the sources and the local Polish formatter

The following describes only the variant suffix. The game name and sender
are separate parts of the notification. A new table has the type “Nowy stół”
(“New table”); an invitation has the title “Zaproszenie do gry” (“Game invitation”)
and a body containing the sender, table name and game with its suffix.
These are not proposals for new descriptions.

| Game | What it currently adds |
| --- | --- |
| 3-5-8 | “z wymianą kart” or “bez wymiany kart” (with or without card exchange). |
| 99 | “Żetony na początek: …” (starting tokens), e.g. 9. |
| Audio Ball | Difficulty: Bardzo łatwy, Łatwy, Normalny, Trudny or Bardzo trudny (Very easy, Easy, Normal, Hard or Very hard). |
| Axel Pong | Singles/Doubles, Classic/Arcade, difficulty; e.g. “Singiel, Classic, Normalny”. |
| Cat, head, tail | “Limit punktów: …” (score limit), e.g. 100. |
| Dominos | Tile set and individual/team play; e.g. “Podwójna szóstka, Gra indywidualna” (Double-six, Individual play). For multiple sets, also “2 ×” or “4 ×”. No tile count or player limit. |
| Farkle | “Limit punktów: …” (score limit), e.g. 1000. |
| Krowa | Daily Krowa, Random word, Race or Word Tower. Random word and Race also include “losowa długość słowa” (random word length) or “… liter” (letters). |
| Makao | Simple Makao, Extended Polish Makao, Makao with jokers or Custom rules. No list of individual rules. |
| Mancala | Oware, Ayoayo or Kalah. |
| Monopoly | Board name, e.g. “Plansza polska” or “Plansza amerykańska / Atlantic City” (Polish board or American board / Atlantic City). |
| Categories | Answer language: Polish or English. |
| Spades | Standard or enabled variants: No hell, Quicksand, Suicide. If more than one is enabled, lists them separated by commas. No team information. |
| Poker | Texas Hold'em or Draw poker. |
| Quiz | Language and set name, e.g. “Polski, Wiedza ogólna” or “Polski, Wiedźmin” (Polish, General knowledge or Polish, The Witcher). No question count or categories. |
| Rummy | Ordinary scoring/Elimination mode and with/without meld manipulation. |
| Scrabble | Language: Polish or English. |
| Taboo | Language and set name, currently e.g. “Polski, General”. “General” is the actual current name in this suffix. |
| Thousand | Three players; Two players and “Musiki: 2 karty” or “Musiki: 3 karty” (2-card or 3-card talons); Four players, one sits out each deal; Two teams of two. |
| UNO | Classic UNO deck/UNO No Mercy deck/UNO Flip deck and with/without interception. Ordinary and super interception share the suffix “z przechwytywaniem” (with interception); straights and the buzzer are not listed. |
| Checkers | Board size and square count: “8 na 8 (64 pola)”, “10 na 10 (100 pola)” or “12 na 12 (144 pola)”. This is the current wording, including the inflection of “pola”. |

No additional variant description: Biblios, Ludo, Four in a Row,
Tic Tac Toe, Mexican Train, Reversi, Battleships, Chess, War,
Scientific War and Yahtzee. Notifications still contain the game name
and basic information; an empty suffix does not mean an empty notification.

## 4. Audio Ball — alternating the starter of successive sets

After a set ends, the other player must start the next one: A, B, A, B, etc.,
relative to the player randomly chosen to start the first set. Do not base
this on the winner or whether the number of points played is odd or even.

The current server selection follows the first server and the count of all
rallies (`first_server` and `rally / 2`), without separately accounting for
the start of a new set. Separate set alternation from the existing changes
of server within a set. Also check the realtime client, announcements and
resumption so that they agree with the replayed game state. Do not change
scoring rules or pause lengths.

Work areas: `games/audio_ball.rb` and the parts of `lib/audio_ball/`
that use the serving state.

## 5. Non-translatable Cat, head, tail title

The game title must always be “Cat, head, tail”, without translation into
any interface language. This applies to game lists, tables, notifications,
rules and all other places that present the game name.

Do not change the game's identifier, its rules or translations of ordinary
messages. Disable translation of the title itself and tidy its catalogue
entries so that later translation work does not reintroduce the problem.

Work areas: `games/cat_head_tail.rb`, places that provide the title,
and the `locale/` catalogues.

## 6. Short variant descriptions in table lists

In the widget's table list and in “Join a table” for the selected game,
display the same short variant description agreed for notifications in
item 3. This applies to every game with such a description, including the
new suffixes for Audio Ball sets and Categories, Spades and UNO points.

Preserve the existing information in each table row and add the variant
description without repeating the game name, using full sentences or listing
every setting. Games without a short description must not receive an empty
suffix or an unnecessary separator.

Use shared description generation for lists and notifications, not separate
lists of settings or translations. Derive the description from the available
table data; do not add a separate network request for each row or for arrow-key
presses. Do not guess the variant when data is missing.

The full settings under Ctrl+R and the detailed participant list under Ctrl+W
remain unchanged. After a list refresh, the description must reflect the
table's current settings while preserving selection and the existing refresh
rules.

## 7. Local announcements of letters placed and removed in Scrabble

Add optional announcements for changes visible in the public preview of
a move being composed, before the word is submitted. Polish examples:
“peterman kładzie G na G7” and “peterman zabiera G z G7”
(peterman places G on G7 and removes G from G7).

Announcements are off by default. In Scrabble, Ctrl+P toggles them directly
on or off and briefly confirms the new state. It does not open settings or
another selection dialog. Do not create a separate Scrabble settings interface
for this one option. Describe the shortcut in the game's help.

The choice is local and saved in local preferences: each participant or
spectator controls only their own readout. It is not a table setting and does
not change anyone else's preferences or the board preview itself. Use existing
draft updates; do not add new network requests or reveal unplaced rack letters.

Announce actual letter placement and removal without repeating the same
announcement on refresh, duplicate delivery of an update or return to the
window. Enabling the option must not read out the entire existing draft.
Submitting a word must not be presented as removing all its letters merely
because the draft was transferred to the committed board. Preserve existing
confirmations of the user's own actions without reading the same action twice.

## 8. Muting game sounds outside the table window

In “General”, alongside the speech and own-turn signal settings, add a local,
saved list labelled “Wyciszaj dźwięki gier po przejściu do innego okna”
(“Mute game sounds after switching to another window”), rather than a checkbox.
Three choices:

- “Wszystkich gier” (“All games”).
- “Tylko gier audio” (“Audio games only”).
- “Nie wyciszaj” (“Do not mute”) — the default.

“Audio games only” covers Axel Pong and Audio Ball. In this mode, sounds from
other games, including Krowa's music, are not muted by this setting.
“All games” covers those other games too. “Do not mute” preserves the
existing audio behaviour.

Use the same background detection rules as speech: another part of ELTEN,
such as Messages or Conferences, or switching to another program. Do not
introduce a second, inconsistent way of detecting the active window.

As clarified by the user, muting covers only sounds of the games themselves:
gameplay effects, the ball and paddles, game music and recorded announcements,
such as Pong scores. It does not mute chat sounds, participant joins and
departures, invitations or new-table notifications. It does not change sounds
in other parts of ELTEN or conference conversation. The own-turn “ding” remains
controlled by its existing separate setting, including when the new game-sound
muting is enabled.

The setting operates independently of speech. It does not overwrite saved
volumes or individual games' local audio settings. It must also cover sounds
already playing when the user switches to another window, including the
looping ball and music, rather than merely preventing further recordings
from starting. On return, restore audio for the current state without playing
backlogged effects or announcements. Muting must not stop the game,
synchronisation or history updates, or change the agreed gameplay pauses.

Work areas: `lib/game_room_screens.rb`, `lib/game_room_preferences.rb`,
`lib/game_background_policy.rb`, shared playback in `lib/game_sounds.rb`
and the separate players for Pong, Audio Ball and Krowa's music. Distinguish
game sounds from table sounds; do not mute the entire application with a
single global volume setting.

### Current behaviour of the speech toggle

The verified Polish label is “Odczytuj komunikaty stołu poza jego oknem”
(“Read table messages outside its window”). Unchecking it blocks automatic
speech synthesis for new gameplay events, turn changes, scores, reminders
and new table-chat messages from others. It also covers automatic messages
from the Pong and Audio Ball clients and a game start received in the
background. The game and history continue to update.

This is not a global switch for ELTEN's synthesiser or for readouts manually
requested with a shortcut. It does not control global invitation and
new-table notifications. It does not mute effects, music, the “ding” or
recorded narrator voices: a recorded score is a sound, even when its synthesised
equivalent is governed by the speech setting. The toggle blocks new automatic
readouts; it does not itself cut off speech started before switching windows.
The game's own help window is not treated as leaving for another part of
ELTEN as long as ELTEN remains in the foreground.

## Required implementation checks

Each of the eight items must pass both targeted local tests and tests in
running ELTEN on real accounts. A local test alone does not complete any item.
Choose the number of accounts to fit the scenario: one for settings and search,
at least two for delivery of changes, chat, notifications and games, and an
additional spectator account where relevant. Check the behaviour of existing
features affected by the change, not merely the presence of the new option.
Record results, failed attempts and test limits in a local report. A blocked
or skipped scenario remains unconfirmed; it is not a pass.

Run local tests for affected areas, then trials on live accounts appropriate
to the changes: searching for an old Daily Krowa and protecting today's
solution; settings with no saved list, with custom language choices and with
a Polish interface plus additional Czech; both notification types within the
agreed scope; several successive Audio Ball sets with different scores and
both possible first servers; and the fixed game title in supported languages.
For item 6, compare the same table's description in its notification, the
widget and “Join a table”, including after changing settings and refreshing.
Check games without a suffix and confirm that navigating the lists makes
no extra requests.

For item 7, check at least two live accounts: off by default, direct Ctrl+P
toggling without a dialog, independent preferences and announcements of
letter placement and removal before submission. Include a spectator,
rejoining, duplicate updates, draft cancellation and word submission;
refreshing must not generate false actions.

For item 8, check locally and in live games a turn-based game, Pong,
Audio Ball and Krowa's music in all three list modes. Confirm that
“Do not mute” is the default and that the selected choice is remembered.
In “Audio games only” mode, also check that other games are not muted.
Switch to Messages, Conferences and outside the ELTEN window, then return,
including while a continuous sound is playing. Check independent combinations
of speech, game-sound and “ding” settings, preservation of configured volumes
and the absence of backlogged announcements on return. Confirm continued
play and updates in the background and unchanged sounds for chat, joins,
departures, invitations and table notifications. Include a spectator and the
game's own help window, without adding exceptions for a particular game.

Do not publish trial results to public leaderboards. The user's later
instruction covered rebuilding the same package and updating the changelog.
Publication on GitHub or changes to server schemas or protection were not
requested.

## Implementation outcome

The latest results of 38 distinct targeted source-test scripts are successful.
These were several runs covering affected areas, not a full run of the entire
project's test runner. The signature and consistency of all 492 installer
files with the sources, binary loading, Krowa, option forms and rules from
the package were checked separately. An older Krowa binary test initially
expected the former word count; its expectations and checks for the added
words were updated, after which the rerun passed. This did not require
changing the finished package's bytes.

Live trials used the papierek, papiertestowy, papiertestowy1 and papiertestowy2
accounts on one computer. Scrabble was checked with two players and a
spectator: the toggle, placement and removal readouts, disabling announcements,
and word submission without a false letter-removal message. Audio Ball played
three full sets, started by A, B and A in sequence; both accounts retained the
same 2:1 result. Pong underwent two separate rally-and-point trials.
Krowa's music and the ball in both audio games were checked on actual audio
streams in all three list modes. Muted continuous recordings remain running
and restore the current sound. Chat and the turn signal retain their own
settings.

In the main copy, entering “jeż” in the normal leaderboard search found the
Daily Krowa from 1 October 2026 and opened the correct leaderboard. No published
results were added or changed. Language settings, the three muting choices
and Cat, head, tail labels were checked in running ELTEN. The formatter for
both notification types received native notification objects; the list and
widget description also came from an actual table. A series of eight
notifications was not sent through the server solely to test the text.

Limits: trials were controlled through native control handlers and MCP,
not a physical keyboard or human listening. Live trials used Messages and
an inactive ELTEN window. Conferences, the game's own help, the other randomly
chosen first server and all combinations of settings were covered by local
tests of the relevant rules, not separate full server trials. This was not
a test of different computers and connections.

The 34 words supplied by the user were also added. The dictionary contains
98 221 entries; the existing text and order remained unchanged. Definitions
are still fetched from SJP on demand, with the existing no-definition message
when the online dictionary does not return one.

Our own private tables were closed and preferences changed for the trials
were restored. Current sources were left in memory in all four copies after
a normal program reload, without test helpers. Installed files, table
protection and public leaderboards were not changed. Private evidence:
`diagnostics/fixes-243-20261005` in the parent workspace.
