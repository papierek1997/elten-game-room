# Integration with ELTEN 3.0.5

The required API comes from the final `3.0.5` tag, commit
`f29e82a0c32c66b1eca5e6fa5e5e7b858b61f480`. Native tests use one
`ELTEN_HOST_SOURCE` pointing to that checkout. The existing service adapters
originated in final 3.0.4; the notification and sound integrations below
require final 3.0.5. Commands: [BUILDING.md](BUILDING.md).

## Native notification lifecycle and audio buffering

`GameRoomNotifications` sends native keyed notifications. An invitation key
includes the sender, recipient, native session, table and invitation ID;
tournament keys use the existing event identity. Receiving an authenticated
acceptance/rejection receipt revokes that sender's exact invitation by key,
without listing the recipient's notifications. Confirmed table closure also
revokes the local sender's outstanding invitations for that native session;
ordinary departure and host transfer do not. Cleanup failure cannot undo a
confirmed closure. The ordinary five-minute invitation deadline and tournament
registration windows are unchanged. Repeated internal coordination wakes keep
their separate, unkeyed delivery path because they are not a single event.

The Program's `notification_lifecycle` hook declares a native lifecycle with
60-second local-evidence checks. These callbacks do not discover rooms, read
tournament tables, open forms or send new invitations. A synchronized native
clock may establish expiry; a verified dismissed token may establish that a
tournament invitation is stale. Missing data is unknown, not rejection.
The host performs a revocation only after an explicit negative result.
No receipt-relative expiry is added to the original invitation lifetime.
Tournament start/final information is permanent. Final metadata includes the
recipient's place and winning units; it remains readable without a new table
read. Verified coordinator observations refresh actionable notice proofs.
List grouping hides dismissed notices without removing the native entries
before their lifecycle worker has revoked them on the server.

Sound factories retain ELTEN's default effect buffering. Power Games does not
force `effect_buffer: :low_latency`: that smaller queue caused underruns with
HRTF processing. Explicit buffering and sample requests pass through unchanged;
the host's global mixer, output device and HRTF settings are not changed.
Spatial scenes, new HRTF profiles, UserState and local notifications are not
part of this integration.

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

### Confirmed table departure

The public native endpoint methods `leave_session(session)` and
`close_session(session)` perform the existing authenticated departure RPC.
Unlike the Session convenience methods, they do not close the local view in
an `ensure` after a failed request. The shared table adapter calls them for
the exact Session belonging to the current endpoint, then calls
`close_local(..., confirmed: true)` only after acknowledgement or an explicit
server absence/closure error. Network failures and authentication refusals
are not acknowledgements. No host monkey patch or separate HTTP client is
introduced. The original SDK deferred cleanup remains for rejected provisional
joins; it must not be used to announce a successful ordinary departure.
`test/host/confirmed_table_departure_test.rb` exercises the actual host
Session, Endpoint and EltenLink wrappers with only HTTP substituted.

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
