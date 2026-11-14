# Forms, volume and help

On the Users list, the host uses `Ctrl+Shift+P` to toggle the selected human's
role for the next game. `Ctrl+Shift+O` still changes the viewer's own role.
The selected human may also be the host; this changes the playing role, not
table ownership.
The selected-person menu and dynamic F1 help share `participant_role_action`;
the callback preserves its original subject and rechecks the displayed action.
Both repository and transport revalidate membership and ownership. Their typed
`RoleChangeUnavailable` conflicts are presented by the Program without closing
the table; arbitrary `ArgumentError` exceptions must still propagate.

`F2` lowers and `F3` raises the volume by 10 points (0–100%).
`Shift+F2/F3` selects the previous/next group: all, game, join/leave, chat,
invitations/notifications. In a new program instance, the selected group starts
at “wszystkie” (“all”). Levels are stored locally. The all-groups level is a
multiplier; it does not overwrite group levels.

`Ctrl+F2` toggles the persisted `optional_game_sounds` preference through the
same settings transaction. It gates presentation effects, not essential
realtime/listening audio, chat, membership, notifications or the turn ding.
It is independent of the host's sound theme and does not change volume levels.

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

Deferred notification delivery uses the same native
`EltenAPI::UI.notifications_muted?` boundary as immediate host delivery, before
reading the sound or calling the speech callback. Muting calls alone does not
mute notifications; a notice processed while notifications are muted is not
announced again when that mode is disabled. This applies after contact/clock
deferral and after tournament-notice verification.

Invitation mapping, contact/blacklist filtering and pending/action lookup share
the native envelope sender check in `GameRoomInvitationIdentity`. A conflicting
metadata sender is suppressed in delivery and in the host notification list;
an absent metadata name uses the authenticated sender's original spelling.
Legacy adapters without a native sender accessor retain their metadata fallback.
This does not replace the room admission or account-identity checks.

The Daily Krowa date browser loads historical assignment rows in bounded
100-day batches through the native `in` filter, outside the UI thread.
Ascending native IDs retain the first assignment even across duplicate-filled
pages; current/future dates are excluded before querying. Missing history stays
blank and a corrupt canonical assignment remains an error, not a redraw.

## Participant labels

Human participants are always shown under their complete ELTEN account name,
including in live speech, lists, history and invitations. Saved or remote custom
aliases are ignored. `GameRoomParticipants.display_name` and
`Base#participant_name` only decode computer-player labels; they return a human
account name unchanged. Do not shorten logins or rewrite announcement text.

## Option editor

### Single-choice modal dialogs

For a local two-choice picker, the current shared call is:

```ruby
selected = GameRoomUI.choose_index(
  _("Choose a result"), [_("First"), _("Second")],
  program: program, index: 1
)
unless selected.nil?
  chosen_value = [:first, :second].fetch(selected)
  # Revalidate the current context before passing chosen_value to its owner.
end
```

This snippet belongs inside the owning Program/translated context, not at
application startup. It is only the local choice, not a complete persistence
operation. Index zero is a valid choice; `nil` means no choice. The caller
keeps the original candidate objects and validates the current context before
acting. Use a `GameShortcut` choice for a game-field action instead of adding
a second handler. The executable [native choice regression](../test/ui/choice_dialog_native_test.rb)
executes this snippet with its default, index zero and Escape, and also checks
the helper's prompt count, stale context and return behavior. The
[interaction checklist](GAME_ACCEPTANCE.md#record-the-interaction-not-just-the-result)
explains what to inspect in each new consumer.

Use `GameRoomUI.choose_index(prompt, labels, program:, index: 0, flags: 0)`
for a finite local single-choice list. It uses native controls, announces the
prompt once, preserves the supplied default, accepts Enter and cancels with
Escape. It returns a zero-based Integer, including `0`, or `nil` on cancellation
or an empty list. Do not treat zero as cancellation or write a game event from
the dialog. The helper clears the closing input frame even after an exception.

For example, `GameRoomUI.choose_index(_("Choose a player"), player_labels,
program: program)` selects an index into that exact displayed list. Retain the
selected identity, then recheck the turn/token/authority and pass the ordinary
action through the executor; the modal does not make an old view current.
Pass `ListBox::Flags::AnyDir` only when both arrow directions are appropriate.
Never call the helper from a worker. For multiple selection or a turn deadline,
keep the dedicated form and its lifecycle, as in WordBoardSurface; those are
not interchangeable single-choice dialogs.

Taboo review/restart, game choice shortcuts and card-action confirmation share
this helper. Regression: `test/ui/choice_dialog_native_test.rb` exercises the
native modal, one prompt, Enter, Escape, default/index zero, stale Taboo tokens
and card authority changed while the dialog is open.

### Editing table options

The option editor changes the contents of a numeric `EditBox` through the
native `set_text`, not the nonexistent `text=`. This also applies to values
hidden when the form is built and to resetting the deck after custom mode is
disabled. The compatibility test must use the host's real `EditBox`; a stub
that adds a `text=` setter masks the error as early as table creation.
Regression test: `test/ui/game_option_editor_native_test.rb` (binary sources
or an `.eltsetup` path as an argument; EN/PL forms, creation, saving,
cancellation, custom mode and dependent Rummy settings).

### Press-time modifiers

Game shortcuts, history navigation and editable-field gating use
`GameRoomUI.modifiers_when_pressed(control, key)`. It reads the required native
3.0.5 press snapshot without consuming the frame. Returned `:control` means
the keyboard scheme's main modifier, and `:alt` means its option modifier.
Question-boundary navigation also requests `include_insert: true` so that
screen-reader Insert+arrows stay native. A key can be a numeric code, a letter,
a native key name, or the comma/period/semicolon aliases used by the bindings.

Read modifiers before consuming the key or opening a modal. Native Form event
parameters describe the state at dispatch and can already differ from the
state when the action key was pressed. Likewise, final `key_held?` cannot
decide whether Enter meant ordinary play or Shift+Enter packet selection.
Do not patch the host's global event dispatch to correct an application binding.
Regression: `test/ui/press_snapshot_native_test.rb` covers release within one
frame, modifiers added after the key, text scope, punctuation/history and both
directions of the question/answer boundary using actual native controls.
Use the same helper for non-game bindings: the rules' Ctrl+F1 passes its
numeric `CTRL_F1_KEY` (not an unsupported `:f1` alias), and channel-space
Shift+Left/Right reads the arrow's press snapshot before rotating. Regressions:
`test/ui/rules_shortcut_press_snapshot_native_test.rb` and
`test/ui/table_conference_controls_native_test.rb`. Do not keep a second
modifier matcher in a document or conference control.

An `OptionChoice` can include a localized `description`, normalized to UTF-8
like its label. The editor opts only described lists into `ChoiceDescriptions`:
it appends the description to the native item utterance after the checked state.
The host still owns navigation, selection and input; labels, saved values and
table-option summaries remain unchanged. Refreshing choices also refreshes or
clears their descriptions. Duck Racing uses this for its challenge checklist.
Regression: `test/games/duck_racing/challenge_descriptions_native_test.rb`
(binary-loaded sources, all five catalogs, native navigation and selection).

## F1 and extending the interface

### Grid move explanations

`GridSpec#move_actions` defines legal origin/destination pairs; `GridBoard`
selects them through the same path for native Enter and movement commands.
Optional `origin_error.call(cell)` and `destination_error.call(origin, cell)`
return a localized explanation for a refused selection. Coordinates are logical
`[x, y]` cells. A nil or empty message retains the shared generic explanation.
These pure callbacks never write a move, and
do not run when input is guarded or the grid has read-only `row_actions: []`.
They do not replace the game's ordinary action validation. Backgammon uses
them for blocked points, dice restrictions, bar entry and bearing off.

An obligatory incoming piece need not occupy a selectable board cell. Set
`forced_origin: :external` and use that same origin in every `GridMove`;
destinations must still be bounded `[x, y]` cells. An external origin without
that declaration, or an external destination, is invalid. The first Enter
then chooses the destination directly. Read-only previews remain read-only.

Optional `selection_message.call(cell)` overrides the first-Enter prompt;
nil or empty text retains the shared prompt. It is a pure presentation callback,
with the same guard as the refusal callbacks. A second Enter on the origin
performs only an explicitly declared self-destination move; it never chooses
an ordinary move implicitly, even when there is only one available.
The selected origin's native cell label also
includes the localized "Selected" state, so it remains readable after moving
the cursor away and back, in speech and braille. Local selection changes update
only the affected cell labels, without refocusing or reannouncing the grid.
Quiet reconstruction restores that label from the same validated epoch; a
refusal cleanup, accepted selection or Escape removes it. Read-only previews
and externally forced origins never mark a board cell.
Backgammon uses a self-destination move for bearing off, without inventing an
extra board cell. Repeating Enter on its selected checker outside home instead
cancels selection, with the existing localized cancellation message; bearing-off
errors apply only to its home points 1 to 6. A refused destination retains
selection by default. Set `clear_selection_on_error: true` to clear the local origin after its refusal
explanation, as Backgammon does. Guarded input does not clear it, and a forced
external origin remains obligatory after a refusal. Selection survives a quiet refresh only within the same
`selection_epoch`; a new accepted move clears it. All emitted actions still
pass through the ordinary game validator.
Regression: `test/ui/grid_moves_native_test.rb` and
`test/games/backgammon/presentation_native_test.rb`.

### Composite controls and reuse

Keep sibling `SurfacePart` IDs unique. A composite forwards the program,
attached form, sound player and action guard to its children; do not duplicate
those capabilities in a game-specific wrapper. During reconciliation each
prior native child can be claimed once. Compatible siblings may use the same
zone ID in their separate specifications without sharing one mutable control.
Nested groups claim their reused leaves from the same operation's remaining
candidates; a caller-supplied candidate array is not mutated.
When a prior composite exists, part IDs scope reuse to the same logical part,
including across reordering, removal and insertion. A new part must not steal a
compatible sibling's control or cursor. Preserve that context until the child
is reconciled instead of flattening it prematurely into an unkeyed pool.
Regression: `test/ui/composite_reuse_ownership_native_test.rb` uses actual
layout updates, independent cursors and emitted cards for flat/nested groups.

Reuse must preserve command semantics, not only command IDs. If a retained
button captures a command whose label or payload changes, refresh both the
label and callback or rebuild that surface. `TypingSurface` compares complete
command definitions; equivalent definitions and status-only changes keep the
native controls. Regression: `test/ui/typing_command_reuse_native_test.rb`.

Keep submission-owning parts flat when their draft cleanup depends on
`action_accepted`/`action_rejected`: the current public `Action.source` is one
part ID, not a nested acknowledgement route. Do not add an ad hoc path field
to game packets to work around this limitation. Current game compositions
use flat parts for these inputs; read-only grouping/capability forwarding is
not evidence that a nested submission ACK is supported.

Use `GameRoomUI::Form` or `GameSurfaces::RefreshAwareForm` and pass
`program:` (in a shared layout, set `form.game_room_program`). Do not create
new game-specific F1/F2/F3 handling. The host handles these keys before form
events. A one-time bridge in the QuickActions dispatcher intercepts only F1,
F2, F3, Shift+F2/F3, Ctrl+F2 and Ctrl+F4 when the active control belongs to a waiting Game Room
form. It does not save ELTEN shortcut settings, intercept Ctrl+F1 or change
host sources. It does not retain the program in the global bridge. After
leaving or switching windows, host behavior resumes.

F1 collects `GameShortcut` entries and the screen's dynamic actions through
`GameRoomContextHelp`. The list order is game, screen, control help, history
and volume. Duplicates are removed while preserving order; replacing phase
definitions removes old entries. Editable chat retains unmodified letter keys
and native text-editing navigation. Explicitly declared Ctrl/Alt+letter commands,
such as question reporting, may work there through the shared bindings; this
does not enable game shortcuts over read-only history's native copy commands.
The list has
one visible control; Enter/Escape closes it, and the previous cursor position
returns without rebuilding the form.

## Help during a game

Score-sheet games may use `GameShortcut` kind `grid_preview` with a `GridSpec`
as `default_value`. The shared modal uses the ordinary native grid and returns
its action through the existing move validation; Escape returns no action.
`GridSpec#row_actions` is an array of ordinary `GameSurfaces::Action` values:
each row activates its declared action regardless of the inspected column.
An empty array makes the grid read-only; nil preserves ordinary board-coordinate
selection. Summary rows without an action are inert. `hide_coordinates` affects
presentation only. A grid may declare read-only announcement `shortcuts`, such
as the dice readout; the shared modal never reads game-specific state fields.
Pending writes and frozen sessions still prohibit submission, not inspection.
Tests cover native opening, navigation, Enter/Escape, one prompt and unchanged
parent focus/drafts, as well as an ordinary coordinate board.

The live in-game shortcut reference also includes a game's declared personal
settings command (Ctrl+P), using the same entry as its table menu. Do not
drop that command when replacing the authored shortcut reference with current
game-field tips, or add it to games without that capability. Other room
management commands remain outside the game-only reference.

F1, Ctrl+F1 and the [audio tutorial](AUDIO_TUTORIAL.md) use the shared form's
help stack. Input reaches only its topmost window; parent timers keep running.
Refresh preserves the help text, cursor and selection. The game runner,
deadlines and presentation continue through the normal path. Enter/Escape
closes help without making a move underneath. Closing the game cleans up the
entire stack and tutorial audio. The real-time surface respects
`game_room_background_help?` from the very frame that opens help.

## Navigating the rules

Form shortcuts use declared choice defaults and may supply a localized
`submit_label`; absent labels retain the usual proposal button. Conditional
fields use the shared option editor's visibility rules and only visible
values enter the submitted action. PawnTrack surfaces can navigate declared
menus locally with `surface/open_menu`, preserving each menu's stable item ID
and returning to the parent category on Escape. Navigation writes no move;
actual choices still pass through the ordinary executor and `action_for`.

A game's `surface_action_shortcut` may supply an existing input shortcut
for a selected list action. The shared surface callback opens it before
capturing the completed move; cancellation emits nothing. Pending operations,
an inactive wait and frozen/busy presentation prevent opening the dialog.
The executor still checks the original view revision before any write.

Number shortcuts use one native numeric EditBox in a GameRoomUI form. The form
owns initial focus, after the default value has been selected; constructing
the field must not speak first. Enter submits the edited value and Escape
cancels without leaking a key to the game. Invalid input retains the value
and reads its error with the field once. Local PawnTrack menu changes read
only the new selection, not the table's spin, balance or other status.

Choice questions may opt into `QuestionSpec#prompt_as_text`. The shared
QuestionSurface then presents native read-only text followed by the answer
list. Plain Down moves from the question to the list, and Up from its first
answer returns to the question. Modified arrows and text editing commands
stay native. GameRoomLayout attaches that navigation to the current form;
the question cursor/selection and answer index survive ordinary refreshes.
Quiz uses this capability; category selection and other choice lists keep
their existing presentation. Regression: `question_text_native_test.rb`.

`QuestionSpec#read_only` prevents every submission route, including immediate
`submit_on_select` choices. Immediate choices use the same `submission_action`
as explicit submission, then the ordinary action guard; do not maintain a
second payload/permission path. This is separate from a read-only prompt:
`prompt_as_text` can display read-only question text while its answers remain
writable. See `test/ui/question_read_only_native_test.rb`.

Tournament Operations must render every journal kind exposed by its workspace,
including current `partnership` and `pair_draw` records, not only historical
`pairing`. Confirmed storage and an applied semantic choice are distinct: retain
the original status and show its stale-choice explanation when
`pairing_applied` is false. Opening details must retain the exact operation ID
and must not reconcile or resend it. Regressions use actual service-produced
records in `test/tournaments/modern_operations_native_test.rb` and native
readback in `pairing_operations_feedback_native_test.rb`.

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

An answer sheet's local draft includes its `sheet_id`. Refreshes of that same
sheet preserve unfinished input; a different sheet starts from its new field
values even when the field IDs repeat. This also applies when recovery skips
intermediate phases, such as returning directly to another Categories round.
Legacy local snapshots without a sheet ID remain readable. Regression:
`test/ui/answer_sheet_identity_native_test.rb`, using the native controls and
the game's actual round/attempt identifiers through the shared layout.

The create-table game selector, the game list under Join a table and the
rules library append the game's localized `short_description` after its name. Other selectors and
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

Backgammon projects move coordinates through `history_entries_for_display`
and `describe_event_for_display`, using the same viewer seat as `board_grid`.
Each move retains its event-time seat, coordinates and capture flag in
`HistoryEntry#value`; historical authors and the canonical replay remain unchanged.
Do not resolve a historical actor against today's roster after replacement.
Observers use the first seat's numbering, as on the board. The shared history
and TXT export consume the same projected entries as the visible view.
The opening roll already names the starter after both dice, so its shared
turn-transition hook suppresses only that duplicate, not later turns.

Ctrl+Shift+S or “Zapisz historię stołu” (“Save table history”) in the menu saves
the available event and chat history as UTF-8 TXT in the account's local
recording library. Audio Ball and Axel Pong instead save a versioned passive
JSON presentation timeline. This never closes or resumes the game. All disk
I/O uses finite background tasks; the realtime observer only copies frames and
presentation events into bounded batches. Returning preserves focus and chat.

Saved games separates Histories and replays from Games to resume. The library
rescans its owned directory instead of storing arbitrary external paths. Export
copies; delete removes only the selected owned file. The offline player reuses
the audio renderers under a virtual clock and the existing Progress bridge,
without constructing physics, game sessions or result publishers. Message import
validates passive data and checksums. Preview does not import or delete; after
persistent import the recipient explicitly chooses whether to delete the exact
message. Confirmed sending removes only the sender's mailbox copy.

The replay player's primary field is a passive native Button, like the audio
playfields, not a command list. Its context options and F1 are derived from the
same current action set. Native symbol shortcuts act without Ctrl only while
that field is active; Space/Enter toggle playback and Left/Right seek five seconds.
These non-letter keys use the native field events, with their localized key
names included in menu labels and F1; do not advertise P/B/F aliases or register
global keyboard actions for replay navigation. S/T share the live game's
read-only score/server formatter, without inventing a replay connection status.
Pong offers two/four seat perspectives; Audio Ball offers its two team-side
perspectives. No active engine, input-capture hook or session is constructed.
Navigation retains the selected event boundary while its cue plays, so another
Previous/Next moves to another boundary instead of selecting the same cue.

Ctrl+R reads `table_options_announcement`, based on the same definitions as
the settings document. The board game's S counter uses
`remaining_piece_counts(replay)` and the actual board, in player order.
Unmodified letter-based game shortcuts do not apply in editable chat; explicitly
declared modified shortcuts still use the shared text-scope rules above.
Read-only history keeps native text selection and copying, including Ctrl+C;
it is not a game shortcut field. The same key still operates the game when
its actual playfield is focused. Explicit history-navigation shortcuts retain
their existing scope.

A browse shortcut may set `default_value` to select the matching choice on
opening. This does not reorder the choices: arrows, Home and End keep their
native behaviour. An absent or unavailable value selects the first row.
Duck Racing uses this for V to open at the viewer's current square; observers
start at square 1.

Regression tests: `test/ui/volume_and_help_test.rb`, `test/ui/background_help_test.rb`,
`test/ui/background_help_native_test.rb`, `test/ui/background_help_game_screen_test.rb`
and the tests for the relevant surface and game.

## Tournament shortcuts and context menus

Table forms also opt into `game_room_table_controls`. Ctrl+Shift+M and the
table's context menu share the native `Conference.muted` state and announce
the resulting state. Do not gate first-frame dispatch on `$activecontrols`:
the host has already cleared that list before the form updates.

While a native conference is connected, the layout shows a native Static
"Channel space" immediately after its voice conversation button. Movement,
rotation and position/size queries delegate to Conference, without a second
position model or audio pipeline. Membership is local: changing it updates
only this control's visibility, preserving the focused field and chat draft.
Regression: `test/ui/table_conference_controls_native_test.rb`.

When the user is connected to that table's conference, explicit departure
offers No, Yes and Leave only the table, in that order, defaulting to No.
The third choice releases only table membership and local tracking after the
normal confirmed table departure; it never calls Conference.leave. Yes retains
the ordinary disconnect behavior. Cancellation and failed table departure do
not clean up either membership. Match native channel ID and name against the
published or retained table identity; an unrelated conference does not enable
the extra choice. A creator's authenticated table departure still withdraws its
invitation as usual, without closing the conference for connected people.
Regressions: `table_voice_departure_choice_test.rb`, `table_voice_departure_test.rb`.

Only the main lobby opts into `game_room_tournament_shortcut_enabled`.
Ctrl+T opens the tournament browser; Ctrl+Shift+T keeps the My tournaments
scope even when no matching row exists. Neither shortcut's menu/help entry appears in game, tournament or
settings forms. The widget keeps its own single-instance launch callbacks.
The form handles the key before updating the focused control; at this point
ELTEN has already cleared `$activecontrols` for the new frame, so that list
cannot be used to decide whether to dispatch this shortcut.

Tournament and match lists set `game_room_invitation_context_field` and append
the shared invitation action after their own context actions. Other fields
keep the form's ordinary invitation action. This changes menu order only:
Ctrl+J still uses the same invitation picker and admission checks.

An open tournament action list follows its next registration/start/deadline
boundary with one local, one-shot timer, including when the viewer has not
registered and receives no coordinator wake. Updating actions preserves their
selected identity and does not refocus or announce the list. Ordinary time
boundaries do not read the server; retention expiry uses one fresh directory
read. Closing the dashboard disposes its pending timer. Regression:
`test/tournaments/public_preview_time_boundary_native_test.rb`.

## Krowa word proposals

`KrowaWordProposals` in `lib/krowa_word_proposals.rb` is a local client service.
Ctrl+B posts the current answer-field text; Ctrl+Shift+B posts the most recent
word rejected as `unknown_noun`, captured before the surface clears the draft.
Chat text, private solutions and accepted guesses are not proposal sources.
Both actions preserve the answer, cursor and game history and post immediately
through `EltenLink::Forum.create_post` to thread 28245. The native server supplies
the authenticated author; the post body contains only the normalized word.

The first-use rules explain the nominative common-noun policy, excluded word
classes, spelling review, Power Games membership and forum visibility. Accepting
them is required before that first post; Escape returns without accepting or
posting. The versioned acknowledgement and delivery state use a separate local,
account-partitioned JSON file. Malformed JSON/shape is refused without replacement.
The player reference belongs in Krowa's authored `vocabulary` chapter, with
both keys also listed in `controls`; maintain all five complete editions.

Every file/network operation runs in a finite managed task. The SDK wrapper
passes cancellation and a 15-second timeout and rechecks the signed-in account
before and after requests. Fresh structure verifies membership and that the
thread/forum are open; the server still enforces write permissions. This never
joins a group or changes its notification settings automatically.

A pending marker is saved before posting. A confirmed post ID is retained in
memory before persisting the receipt. An explicit uncertain retry examines the
account's own posts, matching the exact word and target thread, without reading
or marking the proposal thread. Acquisition is bounded to ten 50-post pages;
an incomplete or malformed continuation refuses another send. Nonempty short
pages continue according to the SDK's `more`/`next_before` contract. State retains
up to 32 pending words and the latest 256 confirmed receipts. This reconciles
ordinary retries, not concurrent exactly-once delivery across computers or
external deletion/editing of the evidence. There is no automatic resend.

The screen accepts optional client `local_shortcuts` and
`handle_local_shortcut` hooks before the move pipeline. Its optional
`action_rejected` callback receives only a guarded current-session submission,
before clearing the corresponding surface. These hooks perform no move writes.
Tests: `test/games/krowa/word_proposals_test.rb` and
`word_proposals_native_test.rb`; the latter uses native controls and captured
speech in all supported languages, without publishing a live forum post.

## A cue after event speech

Games may declare `event_speech_tail_sound(event:, before_replay:,
after_replay:, viewer:)`; the base returns `nil`. The shared event presenter
puts the event's complete live announcement and a non-immediate
native `SpeechCommands::CustomCommand` into one `SpeechSequence`. The callback
enters the owning program Runtime and rechecks its session and sound-output
gate before playing the ordinary configured effect. Canonical history remains
plain full-name text. Cash Auction uses this for the closing gavel.

The sequence never becomes a model, input or network readiness barrier.
Leaving/replacing the game drops the stale callback; interruption or a missing
speech index may cancel the cue. If background speech is disabled, the sound
still follows its independent sound policy. Regression:
`test/ui/event_speech_tail_test.rb` uses the real host sequence class and covers
index order, duplicate indexes, session/leave guards and missing-index progress.
