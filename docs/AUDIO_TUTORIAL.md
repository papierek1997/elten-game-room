# Audio tutorials

Ctrl+F1 opens the rules menu in the waiting room and during a game. Audio tutorial
is its last item when the game supplies sounds; it is also available from the
rules library. Games without entries keep their existing menu.

The tutorial is one native list. Arrow keys browse without autoplay. Enter or
Space plays the selected recording from the beginning, replacing the previous
sound. Changing selection or pressing Escape stops playback. Escape returns to
the same rules-menu item. The welcome is spoken before the first item as one
initial focus announcement, without a separate dialog or text field. Later
navigation and refocusing do not repeat it. Playback uses ELTEN's asset player
and Game Room sound settings.

During an active game, F1 and Ctrl+F1 (including the tutorial) are background
help overlays owned by the current game form. The native game wait and its
timers keep running. Turn-based bot decisions and automatic policies remain
owned by GameRoomSessionRunner; realtime keeps its own client. Received moves,
deadlines and durable writes follow the normal game/repository path while help remains
open at the same reading position. Browsing is not a pause or extra thinking
time. Only the help control receives keyboard input; leaving it must not
serve a ball or play a card. The rules library and idle-room views retain their
ordinary modal navigation. See `UI.md` for the common contract.

## Adding another game

Override `audio_tutorial_entries` in the game class. Return an ordered array of
`GameRoomAudioTutorial::Entry.new(label: _("Description and controls"), asset: "asset_name")`.
The default implementation in `GameRoomGames::Base` returns an empty array.

Use the existing asset name without `Audio/` or an extension. Declare any new
assets in both release manifests as usual. Add UI messages with
`ruby tools/translations.rb update`, translate them in each supported
`locale/<LANG>.po`, then compile and check those catalogs. `PL` in
`ruby tools/translations.rb compile PL` selects Polish, not the only language
to maintain. Follow [the translation workflow](TRANSLATIONS.md) and review each
changed description as an instruction the player will actually hear.
No extra condition in the rules screen or game-specific UI class is needed.

An entry can optionally supply `asset_resolver: ->(program) { asset_id }`.
It is resolved only at playback, without altering table options. Keep `asset`
as the valid default asset for tooling and games without personal packs.

Audio Ball supplies its three shot sounds, preparation and successful-defence
sound. Its entries follow the listener's Ctrl+P sound pack. They are
single, centered previews of the recordings, not a simulated flight or a change
to the match. The tutorial never submits game actions or changes table options.

## Verification

Run `test/ui/audio_tutorial_test.rb`, `test/ui/audio_tutorial_integration_test.rb`,
`test/localization/audio_tutorial_localization_test.rb` and `test/ui/audio_tutorial_native_test.rb`.
The native test needs `ELTEN_HOST_SOURCE` (or the sibling `elten3` checkout).
Localization also accepts an actual installer argument and supports the existing
`ELTEN_DICTIONARY_SOURCE` setting for the host dictionary implementation.
These offline tests do not replace an audible test in ELTEN with NVDA.
The background path is additionally covered by `test/ui/background_help_test.rb`,
`test/ui/background_help_native_test.rb` and `test/ui/background_help_game_screen_test.rb`.
