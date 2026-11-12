# Shared manual forfeits

Scope: an explicitly invoked developer pilot, not the ordinary player flow.
Current public settlements use complete place groups and the game's small-point
policy; see [the current integration contract](TOURNAMENT_SERVER_INTEGRATION.md#matches-results-and-recovery).
Do not copy this pilot's 2/0-only or active-game cancellation rules into that flow.

The developer server trial offers an explicit organizer decision for an
unstarted scheduled fixture. The organizer chooses the winning competitor
(an individual or a complete team). An authenticated immutable document in
the existing plan table records 2/0 tournament points without small scores.
Other clients and sporting phase progression read the same receipt.

The native overview hides the action when a result exists or a native game
has started. The worker revalidates the account, displayed schedule, fixture,
winner, result and bound native table before any row insertion. A stale UI
is not authorization. No automatic decision follows inactivity or refusal.
The existing operation journal reconciles uncertain writes without retries.

A separate `ordinary-match-forfeit-v1` document is authored only by the
publication organizer. A native result and a forfeit for the same fixture
are a conflict, never an implicit override. Reconciliation also rejects
that conflict. Cold readers validate the exact participant set and receipt.

This is still an observational developer trial. AppTable does not provide
an atomic transaction joining a tournament decision to native game start.
Concurrent starts and decisions require the production server start gate;
client checks cannot replace it. A conflicting native result fails closed.

A started unfinished game has a separate explicit organizer decision,
`ordinary-match-cancel-forfeit-v1`. A fresh native replay must still be
unfinished. The receipt retains the bound session ID, binding digest and
observed history prefix digest/count. It awards 2/0 without small scores and
supersedes later native results for that fixture, preserving native history.
Finished games cannot be cancelled. This is a sporting cancellation; it does
not claim to close a foreign native table. Only its owner may close it.
The UI states that distinction before confirmation. No timeout decision or
replay fixture is created. Saved-match restoration rejects a cancelled fixture.
