# Saved ordinary tournament matches

Scope: an explicitly invoked developer archive/continuation pilot, not an
available player feature. Ordinary tournament matches cannot be saved or resumed
from files; [the current public policy](TOURNAMENT_SERVER_INTEGRATION.md#matches-results-and-recovery)
takes precedence. Do not enable this pilot as a fallback after a refusal.

The private saved-game archive optionally contains a checksummed `tournament`
reference: publication, schedule, fixture, leg and the current binding digest.
It is obtained from the explicitly bound creator service, not guessed from
names. Existing non-tournament archives retain their old behavior.

Before preparing or restoring a table, the client checks current source,
participants/options, binding, result and organizer cancellation. A restored
native game receives a continuation document authored by the designated
fixture creator. The document links the previous binding digest to the new
table/session and records the private save checksum, native archive ID and
public action-prefix digest/count. No private game state is published.

Shared readers follow at most 16 authenticated immutable continuation links.
Restored result capture checks native archive identity and the public action
prefix. Cold participants count the resulting receipt for the same fixture,
not a new match. Old in-memory binding collectors cannot export a result for
a superseded attempt. A resolved/cancelled match cannot restore an old save.

A lost continuation acknowledgement is reconciled in Operations without
uploading again. A confirmed resumed session is not recreated to repair a
failed link. The saved copy is consumed only after linking succeeds. Existing
native archive restoration still validates options, participants, private
state and clock; unsupported save moments remain unsupported.

This is a developer client/storage contract, not an atomic production start
reservation. Concurrent resume or cancellation races still require the
production server gate. Modified clients are not an authoritative game
result oracle. Physical two-computer validation remains necessary.
