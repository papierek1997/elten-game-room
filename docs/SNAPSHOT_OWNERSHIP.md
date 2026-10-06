# Snapshot ownership

- Events accepted by the store are immutable history. Participant projections
  and historical messages serve separate purposes.
- The runner owns the execution model. UI publication and planning receive
  their own copies through `GameRoomSnapshot.copy`; the UI does not edit the
  worker's model.
- The first `publish_view` detaches the visible replay's `accepted_events`
  from its sources: it substitutes its own deeply frozen copy of that list.
  The local `ViewRevision` binds the completed revision to that exact list and
  to the table/game/participant-epoch identity. Replacing the list or copying
  the replay requires a new capture; history corrections arrive through a new
  replay/list, not by mutating the frozen prefix. The rest of the model is not
  frozen. Ordinary `GameRoomSnapshot.copy` still returns a mutable copy,
  including for incremental reducers. The token is not passed to the replay,
  archive or worker as proof that a write is current; pre-write validation
  still uses fresh state.
- The presenter also copies prefixes. For values that cannot be copied, it
  may explicitly reconstruct the projection; it must not return the original
  as a fallback.
- Simulation copies the state and RNG. The earlier, explicit
  `shareable_simulation_snapshot?` contract remains the only exception; it is
  not automatically extended to new games.
- Copying preserves symbols, Struct, cycles and aliases within the graph. It
  is not replaced with JSON or a shallow `dup`. `Replay#state` may be `nil`.
- The internal `NinetyNinePlanning::State` owns its value graph, frozen after
  the world is created. A branch copies the collections modified by the
  reducer, and newly introduced card values are also frozen. This explicit
  planner contract does not change replay copying or the general snapshot.
- The activity cache belongs to the repository, after reading accepted
  transport projections. It compares full values, stores its own copies and
  returns fresh mutable results. Sharing internal projections does not replace
  validation or the viewer's current visit boundary.

`tools/benchmark-runtime.rb` measures replay, copying, specification building,
legal moves, bot decisions and uncontended lock cost separately. The report
includes the Ruby version, platform and corpus SHA-256. Do not compare CPU time
with RTT or use it to infer audio behavior behind a native window.
Example: `ruby tools/benchmark-runtime.rb --iterations 10 --output tmp/runtime.json`.
