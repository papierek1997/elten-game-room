# Forms, volume and help

`F2` lowers and `F3` raises the volume by 10 points (0–100%).
`Shift+F2/F3` selects the previous/next group: all, game, join/leave, chat,
invitations/notifications. In a new program instance, the selected group starts
at “wszystkie” (“all”). Levels are stored locally. The all-groups level is a
multiplier; it does not overwrite group levels.

Settings shows five lists of levels from 0–100%, without duplicate toggles.
A previously disabled category migrates to 0%, and an enabled one to 100%.
In Settings, the keys edit the same working values: Save commits them, and
Cancel discards them. In other windows, a change saves only the local volume.
There is no redundant write at the limit of the range.

Application resources are played through its SoundPool with the `volume`
parameter. Speech, conferences, ELTEN's interface and concurrent sound playback
are not changed. Notification presentation has only a sound path: the adapter
plays the resource at the configured volume when the host reads `sound` during
delivery, after checking whether the notification is muted or dismissed; it
returns nil so that the host does not play it a second time. Mapping alone
does not play sound.

## Option editor

The option editor changes the contents of a numeric `EditBox` through the
native `set_text`, not the nonexistent `text=`. This also applies to values
hidden when the form is built and to resetting the deck after custom mode is
disabled. The compatibility test must use the host's real `EditBox`; a stub
that adds a `text=` setter masks the error as early as table creation.
Regression test: `test/ui/game_option_editor_native_test.rb` (binary sources
or an `.eltsetup` path as an argument; EN/PL forms, creation, saving,
cancellation, custom mode and dependent Rummy settings).

## F1 and extending the interface

Use `GameRoomUI::Form` or `GameSurfaces::RefreshAwareForm` and pass
`program:` (in a shared layout, set `form.game_room_program`). Do not create
new game-specific F1/F2/F3 handling. The host handles these keys before form
events. A one-time bridge in the QuickActions dispatcher intercepts only F1,
F2, F3 and Shift+F2/F3 when the active control belongs to a waiting Game Room
form. It does not save ELTEN shortcut settings, intercept Ctrl+F1 or change
host sources. It does not retain the program in the global bridge. After
leaving or switching windows, host behavior resumes.

F1 collects `GameShortcut` entries and the screen's dynamic actions through
`GameRoomContextHelp`. The list order is game, screen, control help, history
and volume. Duplicates are removed while preserving order; replacing phase
definitions removes old entries. Chat does not receive letter-based game
shortcuts or history shortcuts that override normal text editing. The list has
one visible control; Enter/Escape closes it, and the previous cursor position
returns without rebuilding the form.

## Help during a game

F1, Ctrl+F1 and the [audio tutorial](AUDIO_TUTORIAL.md) use the shared form's
help stack. Input reaches only its topmost window; parent timers keep running.
Refresh preserves the help text, cursor and selection. The game runner,
deadlines and presentation continue through the normal path. Enter/Escape
closes help without making a move underneath. Closing the game cleans up the
entire stack and tutorial audio. The real-time surface respects
`game_room_background_help?` from the very frame that opens help.

## Navigating the rules

`GameRoomRules::Document` preserves sections and plain text, while
`GameRoomRules::View` adds native heading and link elements to `EditBox`.
The table of contents is level 1, and section titles are level 2. H and 1–6
move between headings, K between links; Shift reverses the direction. Enter
on a table-of-contents entry moves the cursor to the heading and reads its
title without opening a browser. External addresses still use host handling.

The rules are not parsed as Markdown: characters in paragraphs and translated
titles remain literal. The current-options document has one heading and no
table of contents. Shortcuts remain a list. Both help modes (`wait` and
`open_on`) use the same view, including a snapshot of shortcuts during play.
The regression test `test/ui/rules_native_navigation_test.rb` loads the real
`EditBox` from `ELTEN_HOST_SOURCE` and checks all games and interface languages.

## README in the main menu

README appears after Settings and before What's new. It reads a local file
included in the installer: the Polish `README.md` or the translation at
`content/readme/<LANG>.md` matching the interface language, without a network
download or a copy of the text in code. The known-languages setting does not
change the selected document. The native read-only Markdown field supports
heading navigation (H, Shift+H, 1–6) and link navigation (K, Shift+K). Enter in
the table of contents goes to the section rather than closing the window.
Escape or the Close button returns to the menu. Links to developer
documentation open its GitHub version. `test/ui/readme_test.rb` checks all
languages, their structure, headings, internal links and file selection
through the actual menu path.

## History and options

The create-table game selector and the game list under Join a table append
the game's localized `short_description` after its name. Other selectors and
individual table rows keep their existing labels. The widget reads that same
local description only on Ctrl+O or its Game description context action;
this action neither joins a table nor fetches network data.

The shared chat editor uses `TableActivityRepository::MESSAGE_MAX_LENGTH`
(2000 characters) before, during and after a game. The repository normalizes
and bounds the received text with the same limit. Keep room/chat messages in
one ordinary LiveSessions record, within its 16 KiB payload limit, including
Unicode and JSON escaping. Do not split messages or add requests for typing.

History uses `GameRoomHistory::View` and `GameRoomHistory.bind`.
`index`/`check` refer to character positions; `entry_index` identifies an entry.
Shortcuts for previous tricks or battles read historical authors without
substituting the names of the current participants.

Ctrl+Shift+S or “Zapisz historię stołu” (“Save table history”) in the menu saves
the available event and chat history to a TXT file in the selected folder.
It works before, during and after a game; it neither saves nor closes the game
itself. The file uses UTF-8 and a unique name, so another export does not
overwrite the previous one. Returning preserves focus and the unsent chat draft.

Ctrl+R reads `table_options_announcement`, based on the same definitions as
the settings document. The board game's S counter uses
`remaining_piece_counts(replay)` and the actual board, in player order.
Letter-based game shortcuts do not apply in editable chat.

Regression tests: `test/ui/volume_and_help_test.rb`, `test/ui/background_help_test.rb`,
`test/ui/background_help_native_test.rb`, `test/ui/background_help_game_screen_test.rb`
and the tests for the relevant surface and game.
