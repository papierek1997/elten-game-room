# Local background music

Settings → Sounds contains two independent local tracks: Power Games background
and in-game background. Each has an enabled checkbox, native file picker and
0–100% volume. Both default to disabled, with no selected file. Settings are
stored only in the current user's `settings.json`, never table options or moves.
Cancel discards edits; Save verifies enabled files can be opened.

The native `Sound` decoder handles MP3, WAV, Ogg, Opus, FLAC, AAC/M4A, WMA,
AIFF, tracker formats and MIDI (MID/MIDI/RMI), subject to the host's installed
decoders. The picker filters these common formats. Native MIDI decoding was
also exercised in ELTEN 3.0.5. Unsupported or missing files are reported by the
editor; a later unavailable file is logged once per selection, not retried every
frame. There is no download or file conversion during playback.

`GameRoomBackgroundMusic` owns one looping native stream for the current
application runtime. Main entry points retain it across forms. Shared forms
also retain it for alternative launches and nested dialogs. The common event
presenter switches to the in-game track after a valid game replay, including a
covered window. Finished games, abort, confirmed departure and screen cleanup
restore the general track; the last application window closes it. Runtime
managed-resource cleanup stops it on reload. Worker/model code never opens
audio or reads controls.

Only one background plays at once. Its volume combines the track's level with
All Power Games sounds; it does not change the global mixer or acquire HRTF
effects. Game effects and existing per-game music retain their own controls.
If a selected track is disabled, its context is silent rather than playing the
other background. No timer or polling was added for switching.

Checks: `test/ui/background_music_test.rb`, binary option/form regressions and
an MCP live trial of native looping audio, MIDI, volume and both transitions.
