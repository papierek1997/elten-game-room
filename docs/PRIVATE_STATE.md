# Private answers and saved games

## Local answer commitments

`ProgramStorage` skips writing unchanged state, including another `discard`
after an entry has been removed. The read–modify–write transaction is coordinated
across screens. The normal file is `hidden_submissions.json`; on an I/O error,
the store tries `hidden_submissions.json.recovery.json` in the same private
application directory. The host resolves and validates the path once per file
for each loaded application. Subsequent reads and writes use that path without
unpacking the installer again. The file contents are not cached. Writes go to
a temporary file, which replaces the destination only after the write has been
closed, just as in the host's native storage.

The snapshot contains an increasing `storage_revision`. Reads choose the newest
complete state, so an old primary file cannot undo a deletion confirmed in the
recovery copy. The next successful primary write replaces the older copy. A file
without a revision has revision 0. Do not delete or truncate the original to
force replacement.

A new answer reaches the game only after a durable write. Previous versions
and nonces remain available for an already accepted commitment. Failure of both
preparation paths returns a controlled error without an event plan. A cleanup
error returns `false` instead of interrupting game progress; the local entry may
remain until the next successful attempt. After both paths fail, writes have a
one-second backoff and a single warning until recovery, without sleeping or
adding another loop.

Coordination covers instances of the same native Program sharing a file within
one process. Separate ELTEN processes writing to one profile are not a supported
multi-writer setup. The local storage format does not change the commit/reveal
protocol or game outcomes.

## Boundaries for changing tables and participants

Transferring the table host role, replacing a player and leaving a table recheck
the private phase at the write boundary, including after the participant
selection dialog. Replacement distinguishes that participant's secret from
other participants' pending commitments. Accepting an invitation uses the same
safeguard as leaving normally.

## Account archive

`AccountSavedGames` saves the standard history through the account's private
files. `saved_game_schema_version` versions the format. A game defines
`save_game_error` for unsafe phases or disables saving through
`supports_saved_games?`. `restored_event_value` restores controller names in
specific event fields; do not replace arbitrary history text.

Closing the table and replacing participants require a confirmed archive
write. An uncertain result keeps the freeze in place. Releasing the freeze
requires the same game, the current table host and confirmation of the
operation's own write boundary; it does not unfreeze a newer operation.

Regression tests for answer storage and archives are in `test/persistence/`;
private-phase scenarios are also covered by the Quiz, Categories and Battleship
tests.
