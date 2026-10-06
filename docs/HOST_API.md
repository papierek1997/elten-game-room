# Integration with ELTEN 3.0.4

The required API comes from the final `3.0.4` tag, commit
`3418d67dea40ee116f4a8ba545b1c409fd04706f`. Native tests use one
`ELTEN_HOST_SOURCE` pointing to a compatible checkout. API 3.0.5 RC 1 is not
the basis of this integration. Commands: [BUILDING.md](BUILDING.md).

## Native service adapters

1. `GameRoomClock` reads the public `EltenAPI::ServerClock`, without its own
   HTTP, refresh, retry or clock anchor. The adapter preserves the numeric
   result and `ClockUnavailable` when the host has no sample. It does not
   force synchronization through private host methods. The notification clock
   also only delegates; subscription settings may load before the first sample,
   while sending and presentation wait for readiness. Game epoch and freeze
   calculations remain in `GameRoomSessionClock`.
2. Silent form resumption uses the native `resume_for_refresh` and
   `wait_without_announcement`. It clears its own focus-suppression flag so
   that the first manual navigation after a refresh is announced.
3. Screen shortcuts and context menus belong to `FormBindings`. Each new
   binding removes the previous screen's registrations, without proxies that
   accumulate callbacks. Internal control handlers and the real-time client's
   timer retain their owners. A reset during a callback does not run handlers
   that have already been removed.
4. `Tasks.start` runs short `GameRoomBackground::Work` operations. The adapter
   preserves the single-use result `[wartość, błąd]` (value, error), the busy
   state even for an uncollected result, and the runtime association. The host
   allows four live tasks per UUID; the application queue holds up to 128
   pending operations, admitted FIFO within that UUID. Existing owner updates
   service the queue, without a new thread, timer or polling. Closing discards
   the result and the pending task; it neither interrupts nor retries an
   uncertain write that has already started. The resource registry also cleans
   up tasks when the runtime closes.
5. The participant list and the widget's table list use
   `ListBox#update_options(keys:)`. The key is the person/table ID, not the
   label. A change of role, order or name, or cursor movement during a read,
   does not move the selection to another existing record.
6. Callback dispatch for the visible form belongs to the final host's loop.
   It also delivers callbacks to the active parallel scene before updating
   controls. The form maintains only its own discovery work, retention and
   cleanup of completed redirected launches. The covered game's runner and the
   pre-write check may still drain their own endpoint. A single form with help
   does not double the native callback limit.
7. The real-time timer inherits the native `FormTimer` lifecycle. The match
   clock gate provides an immediate first tick; subsequent deadlines are
   measured from the start of the previous tick, without catching up on missed
   frames. The host's ordinary repeating timer measures its interval after
   the callback ends, so simply replacing it with a timer at the same interval
   would change the pace of the game.
8. Registry and subscription candidate reads use column projection while
   preserving the row author. `delete_many` removes the account's own duplicate
   preferences; `insert_many` writes statistics in batches of at most 25
   records, with a time budget between confirmed batches. Other bulk operations
   cover at most 100 records. Acknowledgement must cover the entire submitted
   set; a partial result, conflict, invalid ID or lost response is not success.
   A retry reads accepted records before sending the missing ones. An account
   change or cancellation prevents the next batch from starting; it does not
   undo a request already accepted by the server. The cache is limited to
   15 s / 4096 rows and is also invalidated after an uncertain write. The
   account's own preferences are read afresh.

The local plural-rule parser uses integer division and remainder compatible
with C/gettext for negative intermediate values. Application translations do
not depend on the host's private catalog.

## Application-specific contracts

### LiveSessions table capacity

The service allows capacities from 2 to 8. The transport, lobby, model and
archive format all have a maximum of 8. New tables and tables for resumed
games have a fixed capacity of 8, including in 1000 miles. Bots and observers
also occupy lobby places. A saved game requiring more places is rejected
before a table is created, with a clear message; the saved game itself remains
untouched. A table host absent from the saved participant lineup needs an
additional observer place. The test broker must reject capacity requests
outside the service's range.

### Other mechanisms

Application-specific mechanisms required by game contracts remain: one session
runner, history projections and validation, write reconciliation, private
answers, a separate real-time lifecycle, deterministic shuffling and model
copies. The covered game's speech/audio bridge and Audio Ball's ordered input
are still needed. Native scene dispatch does not replace presentation behind
another window or move control updates into the worker.
