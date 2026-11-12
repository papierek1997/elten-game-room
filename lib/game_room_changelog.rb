require_relative "game_content"

module GameRoomChangelog
  STORAGE_FILE = "changelog.json".freeze
  LAST_SEEN_BUILD_KEY = "last_seen_build".freeze
  ENTRY_TEMPLATE = "Version %{version}, build %{build}".freeze

  Entry = Struct.new(:version, :build, :changes, keyword_init: true)

  ENTRIES = [
    Entry.new(
      version: "1.1.8",
      build: 221,
      changes: [
        "Quiz Party no longer stops while preparing the next question when clients receive slightly different timestamps for the same LiveSessions entry."
      ].freeze
    ).freeze,
    Entry.new(
      version: "1.1.8",
      build: 222,
      changes: [
        "Game and room updates are received even while a key is held or text is being typed. This should prevent games from occasionally getting stuck. Chat text, cursor position and selection remain unchanged.",
        "Makao draw penalties no longer return to their author when the next player is already waiting one or more turns.",
        "After a second review, 284 well-supported Quiz Party questions were restored without bringing back ambiguous questions.",
        "A What's new list is shown once after an update and remains available from the main menu.",
        "Game Room notifications use their own notice sound. Joining a table also clears invitations and notifications for that table.",
        "After playing Wild or Wild Draw Four in UNO, colours are offered in the order yellow, red, blue, green."
      ].freeze
    ).freeze,
    Entry.new(
      version: "1.1.8",
      build: 223,
      changes: [
        "The What's new list is remembered correctly after closing it and groups all changes under a single version and build heading."
      ].freeze
    ).freeze,
    Entry.new(
      version: "1.1.9",
      build: 224,
      changes: [
        "F2 and F3 adjust Game Room sound volume; Shift+F2 and Shift+F3 select a sound group. Sound settings now use separate volume levels, including a master level, without affecting speech or other ELTEN sounds.",
        "F1 opens an arrow-key shortcuts list: current game actions first, room and screen actions next, and general controls last. Enter or Escape closes the list. Native ELTEN help remains unchanged outside Game Room.",
        "In card games, Z and Shift+Z move to the next or previous playable card. A single unambiguous card may be played automatically. UNO disables this aid when Straights, Interceptions, Super interceptions by value or Buzzer cards are enabled.",
        "Makao can be announced or caught while a local bot is thinking. Bot moves now include missing joker declarations and strategically distinct card packages, and catching an unannounced Makao takes priority. The table-card shortcut before dealing now gives a clear message."
      ].freeze
    ).freeze,
    Entry.new(
      version: "1.1.9",
      build: 225,
      changes: [
        "F2 and F3 adjust Game Room sound volume; Shift+F2 and Shift+F3 select a sound group. Sound settings now use separate volume levels, including a master level, without affecting speech or other ELTEN sounds.",
        "F1 opens an arrow-key shortcuts list: current game actions first, room and screen actions next, and general controls last. Enter or Escape closes the list. Native ELTEN help remains unchanged outside Game Room.",
        "In card games, Z and Shift+Z move to the next or previous playable card. A single unambiguous card may be played automatically. UNO disables this aid when Straights, Interceptions, Super interceptions by value or Buzzer cards are enabled.",
        "Makao can now also be announced during a bot's turn, including while waiting for its move. Catching an unannounced Makao also works during that time. Bot moves now include missing joker declarations and strategically distinct card packages, and catching an unannounced Makao takes priority. The table-card shortcut before dealing now gives a clear message."
      ].freeze
    ).freeze,
    Entry.new(
      version: "1.1.10",
      build: 226,
      changes: [
        "Invitations can now be accepted from notifications after reopening Game Room. Joining a table clears its invitations; a temporary network error does not invalidate an invitation.",
        "Private tables can be selected when creating any game. They are available by invitation and do not appear in public table lists, the widget or lobby announcements.",
        "Ctrl+R reads the variant and active settings of the selected or current table without opening the rules or moving the cursor.",
        "The table creator can save an ongoing game locally with Ctrl+S, closing the table. Saved games replaces rankings in the main menu.",
        "Resuming preserves the game, settings, bots and remaining turn time, and waits for the original players. Quiz Party and Categories cannot be saved; UNO requires finishing the colour choice and Monopoly requires finishing the auction. Private and resumed tables require an up-to-date Game Room for all players.",
        "S counts discs in Reversi, men and kings in Checkers, and pieces in Chess.",
        "Monopoly bots evaluate trades using colour-group prospects and blocking opponents, rather than selling properties too easily for their purchase price.",
        "Monopoly automatically declines an unowned property purchase when the player cannot afford it, without requiring Enter. Auctions still follow the table settings.",
        "Sending and declining invitations is recorded in the room history. Declining no longer creates a separate notification or an empty notification entry."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0",
      build: 227,
      changes: [
        "Five new games: Rummy, Domino, Mexican Train, Scrabble and Taboo. Each has detailed rules and keyboard help in Polish and English.",
        "Also added Biblios by dawidpieper (Pajper): a card game of building a library and bidding at auctions, for two to four players, with bots and Polish translation.",
        "Computer players now receive randomly selected names from Polish or English lists.",
        "Rummy includes ordinary and elimination scoring, several discard-pile modes, jokers and optional manipulation of table combinations. Play against people or regular bots.",
        "Domino offers eleven tile sets, individual or team play, drawing variants and an optional turn clock. Mexican Train adds personal and public trains, opening trains and completing doubles.",
        "Scrabble is for two to four people, with Polish and English word lists, a keyboard-operated board, a private move draft and configurable invalid-word penalties. Polish uses SJP and English uses Wordnik; these are not the official tournament word lists. There are no bots.",
        "Taboo is a voice game for four, six or eight people in two teams, with 500 cards in each language. Use an external conference or voice conversation. The table master reviews and approves every turn; the game does not recognize speech and has no bots.",
        "Ctrl+X lets the table master change settings for the next game without creating another table. Ctrl+Q ends the current game after confirmation, keeping the room, participants, bots and chat, without declaring a winner.",
        "The active-tables widget no longer reloads when you press the arrows. It refreshes when you enter it, with R, and every five seconds while it has focus, preserving the selected table.",
        "You can subscribe to notifications about new public tables for selected games. Notifications are sent to online subscribers; no games are selected by default. Private and resumed tables are not announced this way.",
        "Games with bots share a move-delay setting from zero to five seconds. Zero disables the deliberate pause; UNO and Makao still default to one second. The delay cannot exceed an enabled thinking-time limit.",
        "Reversi adds optional passing even when a move exists and optional play without capturing. A non-capturing move must still touch an existing disc. P passes; voluntary passes alone do not end the game. Bots follow the selected rules.",
        "D reads rolled dice in Yahtzee and Ludo, as it already does in Farkle. Monopoly keeps its existing D shortcut. In Yahtzee, V opens your scorecard and Shift+V opens an opponent's.",
        "Farkle now finishes the current table circuit after someone reaches the score limit. The highest score wins, with shared wins on a tie. Bots take the leader and remaining turns into account; older saved games keep their original finishing rule. Based on dawidpieper's contribution.",
        "Game lists are sorted alphabetically using names in the interface language. Ninety-nine is now displayed as 99.",
        "New tables require Game Room 2.0 for all participants, so everyone uses the same game rules and table controls. Existing local saved games are retained."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0",
      build: 228,
      changes: [
        "Five new games: Rummy, Domino, Mexican Train, Scrabble and Taboo. Each has detailed rules and keyboard help in Polish and English.",
        "Also added Biblios by dawidpieper (Pajper): a card game of building a library and bidding at auctions, for two to four players, with bots and Polish translation.",
        "Computer players now receive randomly selected names from Polish or English lists.",
        "Rummy includes ordinary and elimination scoring, several discard-pile modes, jokers and optional manipulation of table combinations. Play against people or regular bots.",
        "Domino offers eleven tile sets, individual or team play, drawing variants and an optional turn clock. Mexican Train adds personal and public trains, opening trains and completing doubles.",
        "Scrabble is for two to four people, with Polish and English word lists, a keyboard-operated board, a private move draft and configurable invalid-word penalties. Polish uses SJP and English uses Wordnik; these are not the official tournament word lists. There are no bots.",
        "Taboo is a voice game for four, six or eight people in two teams, with 500 cards in each language. Use an external conference or voice conversation. The table master reviews and approves every turn; the game does not recognize speech and has no bots.",
        "Ctrl+X lets the table master change settings for the next game without creating another table. Ctrl+Q ends the current game after confirmation, keeping the room, participants, bots and chat, without declaring a winner.",
        "The active-tables widget no longer reloads when you press the arrows. It refreshes when you enter it, with R, and every five seconds while it has focus, preserving the selected table.",
        "You can subscribe to notifications about new public tables for selected games. Notifications are sent to online subscribers; no games are selected by default. Private and resumed tables are not announced this way.",
        "Games with bots share a move-delay setting from zero to five seconds. Zero disables the deliberate pause; UNO and Makao still default to one second. The delay cannot exceed an enabled thinking-time limit.",
        "Reversi adds optional passing even when a move exists and optional play without capturing. A non-capturing move must still touch an existing disc. P passes; voluntary passes alone do not end the game. Bots follow the selected rules.",
        "D reads rolled dice in Yahtzee and Ludo, as it already does in Farkle. Monopoly keeps its existing D shortcut. In Yahtzee, V opens your scorecard and Shift+V opens an opponent's.",
        "Farkle now finishes the current table circuit after someone reaches the score limit. The highest score wins, with shared wins on a tie. Bots take the leader and remaining turns into account; older saved games keep their original finishing rule. Based on dawidpieper's contribution.",
        "Game lists are sorted alphabetically using names in the interface language. Ninety-nine is now displayed as 99.",
        "New tables require Game Room 2.0 for all participants, so everyone uses the same game rules and table controls. Existing local saved games are retained.",
        "Fixed text encoding in game settings, including a Reversi checkbox crash when Game Room and ELTEN use different interface languages."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.1",
      build: 229,
      changes: [
        "Rewritten the rules of all 23 games in Polish and English, with clearer explanations, examples and descriptions of the variants and settings available in Game Room.",
        "In-game keyboard shortcuts are now an arrow-key list. During a game, it uses the same current game-field help as F1. Enter or Escape closes the list; rules remain one document with headings.",
        "Receiving new-table notifications no longer waits for disk writes, removing one source of temporary interface stalls. The occasional record of a handled table is saved in the background.",
        "New-table notifications give the owner, game and notification type without repeating New table twice.",
        "Changing the question or card language in Quiz Party and Taboo keeps focus on the language. Sets update without moving the cursor; use Tab to reach them.",
        "Card hands support Shift+C to sort by suit or colour, Shift+H by rank, and Shift+M by receipt order. Pressing C or H with Shift again reverses that sorting direction. This covers UNO, Makao, Rummy, Spades, Tysiac, 99 and Poker's exchange hand, preserving each game's default order, the selected card and card packages.",
        "Makao's F1 help now includes Shift+Enter for adding a card to or removing it from a package.",
        "Fixed mixed Polish and English text in Taboo's rules and keyboard help. Help follows the interface language, independently of the card language.",
        "Independent sound effects can play together, including the jack effect and a threshold effect caused by the same move in 99.",
        "Added sounds for banking points in Farkle, reaching exactly 33 or 66 in 99, and declaring a marriage in Tysiac.",
        "Replaced the sounds for winning and losing a whole game. A player or team now hears the defeat sound when permanently eliminated, without hearing it again at the end of that game. Round-result sounds are unchanged.",
        "The Private table checkbox is now part of the table creation form, alongside the game settings, instead of a separate window.",
        "New games are selected in the widget by default, while saved manual deselections are remembered. Older settings also enable Rummy, Domino, Mexican Train, Scrabble, Taboo and Biblios once.",
        "Domino and Mexican Train now have distinct sounds for dealing tiles, playing a tile and drawing from the boneyard.",
        "You can limit the active-tables widget and new-table notifications to your contacts. Both filters are off by default. Invitations restricted to contacts now use the same background-updated contact list.",
        "Turn-time settings are now consistent across UNO, Makao, Domino, Mexican Train, Rummy, Scrabble, 99 and Poker. The limit is off by default. Timeouts follow each game's rules and never choose and play a card for you.",
        "In 99, exceeding the turn-time limit costs one token and passes the turn to the next player.",
        "In both Poker variants, exceeding the time limit folds your hand. During the draw, an all-in player instead keeps their cards and remains in the showdown. Side pots are also settled correctly when players fold during the draw.",
        "Ctrl+R gives shorter table settings, omitting disabled clocks and delays. Domino set names are also translated in the table creation form.",
        "Keyboard help in the rules lists each game-field shortcut separately, without chat controls or global shortcuts.",
        "Reshuffling an exhausted deck during a deal now has a short announcement and its own sound in UNO, Makao, 99, Rummy and draw Poker.",
        "Score announcements under S are ordered from highest to lowest, with eliminated players or teams last. Their actual scores are preserved.",
        "Added Battleship by Dawid Pieper: two fleets, manual placement, a computer opponent, spectator boards and a final fleet check. Saving this game for later is not yet available.",
        "Added Mancala by Dawid Pieper, with Oware, Ayoayo and Kalah variants and three computer strengths. Both new games include clear Polish and English rules, keyboard help and move sounds.",
        "At the start of Battleship, each player can choose random or manual fleet placement. Random placement follows the selected fleet and ship-spacing rules.",
        "Battleship has new rocket-launch, hit and miss sounds. The next event waits for the current sound to finish, while chat and receiving moves remain available. Other games keep overlapping sound effects.",
        "After selecting a game to create a table, focus starts on the opening instructions again. Tab then moves to Private table and the game settings.",
        "Fixed the empty in-game shortcuts list opened through Ctrl+F1, including in Scrabble. It now retains the current game-field help when opening the rules.",
        "Added Krowa by paulinux: guess Polish words in the daily puzzle, solo play, Race or cooperative Word Tower, with a personal gallery and optional leaderboards."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.1.1",
      build: 230,
      changes: [
        "Tysiac can now be played by two people, with two talons of two or three cards each. A checkbox decides whether the unchosen talon and set-aside cards count for the winner of the last trick. Bots and the rules support both options. Both players need this update for the new variant.",
        "Tysiac announces when a player goes onto the barrel. Score announcements under S also identify everyone currently on the barrel, in both player-count variants.",
        "Game Room uses server time for invitation validity and shared deadlines. Game and chat history follows the server's event order, so different computer clocks no longer put those entries in a different order.",
        "Turn clocks, saved and resumed games, and the daily Krowa puzzle now use a shared time reference. Local interface and bot delays still run without extra network requests.",
        "Fixed a bot-delay error that could stop games such as Connect Four and Tic-tac-toe.",
        "Battleship reads the fleet-placement question at the start, confirms automatic placement and announces the first turn after both fleets are ready.",
        "Monopoly's board list under Shift+D includes property groups. Property lists use shorter group counts, building announcements say which house is being built, and Enter under V or Shift+V shows the current rent.",
        "Krowa has shorter setting names and updated keyboard help. F1 and the shortcuts in game rules use shorter descriptions without Press and to.",
        "Farkle no longer asks players to finish the table circuit when the last player has already reached the target and the game ends immediately."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.2",
      build: 231,
      changes: [
        "Axel Pong is not an original project by papierek. The game was originally called Dragon-Pong, was later improved by Axel and balteam, and has now been ported to ELTEN with their permission.",
        "Added Axel Pong, an audio ping-pong game for two people or a player and a bot, with Classic and Arcade Classic modes and six difficulty levels. Play with the keyboard or mouse. Ctrl+P at the table opens personal settings for automatic return and sound volumes, also available in Settings > Axel Pong.",
        "On the Game Room widget, Ctrl+N opens the game list for creating a new table.",
        "Assign ten table presets to Ctrl+1 through Ctrl+0 in Game Room > Settings > Widget. Tab to the Table shortcuts list at the end of that section. Select a shortcut with the arrows, press Enter, choose a game and confirm its options and table privacy. The assignment is saved immediately; Cancel in Settings does not undo it. The shortcuts work only on the widget and create a table without starting the match. Assignments are saved locally.",
        "In Ludo, 1 reads your pawns and 2, 3 and 4 read the other players' pawns. D says who rolled last and the number. Shift+V lists pawns in board-position order instead of grouping them by player.",
        "In Yahtzee, D reads only the dice values. Clarified the rules and the bonus for Ones through Sixes; Misery now has a Polish name.",
        "Makao allows drawing even with a playable card in all three ready-made profiles; custom rules can disable it. After drawing a playable card, Space lets you pass without drawing again. If the drawn card cannot be played, the turn ends automatically.",
        "Mexican Train no longer repeats the same required-double announcement after every turn. T still lets you check it.",
        "Added a Draw another word button to Krowa's Random word variant. It reveals the previous word and resets attempts without recording a win.",
        "Games added since version 2.0 are now selected for lobby messages, and future games will be selected automatically. Later manual deselections are remembered. This does not enable main-screen notifications."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.2.1",
      build: 232,
      changes: [
        "Added Axel Pong Doubles by budyn1211: two teams of two players, with alternating returns and shared scores. Spectators can use 1–4 to choose a player's perspective. Partners have distinguishable step and return sounds.",
        "Pong reconnects for a new match at the same table, including after changing the score target. Improved connection recovery and reduced goal-announcement delays.",
        "Pong's first table setting is now a Classic/Arcade mode list. Shift+E changes side-wall cues: off, noise or tones.",
        "Pong lets number and victory recordings finish before the next announcement. Scores beyond 21 are read in full using ELTEN speech.",
        "Pong observers can press 1 or 2 in the playfield to listen from the first or second player's perspective. This does not give control of a paddle.",
        "History and F1 help are now read-only text fields, with normal text navigation, selection and copying. Each help shortcut has its own line. Enter or Escape closes help.",
        "Use Ctrl+Comma and Ctrl+Period for the previous and next entry in the selected history category; Ctrl+Shift+Comma and Ctrl+Shift+Period change the category. Ctrl+Home and Ctrl+End read its first and last entry. These shortcuts leave normal editing intact in chat. New history entries preserve your reading position and selection."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.2.2",
      build: 233,
      changes: [
        "In Pong matches with bots, your own paddle steps respond locally instead of waiting for a network round trip, improving their smoothness for guests.",
        "In Doubles, the first player on each team uses a distinct footstep recording without an extra pitch shift. Their serves and returns are four semitones lower. Missing Polish Doubles messages have also been translated.",
        "Improved Polish UNO card names and removed commas between colour and value. Playing a buzzer card now has its own sound; announcing UNO keeps its existing sound.",
        "Rummy is now called Remik in the Polish interface and rules.",
        "Added Cat, head, tail by TD Programs: a dice game for 2–8 players. Roll an eight-sided die and decide when to bank your points. Includes bots and Polish and English rules.",
        "Ctrl+F4 reads the response time of the ELTEN server. It works on Game Room screens and its widget, without interrupting play.",
        "A removed bot no longer remains in the waiting table's team list after a previous match was stopped.",
        "Ctrl+Comma and Ctrl+Period, including their Shift variants, now navigate history while you type in chat, without changing your message or moving the cursor.",
        "The widget now supports 30 table presets: Ctrl+1–0, Alt+1–0 and Shift+1–0. Set them in Game Room > Settings > Widget, in the Table shortcuts list. Press a shortcut there to select its entry, then Enter to assign or edit it. Changes are saved immediately, independently of Cancel in Settings.",
        "When assigning teams, Shift+Up and Shift+Down swap the selected person or bot with their neighbour. The cursor follows that person, and movement stops at the ends of the list."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.2.3",
      build: 234,
      changes: [
        "Improved Axel Pong connection setup and recovery, including starting another match at the same table. Repeated connection invitations no longer interfere with an already accepted connection.",
        "Reduced delays in sending and handling serves, returns and goal notifications in online Pong. Improved synchronisation between four players in Doubles, without changing the rules or ball physics.",
        "Fixed Ctrl+F4 after updating Game Room without restarting ELTEN. It now labels HTTP and, during an active connection, Communications UDP relay ping separately. The relay ping is not the full delay between players."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.2.4",
      build: 235,
      changes: [
        "In Axel Pong Doubles, announcing the server and receiver no longer holds the match until speech finishes. This removes a cause of long pauses after a server change. The normal 2.7-second pause applies, as in Singles."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.2.5",
      build: 236,
      changes: [
        "Improved communication in Axel Pong matches with bots, in both Singles and Doubles. Adding a bot no longer routes human serves and returns through the table owner's computer.",
        "In Pong matches with bots, the goal sound no longer waits for the score to be saved on the server. All participants in these matches need this update.",
        "Removed the extra three-second delay at the start of human Pong matches. Waiting for players to connect, announcements and breaks after goals remain unchanged."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.3",
      build: 237,
      changes: [
        "Added Audio Ball by budyn1211, known on ELTEN as balteam: an audio game for two players, against another person or a bot. Recognize three shot sounds, choose the matching defence and prepare your return. Sets are played to seven points with a two-point lead; choose one, two or three sets to win.",
        "Axel Pong adds Custom score, with a field for 2 to 999 points, and Unlimited, which keeps the match going without a score limit. Both options work in Singles and Doubles, including matches with bots. Finite matches still require a two-point lead.",
        "Updated Krowa's rules, with descriptions of its modes and controls in Polish and English.",
        "New-table notifications now use a distinct sound, balanced to the existing notification volume. Invitations keep their previous sound.",
        "Opening help with F1 or the rules with Ctrl+F1 no longer stops the game. Other players' moves, bots and turn timers continue while you read.",
        "Fixed an unintended serve in Axel Pong after using chat. Keys used outside the game field no longer trigger a serve.",
        "Fixed a Game Room installation error caused by Unicode compatibility on some ELTEN runtimes.",
        "Ctrl+J on the Game Room widget now lets you accept invitations. Joining clears the related notification just as it does inside the app.",
        "You can now choose Game Room's interface language independently of ELTEN in Settings > Language. Choose your main language and additional languages to use when a translation is missing. Restart ELTEN after saving the change.",
        "Translation support by balteam (budyn1211): each language now has one editable PO file for interface text, game rules and the changelog, making it easier to add and maintain translations without changing game logic.",
        "When watching Axel Pong, C reads the selected player's name and paddle position. Victory and defeat are also heard from that player's or team's perspective at the end of the match.",
        "Team selection is now a separate step: choose the players or use Choose teams randomly, then Accept to return to the table. Start game starts the match. Everyone hears the accepted teams, which are saved for the next game. Use Choose teams in the table menu to change them.",
        "The table master can change another person's player or observer role from the Users list context menu. During a match, this changes only who will play in the next game.",
        "Starting, ending or restarting a game no longer moves you away from chat, history or the Users list. Chat drafts, text selection and the reading position are preserved."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.3.1",
      build: 238,
      changes: [
        "Game Room now keeps regular games running while you use other ELTEN windows, such as Messages or the forum. Opponents' moves, bot actions and turn timers no longer wait for you to return to the game.",
        "Game announcements and sounds also reach you while another window covers the game. This includes the waiting room: participants joining and leaving, the start of a game and the table closing.",
        "Fixed updates when Game Room is opened from another window, such as a conference. Previously, the game could show subsequent moves only after you sent a chat message.",
        "Returning to the table preserves your chat draft, cursor position and selected field. Events announced while you were in another window are not announced again.",
        "Reduced interface stalls when receiving new-table notifications for subscribed games. Existing filters, volume settings and removal of outdated notifications are preserved.",
        "Fixed a rare Makao error with jokers enabled that could interrupt the game while checking available plays.",
        "Added missing Polish messages, including the notice that Daily Krowa requires a private table.",
        "Axel Pong and Audio Ball still pause when you switch to another ELTEN window: their controls require the game field to be active. The background-play changes apply to the other games."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.4",
      build: 239,
      changes: [
        "This version requires ELTEN 3.0.4 or later.",
        "Added War and Scientific War by balteam, for two to eight players, with bots. War compares cards from a face-down deck; Scientific War lets you choose your cards and use their special powers.",
        "Added statistics by balteam: visits, started and completed games, with game and period filters. Open Statistics in the main menu. Ctrl+W on that menu's options list reads current public and private table counts and human memberships, including observers but not bots. Developer mode does not collect new statistics.",
        "In doubles Arcade Axel Pong, teammates now share their shield, as proposed by balteam.",
        "Direct P2P connections can now be enabled in Axel Pong and Audio Ball table settings. The option is off by default; enabling it reveals a P2P participant limit, defaulting to 8. If a direct connection is unavailable, the game uses the relay server.",
        "Ctrl+F4 now distinguishes HTTP ping, Communications through the relay server, and P2P. Mixed connections are reported separately.",
        "Improved detection of quick presses and held keys in Audio Ball.",
        "Invitations can be accepted with Ctrl+J or from the context menu throughout Game Room, including while playing, typing in chat, browsing history and using settings.",
        "Opening Game Room again returns to the already open window, preserving your game and message draft. Fixed inactive entries being left in ELTEN's Windows menu.",
        "Fixed opening Messages and other ELTEN windows after entering Game Room through the widget, and receiving updates for games opened this way.",
        "In Ludo, a 1 also allows leaving the base by default, but does not grant another roll. You can turn this rule off when creating a table. Position descriptions are shorter; Ctrl+C switches between player names and colours, and C reads their colour assignments.",
        "Board presentation choices in Chess, Checkers and Ludo are now remembered locally for future tables, without changing other players' preferences.",
        "Added 22 Polish bot names.",
        "Corrected many quiz questions, removing ambiguous wording and language errors and clarifying questions and answers.",
        "Added 3-5-8 by Guliwer777: a card game for three players, with trick-taking, contract selection and card exchanges between deals. You can also play against bots.",
        "Added Czech and Spanish interface translations by balteam. Choose the language in Settings > General. These translations do not include game rules. Tysiac is now called 1000 card game in English.",
        "The table master can transfer ownership to another person with Ctrl+M. Leaving no longer automatically closes the whole table: another participant takes over, including control of the bots.",
        "Participants can be replaced during a game. Select a player or bot in the Users list and press Ctrl+Shift+R. You can give their seat to a present observer or replace a person with a new bot if the game supports bots. The hand, score and team position are preserved, and the replaced person can keep watching.",
        "In games that support bots, a player who leaves is automatically replaced by a bot. They return as an observer, and the table master can give them a seat again.",
        "Saved games are stored on your account, not only on the computer where you saved them. You can resume them after signing in on another device.",
        "In Settings > General, choose whether game announcements and the sound for your turn are heard outside the table window. The same settings apply in other ELTEN windows and when you switch to another program.",
        "Table lists and the widget show more accurate participant counts and whether a table is waiting for players or a game is already in progress.",
        "Fixed creating trade offers in Monopoly. The game should no longer get stuck after announcing that a player is preparing an offer.",
        "Improved rejoining tables and updating participants, hands and turns after replacing a player or changing the table master.",
        "Fixed the card-correction and turn-replay dialogs in Taboo. In Krowa, deleted words no longer reappear after drawing another word, and Daily Krowa synchronisation now includes longer histories.",
        "Lack of access to server tables no longer blocks the entire Settings window. Settings that do not need that access remain available.",
        "Reduced unnecessary calculations when updating games and planning bot moves, and limited the retention of unneeded data from tables you have left."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.4.1",
      build: 240,
      changes: [
        "Added a Russian interface and a Russian pack of 36 quiz questions by Danil (Kostenkov-2021). Choose the interface language in Settings > General, and the question language when creating a table.",
        "Added Daily Krowa rankings by paulinux. You can publish results and browse rankings for individual days. Today's solution remains hidden; you can view the word for earlier days.",
        "Krowa's Word Tower now allows more attempts and includes eight new nouns. A custom dictionary is available only in the single-player Random word mode, not in Daily Krowa.",
        "Reduced interface stalls on slow connections. While a move is being sent, you can still browse available information and use help. In arcade games, waiting for a score to be saved no longer blocks local paddle movement.",
        "The widget and join list hide tables with a game in progress after 45 minutes without activity. This does not close the table; resuming the game or chat makes it visible again.",
        "Ctrl+W on a selected table in the widget or join window reads its players and observers without joining it.",
        "Press Enter on a person in the table's Users list to open ELTEN's standard user menu, where you can send a message, call them or add them to your contacts.",
        "Improved Ludo announcements. Your choice of player names or colours now also applies to moves, turn announcements, scores and history. Move descriptions are shorter and omit unnecessary piece numbers.",
        "Corrected move geometry and square numbering in Checkers on 8 by 8, 10 by 10 and 12 by 12 boards.",
        "Fixed watching an ongoing rally in Axel Pong after joining a match already in progress.",
        "Removed the rustling sound at the start of Audio Ball's standard high-ball sound. The Audiodisc sound pack is unchanged.",
        "Farkle now correctly recognises a five-dice straight together with an additional scoring die.",
        "In Categories, after using the entire alphabet, you can continue playing with the letters available again.",
        "Fixed resuming larger saved games, including Scrabble, and a case where a failed save left the game paused.",
        "Fixed selecting the next table master after successive games at one table, and safeguards when switching to another table through an invitation.",
        "In the 1000 card game, an invalid play record no longer prevents subsequent valid moves from being replayed.",
        "Corrected messages about the required number of players and the current number of users at the table, thanks to balteam."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.4.2",
      build: 241,
      changes: [
        "Opening a menu no longer holds back game updates, chat, announcements or sounds. This also applies to the waiting room, including participants joining and the start of a game.",
        "Axel Pong and Audio Ball now keep running behind Messages, the forum and other ELTEN windows, like the other games. Their controls work only in the game field: switching windows does not pause the ball or protect you from losing a point.",
        "F2 and F3 change sound volume immediately, without waiting for settings to be saved. Changes also affect sounds that are already playing.",
        "In Axel Pong, a held arrow resumes moving the paddle without an additional key-repeat delay after a brief stall.",
        "Improved establishing and restoring connections in Axel Pong and Audio Ball, including doubles and games with observers. Renewing a connection no longer restarts an ongoing local rally against bots.",
        "Fixed an error when opening Krowa's Word Tower before the first word was ready.",
        "In Scrabble, other players and observers can now follow letters being placed, moved or removed before the word is confirmed. The rest of the rack remains hidden, and points are awarded only after a valid move is confirmed.",
        "In Scrabble, Shift+1 to Shift+7 places the corresponding rack tile on the selected board square. The shortcut follows the current rack order; a blank still asks which letter it represents. Enter placement and the 1 to 7 tile-reading shortcuts remain available.",
        "Scrabble board descriptions now read the letter before its coordinates, followed by its points, for example G, H8, 3 points.",
        "Updated the Russian translation by Danil (Kostenkov-2021) and corrected translations of River in Categories and Poker.",
        "Simplified Game Room settings labels, thanks to balteam. Select all games and Deselect all games now consistently do what their names say, including when used repeatedly or from the context menu.",
        "Axel Pong's local settings are available at its table with Ctrl+P or from the table menu. They are no longer duplicated in Game Room's general Settings window.",
        "Reduced periodic game and interface stalls caused by statistics collection, including in Axel Pong and Audio Ball.",
        "Statistics now include all records in the selected date range, even for larger histories. Fixed incomplete counts of started and completed games.",
        "The game, chat, announcements and sounds now continue while you decide whether to leave the table. Choosing No or pressing Escape returns to the same game without reconnecting.",
        "When opening Game Room, you can download and install a newer version available in ELTEN. Updating is optional: choosing No keeps the installed version, and an update never interrupts an open game. After updating, Game Room returns to the requested table or invitation.",
        "The Game Room code has been reorganized to make it easier to develop games and introduce further fixes. Thanks to Dawid Pieper (Pajper) for preparing these changes."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.4.3",
      build: 242,
      changes: [
        "In Axel Pong, the ball should move more smoothly between the right and left sides of the table. After a return, it should fly across smoothly instead of seemingly teleporting from one side to the other.",
        "Wall impacts and paddle movement sounds in Axel Pong are better synchronized with play, including during rapid paddle movement.",
        "ELTEN Game Room is now called Power Games. This is the same application: your settings, saved games, statistics and subscriptions remain unchanged.",
        "Daily Krowa keeps one word assigned to each day, so dictionary updates no longer change that day's puzzle or its recorded solution. New words can be drawn from the next day. Old ranking entries without a confirmed solution no longer show a guessed word.",
        "Krowa settings are available with Ctrl+P and from the table menu, like in Axel Pong and Audio Ball. The gallery can be opened before a game or after it ends, but not during play.",
        "After solving or surrendering a random word in Krowa, Start game lets you play again at the same table. Daily Krowa still allows only one start per day.",
        "Team games now show Choose teams, then Accept teams, and finally Start game. Accepting the teams does not start the match, and confirmed teams are remembered for the next game.",
        "Ctrl+R also reads a table's variant and settings before you join, both on the widget and in Join table. You do not have to enter the table to check its rules.",
        "New-table notifications and invitations include a short description of the game's most important variant settings, without reading the whole configuration.",
        "Thousand has two new variants: four individual players, with one sitting out each deal in turn, and two teams of two. Team play uses a four-card talon and shared scores, barrels and surrender penalties. Bots can play both variants.",
        "A distinct sound now accompanies a declined invitation in the sender's table history. It follows the notification volume and mute settings."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.4.4",
      build: 243,
      changes: [
        "Added a completely new Polish question set of much better quality. The questions come from existing collections based on popular television quiz shows such as Jeden z dziesieciu, rather than being invented by AI. Have fun playing!",
        "The new General knowledge set has 11 broad categories: Geography, History, Culture, Literature, Science, Nature, Religion, Sport, Language, Society and Everyday life. Each contains several hundred questions or more. Other languages and the Witcher sets are unchanged.",
        "Krowa leaderboard search now also finds words from past Daily Krowa games and opens the ranking for the matching day. Today's answer remains hidden.",
        "Known languages are now all unchecked by default, independently of the main interface language. Your saved choices are preserved. Fixed mixed-language labels in Cat, head, tail; the game's name stays the same in every language.",
        "Table lists and the widget now include the same short variant description as notifications. UNO, Spades and Categories also show the point limit, and Audio Ball shows the number of sets needed to win.",
        "In Audio Ball, players now take turns starting successive sets. Service still changes every two points within each set.",
        "In Scrabble, Ctrl+P toggles announcements of letters placed on or removed from the board before a word is submitted. This personal setting is off by default and is remembered for future games.",
        "General settings now let you mute game sounds after switching to another window: all games, audio games only, or no muting. The default is no muting. Chat and table notifications remain audible, and the turn ding keeps its separate setting.",
        "Added 60 Polish words to Krowa.",
        "Added a Power Games guide under README in the main menu, after Settings and before What's new. It covers the program's features, important shortcuts, the widget, invitations, settings and saved games. It follows your interface language: English, Polish, Czech, Spanish or Russian.",
        "Game rules now have navigable headings and a table of contents. H and Shift+H move between headings, K and Shift+K between links, and Enter on a contents link opens its chapter.",
        "Ctrl+Shift+S or the table menu now lets you save the available game and chat history to a TXT file without closing the table."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.4.5",
      build: 244,
      changes: [
        "Replaced all previous Witcher quiz sets with a new Polish set, Witcher — books. Seven categories cover characters, the plot, politics and wars, geography, magic and witchers, creatures and nature, and life and culture.",
        "The questions were checked against Andrzej Sapkowski's books, including Season of Storms and Crossroads of Ravens. The two additional stories, Droga, z której się nie wraca and Coś się kończy, coś się zaczyna, are always named in their questions. There are no questions about games or screen adaptations. The set includes spoilers."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.4.6",
      build: 245,
      changes: [
        "Quiz answers are now saved and checked faster, reducing the wait before results when everyone has answered.",
        "Shortened the Quiz confirmation to Answer sent. Removed the redundant Quiz heading and Collecting the answers announcement.",
        "Quiz now plays the UNO call sound when five seconds remain and a separate sound for a wrong answer."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.4.7",
      build: 246,
      changes: [
        "Added 1000 miles (Mille Bornes), by Patryk (Pates2004): a card race for 2 to 8 players, with bots and team play. Reach 1000 miles, obstruct your opponents and protect your car. You can also change the deck and enable additional card types. Bots wait one second by default.",
        "The widget context menu now shows command shortcuts, including Ctrl+W for table participants and Ctrl+J for invitations. Assigned table presets appear by name with their shortcuts; unassigned presets are hidden."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.4.8",
      build: 247,
      changes: [
        "Rewritten the Polish rules for all games. The explanations guide you through play and introduce the relevant keys alongside each action. Optional variants are described separately.",
        "Card effects, combinations and other lists in the rules now appear as separate items, making them easier to read and navigate.",
        "New English, Czech, Spanish and Russian rulebooks for every game.",
        "Game selection lists now include a short description of each game. In the tables widget, press Ctrl+O or choose Game description from the context menu to hear it.",
        "Table chat messages can now contain up to 2000 characters instead of 400.",
        "The main menu has a new order, with Saved games directly after Join a table. Invitations remain available through Ctrl+J and the context menu.",
        "What's new is now a read-only document with a heading for each release. Press H or Shift+H to move between releases.",
        "A saved game is removed from your account once it has been successfully resumed. Save it again with Ctrl+S if you want to continue it later.",
        "Changed the sound played when banking points in Farkle."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.4.9",
      build: 248,
      changes: [
        "Added Duck Racing, a game for two to eight players, with bots. Race around Peaceful Pond, play cards and win feathers in 18 different challenges. These include memory, sound, card and number games, as well as a single point in Audio Ball or Axel Pong. The host can choose the number of laps, available challenges and question sets.",
        "Polished the Polish game rules: clarified confusing sentences, removed unnecessary explanations and reorganized descriptions. Huge thanks to Lwica for her patient reading, for spotting so many unclear passages and for all her thoughtful language corrections!",
        "Improved the wording and clarity of the English, Czech, Spanish and Russian rules as well.",
        "Added 174 questions to The Witcher - Books set, based on suggestions from balteam. After editing and checking them against the books, the set now contains 1449 questions.",
        "Changed century numbers in the Polish general-knowledge set from Roman to Arabic numerals so speech synthesizers read them more clearly.",
        "When creating a table, the default language of questions, words or cards now follows the Power Games interface language. If that language is unavailable, English is selected. Your saved settings still take precedence.",
        "Short game descriptions are now also available when choosing a game in Game rules.",
        "Clarified the options for switching between playing and observing: the menu now makes clear whether you are changing your own role or the selected person's. If the current participants cannot start a game, the message lists the selected variant's requirements and the people signed up to play.",
        "Fixed word explanations in Krowa. If the dictionary has no definition, the program reports this instead of displaying unrelated text from the page, such as the add link.",
        "Reduced unnecessary waiting for the game to refresh after moves. When the updated game state has already arrived, it can be displayed immediately without an additional Please wait step."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.4.10",
      build: 249,
      changes: [
        "Fixed an error that could prevent Krowa from opening after Duck Racing was added.",
        "The challenge list in Duck Racing settings now reads a short explanation after each challenge's name and checked state.",
        "Duck Racing table descriptions and notifications now include the language of the question sets.",
        "Challenges with a countdown now give you five seconds to prepare before it plays. Count the ducks uses a three-second pause after the quacks, before the countdown.",
        "The Axel Pong challenge now explains the controls and waits for both players to confirm they are ready with Enter.",
        "Guess the number now draws numbers from 1 to 999. The winner takes one to five feathers according to how much closer their best guess was, using a separate scale for one-, two- and three-digit targets. Equal distances remain a draw.",
        "Shooting a duck now plays a shot at the stereo position you chose, followed by a one-word rating. A pause separates the rating from the next duck.",
        "In Duck Racing, V opens the track at your duck's current square instead of the start of the list.",
        "A message and a new sound announce when a duck begins the final lap.",
        "Lowered the challenge announcement sound and clarified the Polish messages about cards that make a duck wait for several turns."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.4.11",
      build: 250,
      changes: [
        "Added Create your own question sets to the main menu. You can suggest questions for an existing set or create your own, with categories, four answers per question and an optional source. Send your work to the author for review; sending does not add it to the game automatically.",
        "Question drafts can be saved and continued later, including on another computer using the same account. You can save unfinished questions; before sending, the creator tells you exactly which fields are missing. An unsuccessful send leaves the draft available.",
        "In the question creator, Ctrl+N creates a set from the set list or adds a question from the question list. Enter opens a set or edits a question. Short selection lists accept both horizontal and vertical arrows. README now explains how to use the creator.",
        "In Duck Racing, each player now starts Simon, Repeat the rhythm and Hit the duck independently, without waiting for everyone to confirm readiness. You can try the sounds before starting. Results are compared after everyone finishes.",
        "Reduced waiting during Duck Racing challenges, especially longer sound challenges. Games with shared turns still follow their normal turn order.",
        "Duck Racing now names the players still being waited for when confirming readiness or finishing a challenge.",
        "Fixed continuing Duck Racing challenges after resuming a saved game.",
        "In Quiz, Ctrl+B marks the current question for reporting and Ctrl+Shift+B marks the previous one without interrupting play. After leaving the table, you can describe the problem and send it to the author."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.5",
      build: 251,
      changes: [
        "Added Tournaments to the main menu, directly after Saved games. You can organize a tournament or join one, playing individually or in fixed pairs.",
        "Choose round-robin play or a group stage followed by a knockout stage. Tournaments support rematches and knockout matches played to a chosen number of wins. The program arranges matches, records game results and determines who advances.",
        "Choose Play on your match to invite the other players. They can accept from an ELTEN notification or with Ctrl+J; the program opens the table with the tournament settings. Ctrl+Shift+T gives quick access to your tournaments, also from the widget.",
        "Tournament dates are optional. The organizer can manage registration and start the tournament manually or schedule these steps. Unfinished matches are not decided automatically when a deadline passes; the organizer can award a forfeit.",
        "The match list shows the current phase, your unfinished matches first, then the other unfinished matches and completed results.",
        "README now includes a detailed tournament guide in all interface languages, covering controls, formats, scoring, partners and organizer options. Thank you to guliwer for the idea and implementation of tournaments!",
        "In the quiz question creator, the first answer is now always the correct one, followed by the three incorrect answers. When editing an older draft, its correct answer moves to the first field.",
        "When adding questions to an existing set, choose the language first, then press Enter to choose a set in a separate window. Set names no longer repeat the language code. Delete removes a selected draft after confirmation. The main-menu entry is now called Create your own quiz question sets.",
        "Question reporting with Ctrl+B and Ctrl+Shift+B now also works in Duck Racing. After leaving the table, the report form shows the question, its answers and the answer marked as correct in the set.",
        "Added seven questions to the Polish general-knowledge set, based on suggestions from bratczyk96.",
        "Thank you to Zuzler for reporting problems with quiz questions!"
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.5.1",
      build: 252,
      changes: [
        "Simplified tournament menus and removed duplicate actions. The main views are now Tournament matches, Standings, and Information and rules. Your tournaments appear first in the current list, and context menus show the available keyboard shortcuts.",
        "Organizers can invite players to register for a tournament. Notifications now also announce the end of a phase or the whole tournament and open the relevant standings.",
        "Tournament organizers can set daily playing hours, including a time range that crosses midnight. These hours restrict starting matches, not finishing games already in progress.",
        "Completed tournament matches show the game's score when available. If a scheduled rematch remains, you can invite its players directly from the completed match with Ctrl+G. Forfeit details remain available after the tournament moves to its next phase.",
        "Dice rolls and many card deals and question draws now use server-generated randomness. The rules of the games remain unchanged.",
        "Added private tournament hands in 1000 miles, Spades, Thousand, 3-5-8, 99, Poker, War, Rummy, Makao, Biblios, UNO and Bridge, as well as private tiles in Domino, Mexican Train and Scrabble. Other players, observers and the host do not receive your unrevealed hand. In tournament Taboo, only the describer and the opposing team receive the current phrase.",
        "In matches with private hands, return to the same table on the same account to recover your cards after a disconnection. Changing the host does not reveal hands. Tournament matches cannot be saved; matches with private hands also disallow bots and player replacement. Cards passed to others or returned to the deck lose this protection; README explains the exceptions. Ordinary games retain their existing bot, replacement and save options.",
        "In Duck Racing, Count the ducks now waits three seconds after the challenge announcement before playing the quacks. When several players earn the same number of feathers, their reward is announced together.",
        "Duck Racing's Audio Ball challenge now announces who is on each side. Axel Pong tells observers whose perspective they are following and who serves. Landing on a mine plays a separate sound.",
        "Added Bridge, a card game for four players in two partnerships, with bidding, contracts and rubber scoring. It supports bots, saved ordinary games and tournaments. The rules explain the controls and available variants.",
        "Poker has shorter, clearer announcements and new sounds for betting and paying out the pot. Your dealt cards are read to you, and a six-second pause between hands gives you time to hear the result.",
        "Countries and Cities now defaults to 50 points. Sounds announce submitted answers, the last 20 seconds and the end of the time limit. There is a longer pause before the next round, and the final scores remain in the history.",
        "Countries and Cities groups answers by category during assessment. The judge hears a reminder to confirm with Enter and a short confirmation when the grade is accepted. Spoken examples help distinguish the letters M and N.",
        "In ordinary Countries and Cities, a player confirmed to have left the table is removed from the game. Their answers from the unfinished round are excluded from assessment. If the judge leaves, that round is cancelled and play resumes with a new judge. If fewer than two participants remain, the game is interrupted.",
        "You can now follow more Duck Racing challenges without taking part. Spectators and racers outside the challenge hear the relevant public actions or final results, without readiness prompts or countdown sounds meant for the participants.",
        "Chat no longer rejects your message just because another player acts at the same time. Improved handling of simultaneous actions also keeps typed challenge answers and newer chat drafts from being lost during a refresh or retry.",
        "Tournament options now hide unavailable actions. Ctrl+F lets the organizer choose who forfeits and review the proposed result before confirming. For matches with more than two competing players or teams, this option is available only in games that can determine the remaining places.",
        "Fixed problems with returning to a table, retrying invitations and resuming saved ordinary games after a connection error. Private-answer games can also recover from a temporary storage error without losing an accepted answer or stopping the game permanently.",
        "Statistics load in the background, so you can change the period or close the window while waiting. Missing server data is no longer shown as zero results. If the current date cannot be confirmed, you can try Refresh again.",
        "Fixed Audio Ball's timing between sets when the match starts some time after the table is created.",
        "Clarified three questions in the Polish general-knowledge set following player reports.",
        "Started individual tournament matches pause when a player disconnects. Each player has a total of five minutes to return during the match. After that, they lose a one-on-one match or place last in a multiplayer match; the others continue if the game allows it. The organizer can also eliminate a player with Ctrl+F without ending a game that can continue.",
        "You can quickly add or remove several computer players without losing commands to Please wait, including between games.",
        "When you enter an invalid number in an action dialog, the dialog stays open, explains the problem and selects the value so you can correct it immediately.",
        "Improved interface responsiveness while loading the Daily Krowa leaderboard.",
        "Notification settings now include a blacklist. Add a user name to hide ordinary invitations from that person, or remove it to see them again. Invitations to tournament matches are not blocked.",
        "You can now hear other players' moves from their places around the table. 3D sound (HRTF) can be switched off altogether or for individual games in the sound settings."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.5.2",
      build: 253,
      changes: [
        "Fixed an error that could prevent tournament matches from starting in Axel Pong and Audio Ball."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.5.3",
      build: 254,
      changes: [
        "Added Mahjong by Guliwer: Solitaire, Hong Kong, Riichi and MCR. The multiplayer variants support computer players and tournaments.",
        "In Mahjong tournament matches, concealed tiles are private to their owner. Ordinary matches retain computer players, player replacement and saved games.",
        "Fixed tournament invitations and notifications not reaching some players because of differences in the spelling of their user names.",
        "Organizers can add their own tournament notes, shown with the rules. A Back button also lets you return to game settings while creating a tournament without losing what you entered.",
        "After a tournament's deadline, new matches cannot be created or started. Matches already in progress can still be completed, and players can return to them even outside daily playing hours. Existing results are unchanged.",
        "Tournaments whose deadline has passed stay in Current, in the same order, with the status Deadline passed. Only tournaments with all required matches resolved move to Completed.",
        "Standings now show game points scored, conceded and their difference when complete scores are available. Participants still tied are listed with fewer matches played first; this does not decide qualification.",
        "Tournament tables are now clearly marked as Tournament match in table lists, the widget and the participant heading.",
        "Automatic tournament rules are displayed in your interface language. Notes written by the organizer remain in their original language.",
        "Krowa now clears the answer field after rejecting a word with the wrong length or one missing from the dictionary.",
        "Added 185 nouns to Krowa and removed duplicate dictionary entries. Thanks to paulinux for these additions and the improvements to word definitions.",
        "Krowa explanations from SJP now choose the appropriate base noun and meaning more accurately when looking up inflected words.",
        "Added a Polish general-knowledge question proposed by turekcom and improved the wording of another following a report from Zuzler. Thank you!"
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.5.4",
      build: 255,
      changes: [
        "You can create or join an ELTEN voice conference directly from a game table. Joining remains your choice and does not interrupt the game. After joining, use Disconnect voice conversation to leave; other participants can keep talking.",
        "Tournament participants and invitations are now managed from the participant list. Organizers can invite several online users or contacts at once; Ctrl+L shows pending and declined invitations.",
        "Ctrl+T opens Tournaments from the lobby or widget. Ctrl+Shift+T opens a list of your own tournaments.",
        "Tournament organizers can now set all final places, including shared places and multiple forfeits, or award zero points to everyone. The result is shown for confirmation before it is saved. Manual settlement does not interrupt an active game.",
        "Tournament small points are enabled only in games with an agreed scoring method. UNO, elimination Rummy, Domino and Mexican Train use penalty points, where fewer is better. Audio Ball adds points from all sets.",
        "Forfeits use technical small-point scores based on the game's target and variant. A participant losing by forfeit receives zero tournament points, including when several participants share last place.",
        "Available small-point totals remain visible even if an older match has no recorded small points. Incomplete totals do not decide the order of tied participants.",
        "In knockout tournaments, awarding zero points to everyone resolves that pairing without advancing a winner. The rest of the bracket continues normally.",
        "Computer players now default to a one-second decision delay in every turn-based game. Your explicitly chosen delay is kept; realtime games keep their existing pace.",
        "New Countries and Cities games have Drink, Tool, Known athlete, Known actor and Known writer instead of Surname, Chemical element, Building, Invention and Famous person. Existing and saved games keep their categories.",
        "Reduced repeated calculations in Mahjong and Duck Racing to improve responsiveness during longer games.",
        "Fixed restoring custom Makao settings when creating another table.",
        "Krowa sound effects are enabled by default. Your saved personal settings are preserved."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.5.5",
      build: 256,
      changes: [
        "Audio Ball now supports doubles: two teams of two players, alternating returns and sharing points and sets. You can play with people or computer players.",
        "Audio Ball announces who serves and who receives. In doubles, pressing a defence key while the ball is flying to your partner gives the opponents a point, marked by a distinct sound instead of the normal goal recordings.",
        "Choosing a tournament partner now uses invitations that can be accepted, declined or cancelled. Changing a pending invitation asks for confirmation, and partnership notifications explain what changed.",
        "Agreed tournament pairs stay together. When the tournament starts, the remaining participants are paired at random, without the organizer choosing their partners. If the tournament cannot start, the program explains why.",
        "Team tournament participant lists show each team once, above unpaired players. Enter on a team opens its members, with the usual user menu available for each person.",
        "Axel Pong doubles has a personal option to keep your own footsteps and returns sounding the same in either team position, with a different sound for your partner. Open Ctrl+P to choose it.",
        "Leaving a table also disconnects its voice conference. Ctrl+Shift+M toggles your conference microphone while you are at the table.",
        "Expanded Mahjong rules explain all variants and their scoring. During play, you can check basic scoring progress and read the scoring breakdown after a completed hand.",
        "Fixed finishing places in several tournament games, including shared results and matches that end before the usual score target is reached.",
        "Improved responsiveness and recovery during simultaneous actions, background play, invitations and saved-game operations. Reduced repeated work in game updates, tournament lists and leaderboards.",
        "Added five Polish general-knowledge questions proposed by bratczyk96 and corrected several reported questions. Thank you!"
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.5.6",
      build: 257,
      changes: [
        "Added Axel Pong and Audio Ball leaderboards for singles and doubles, covering the last 7 days, 30 days, six months or year. Open a player to view wins, losses and goals; My statistics shows your all-time results. Rankings consider results, goal advantage and match length, and save completed human-only matches in the background, including tournament forfeits.",
        "Improved responsiveness in longer Mahjong games. Successive hands should no longer cause the same growing slowdown, particularly in Hong Kong.",
        "Fixed UNO rounds failing to end after stacked draw penalties returned to the first player who emptied their hand. Other players who have also played their last card are now remembered when that penalty is settled.",
        "Four of a kind in Yahtzee now scores at least 15 points.",
        "New Tic Tac Toe games randomly choose who starts. The starting player uses X.",
        "In singles, Audio Ball announces only who serves. In doubles, it still announces both the server and the receiver.",
        "Fixed an error when confirming a tournament start again.",
        "Fixed Ctrl+Shift+M at the table. It now toggles your conference microphone and announces its state. You can also mute or unmute it from the table's context menu while connected.",
        "While connected to a voice conference, Channel space appears directly after the voice conversation button. Use the arrow keys to move, and Shift+Left/Right Arrow to turn, just as in ELTEN conferences."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.5.7",
      build: 258,
      changes: [
        "Added Inferno, a seventh difficulty level in Axel Pong, faster than Nightmare. Thank you to budyn1211!",
        "Fixed paddle movement and serving after returning from the forum or another ELTEN window when Pong or Audio Ball started in the background.",
        "Leaving a table now waits for confirmation. If the connection fails, you stay at the table and can retry instead of returning to the lobby without leaving.",
        "In Yahtzee, any five-of-a-kind can now fill any unused category, even after scoring zero for Yahtzee. It scores 30 for One pair or Two pairs, 40 for the other lower categories and 50 for Yahtzee. Upper categories still count matching dice. Removed the extra 100-point bonus.",
        "In singles, the T shortcut in Audio Ball now names only the server; doubles still names the receiver.",
        "Updated Russian voice-chat labels and instructions. Thank you to Kostenkov-2021!"
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.5.8",
      build: 259,
      changes: [
        "Added Bouillabaisse, a card game for two to eight players with six rounds and changing scoring rules. Play with people or computer players, including in tournaments. Each round announces its rules; R repeats them.",
        "Added Scopa for two to six players, with Escoba, Scopone, Muerto and team play. Includes computer players, tournament play, game sounds and a short scoring breakdown after each round.",
        "Unfortunately, the Axel Pong and Audio Ball leaderboards did not meet expectations and have been disabled. Player statistics remain available under Statistics: wins, losses, goals and balances, separately for singles and doubles.",
        "After a temporary failure to read game updates, Power Games retries automatically after 5, 10 and then 15 seconds. A failed update should no longer leave the game waiting indefinitely.",
        "Ctrl+C in game history now copies selected text instead of triggering a game command.",
        "The keyboard shortcuts in game rules now include Ctrl+P wherever personal game settings are available.",
        "Corrected reported questions in the Polish general-knowledge set and removed a duplicate. Thank you to Zuzler and paulinux for the reports!",
        "Player statistics, like general statistics, are not collected, read or sent while ELTEN runs in developer mode. Previously unsent normal-mode results remain saved."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.5.9",
      build: 260,
      changes: [
        "Axel Pong and Audio Ball statistics now show matches played and an opponent list for each selected period. Press Tab to reach the list and Enter on an opponent to view head-to-head results. Singles and doubles remain separate. Thank you to Balteam!",
        "Krowa results can now include the words you tried and the number of letters in the right places. Check them in your gallery or a public result; when publishing, choose whether to share the attempt list. Thank you to Paulina!",
        "Daily Krowa attempt lists become public only on the following day. Word Tower results include attempts from each round.",
        "In Thousand, R reads the current bid or contract and who declared it. Shift+R surrenders when the rules allow it; B still reads the full bidding information.",
        "In Thousand, cards received from a talon or another player now join the hand in suit order, as in Spades. Your own sorting choice is preserved.",
        "Quiz questions now appear in a read-only text field, where Ctrl+Left/Right Arrow reads word by word. Down Arrow moves to the answer list; Up Arrow from the first answer returns to the question.",
        "Added a Polish Harry Potter question set with 985 questions about the seven books, contributed by LordKiller.",
        "Added 42 Polish general-knowledge questions from Zuzler and corrected reported questions, including wording that depended on a missing recording and abbreviations read by speech. Thank you for the questions and reports!",
        "Updated Krowa's word list with the submitted additions and removals.",
        "Short Scopa table descriptions now show the selected variants and score limit; Bouillabaisse shows whether All or nothing is enabled."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.5.10",
      build: 261,
      changes: [
        "Power Games now requires ELTEN 3.0.5 or later.",
        "Added a history and replay library under Saved games. Ctrl+Shift+S keeps a text history in turn-based games or an audio replay in Axel Pong and Audio Ball, without closing the table. Games saved for resuming have their own section.",
        "The replay player supports changing perspective and speed, seeking through actions, points and sets, and checking the score and server with S and T. Space pauses or resumes playback; Left and Right Arrow seek by five seconds.",
        "Histories and replays can be renamed, exported, imported and sent to other players. Use Import from messages in the library to open a received game. After importing, you can choose to delete its message.",
        "Added a Countries and Cities option that draws a different letter for each category.",
        "Improved notification cleanup for expired and resolved invitations. Tournament start and finish announcements no longer expire; the final announcement includes your place and the winner or joint winners.",
        "Tournament match invitations now appear regardless of invitation filters and the blacklist. Sound and quiet-mode settings still apply.",
        "When leaving a table with an active voice conversation, you can now choose Leave only the table to stay in the conversation.",
        "Fixed a chat issue where pressing Enter together with another character could leave an already sent message in the input field.",
        "Reduced the progressive slowdown in long Monopoly games with computer players, especially after many purchases and building upgrades.",
        "Clarified four reported questions in the Polish Harry Potter set, including missing context and misleading answer clues.",
        "Replaced remaining references to the old Game Room name in the interface with Power Games."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.5.11",
      build: 262,
      changes: [
        "Fixed missing paddle-hit sounds after goals in Axel Pong replays.",
        "Fixed Audio Ball replays cutting off preparation and ball-stop sounds or briefly replaying the previous flight.",
        "Completed translations of history and replay library labels in Polish, Czech, Spanish and Russian."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.6",
      build: 263,
      changes: [
        "Added Typoholism: practise typing on your own or compete with friends in four modes, using a keyboard or Braille input.",
        "Made Bridge announcements shorter, clarified bidding and improved navigation between your hand and dummy. Trump cards now use the same sound as in Spades.",
        "Added options in Tysiac to request a redeal with four nines in the initial hand or at least two nines in the talon. Use Shift+D when a redeal is available.",
        "Added sounds for surrendering and for making or missing the contract in Tysiac.",
        "Bouillabaisse rounds now end once all their scoring cards have been taken. Distinct sounds identify penalty suits, ranks and the special card.",
        "Rummy now clears the selection after an invalid card combination.",
        "Hosts can use Ctrl+Shift+P on the users list to change a person's role for the next game. Fixed an error when that person has already left the table.",
        "Expanded and improved the Russian interface, README and game rules.",
        "Reviewed reported Polish quiz questions, clarified their wording and removed an ambiguous question. Thanks to Zuzler for the reports!",
        "Clarified the language-change instructions: close ELTEN completely and start it again; restarting with F12 does not reload Power Games."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.6.1",
      build: 264,
      changes: [
        "Bridge reads your initial high-card points when you focus your own hand again, without repeating them on table refreshes.",
        "Bridge bots bid more carefully and plan their card play better.",
        "Bouillabaisse bots adapt their play to the scoring of each round, including All or Nothing.",
        "Scopa bots choose captures more carefully and are less likely to leave an easy sweep for the next player.",
        "Mahjong bots make better choices about discards, calls and when to defend."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.6.2",
      build: 265,
      changes: [
        "Added seven games: Blackjack, Blackjack Dice, Dice Poker, Liar's Dice, Go, Roulette and Bingo. Rules are available in all five languages.",
        "In Blackjack, press Space to draw a card. The new card and dice games announce turns and round results more clearly and use the familiar betting sounds.",
        "Improved the new games' computer players: they make better decisions about drawing cards, keeping dice, calling bluffs, placing stones and betting on the wheel.",
        "Poker now offers a short deck of 24 cards, from nines to aces.",
        "Added optional background music, with separate tracks for menus and for games. You can turn it on under Settings, Sounds.",
        "Countries and Cities now offers 86 categories across three difficulty levels. You can also choose your own set of categories. Thanks to Peterman for suggesting a category!",
        "Added 67 questions to the Polish General Knowledge and Harry Potter sets and corrected reported questions. Thanks to Zuzler for the submissions and reports!",
        "Corrected the Russian text in Monopoly. When two salaries are paid in a single move, both now appear separately in the history."
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.6.3",
      build: 266,
      changes: [
        "Krowa leaderboards now offer word definitions in the context menu. Closing a daily leaderboard returns to the date list with the same day selected.",
        "Typing echo now works with Braille input in Typoholism. An incomplete Braille prefix no longer ends the attempt.",
        "The table host can use Ctrl+Shift+P on their own name to choose whether to play or observe the next game.",
        "Roulette bets are grouped by type, making the lists easier to browse. The B form uses the same groups when you choose your own stake.",
        "In the quiz question creator, Delete removes the selected question from a draft after confirmation.",
        "Ctrl+F2 switches additional game sound effects on or off. Chat, notifications and the sounds needed for audio games and listening challenges are not muted.",
        "In Monopoly, computer players accept legal gifts of money or properties when nothing is requested in return.",
        "Improved performance when browsing long Monopoly games and evaluating trades.",
        "In 1000 Miles with discard recycling, the round ends if no player can reach exactly 1000 miles with the remaining distance cards. Existing points count without a finish bonus.",
        "Thanks to td-programs for the Krowa, Braille echo and table-role improvements!"
      ].freeze
    ).freeze,
    Entry.new(
      version: "2.0.6.4",
      build: 267,
      changes: [
        "Typoholism has a new Polish dictionary of 29,987 frequent word forms reviewed by paulinux. Games saved with the previous Polish dictionary cannot be resumed. Thanks to paulinux for the dictionary and braille improvements!",
        "In Typoholism, your own text remains available for reading, selection and copying during the current session, including after the round ends.",
        "Typoholism settings now offer a braille-table list. Enter saves the whole form; Escape cancels. A table change applies when the word buffer is empty, and correct braille capital indicators are accepted in all modes.",
        "Reduced repeated work in long Mahjong and Duck Racing games and when playing successive games at the same table.",
        "Improved dialog cancellation, focus and selection handling, and shortcuts using Shift or Ctrl in game fields and help.",
        "Read-only quiz questions retain text navigation and copying, while Down still moves to the answer list.",
        "Fixed Typoholism input after returning from another window. An unfinished Braille marker in own-text practice now counts as a mistake instead of cancelling practice.",
        "Blackjack, Blackjack Dice and Dice Poker bots now account correctly for side pots and tied hands.",
        "Improved Tysiac and 1000 Miles bots, and corrected decisions involving eliminated players in Farkle and Cat, Head, Tail.",
        "UNO no longer blocks a required draw when optional drawing is disabled. Fixed round completion in the No Mercy variant.",
        "Improved Poker bots with the 24-card deck and prevented excessive calculations at very high blind levels.",
        "Fixed Mahjong getting stuck after a refused tile move and corrected deal numbering in single-hand games.",
        "Fixed switching between Krowa attempt lists and loading word lists when the server returns results in smaller batches.",
        "Duck Racing bots respect the move delay in Sound Pairs and the advertised number length in Guess the Number.",
        "Tournament setup checks supported team sizes and the actual roster before starting, explains incompatible group settings more clearly and keeps bound match settings fixed.",
        "Fixed tournament partnership updates, the Operations list and handling of cancelled scheduled starts.",
        "Tournament results now count Audio Ball team goals correctly across sets and preserve tied winners in Mexican Train. Fixed team win and loss sounds in Audio Ball and Scopa.",
        "Replay names and perspectives follow player replacements during the game. Improved validation of saved games and imported histories.",
        "Fixed handling of expired table notifications and cleanup of table voice channels whose creation was not confirmed."
      ].freeze
    ).freeze
  ].freeze

  module_function

  def available_entries(current_build, entries: ENTRIES)
    entries.select { |entry| entry.build.to_i <= current_build.to_i }
      .sort_by { |entry| -entry.build.to_i }
  end

  def pending_entries(last_seen_build, current_build, entries: ENTRIES)
    available = available_entries(current_build, entries: entries)
    if last_seen_build == nil
      current = available.find { |entry| entry.build.to_i == current_build.to_i }
      return current == nil ? [] : [current]
    end
    return [] if last_seen_build.to_i >= current_build.to_i

    available.select { |entry| entry.build.to_i > last_seen_build.to_i }
  end

  def list_items(entries, translator: nil)
    translate = translator || ->(text) { text }
    entries.flat_map do |entry|
      heading = translate.call(ENTRY_TEMPLATE) % {
        version: entry.version,
        build: entry.build
      }
      [heading] + entry.changes.map { |change| translate.call(change) }
    end
  end

  def markdown(entries, translator: nil)
    entries.map do |entry|
      heading, *changes = list_items([entry], translator: translator).map { |text| GameRoomContent.utf8(text) }
      "## #{heading}\n\n" + changes.map { |change| "- #{change}" }.join("\n\n")
    end.join("\n\n")
  end
end
