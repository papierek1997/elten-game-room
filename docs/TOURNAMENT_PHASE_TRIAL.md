# Client sporting phases in the owned server trial

Scope: the explicitly invoked developer pilot described below, including its
test-only scheduling behavior. Use [the current integration contract](TOURNAMENT_SERVER_INTEGRATION.md)
for the ordinary player's automatic coordination and optional dates.

`ServerPhasePlan` reuses the existing group qualification, knockout round,
rematch aggregation, replay and win-series policies. It receives already
validated ordinary result receipts. Incomplete results never advance a phase;
unresolved automatic group qualification produces additional real fixtures
through the existing GroupTiebreak policy. A tied knockout pairing gets
a new replay fixture, while decisive results retain their sporting identity.
A finished final reports the champion and has no successor.

`ServerPhaseStore` publishes an immutable child candidate to the existing test
plan-document table, under the organizer's authenticated account. The document
binds the parent schedule, full parent candidate digest and sorted result digest.
Every reader starts from the fresh registered root and recomputes each stored
child against fresh verified parent results. It rejects altered ancestry,
foreign authors, partial documents, changed accounts and stale displayed phase
tokens. A cold journal reconciles uncertain publication without retransmission.
This is an observed sporting plan, not an execution seal: start/dispatch/finalize
flags remain false. Existing explicit ordinary native-table entry is separate.

The traversal is bounded to 256 phase steps and 1 MiB of compact presentation
history. Existing per-fixture result/read budgets and 120000-byte journal document
limit still apply. An exceeded budget fails explicitly rather than omitting an
old phase or pretending a shorter chain is current. Previous group and round
results stay visible; history omits nested series history and transport hashes
but retains member names, fixtures, summaries and standings. The independent
current-phase result view also carries its schedule ID, allowing the UI to
reject a phase change between its two reads.

The organizer invokes this path explicitly in the server trial. It adds no
poller, automatic invitations, player claims or secondary game executor.
Independent server invitation scheduling and result collection remain the
intended production architecture. Group and wildcard tiebreaks retain original
group points and restore already-qualified competitors/full team membership.
Repeated draws produce another qualification attempt. Legacy manual seeding
policies remain blocked instead of receiving arbitrary seed order.

Validation runs native group/semifinal/final games with four individual clients
and eight accounts in four Domino pairs, including actual private deals through
the normal per-client executors. A native final-to-two-wins scenario verifies
series progression. Additional native scenarios cover drawn group and
qualification games and the nine-player best-second wildcard contest.
Archive tests cover lost replies, immutable result lineage,
partial documents, unauthorized/stale actions, draws and completed finals.

# One-day and repeated daily windows

The setup wizard selects One day or Several days before date/hour controls.
Registration controls retain full date/time editing. Playing dates use year,
month and day only; playing hours use hour/minute only, with one Tab stop per
control. One day uses Tournament date; Several days uses First tournament day
and Last tournament day. The civil date range is inclusive with a separate interval
on each day. `PlayingDays` resolves each endpoint in the local system timezone
independently, preserving the selected local hours across daylight saving.
Publication stores the resolved UTC windows and uses the existing schedule
contract; no new server schema is required. End hour must be later than start
hour on each date. The date range is bounded to 256 days; existing publication
payload limits can impose a smaller server-trial range.

Editing a representable recurring schedule restores its local dates and hours.
An irregular or continuous legacy window uses Keep existing playing windows
until the user explicitly selects a replacement mode. A native editor test
covers 16–18 October, daily 19–21, UTC persistence, reopening, cancellation and
preservation of a legacy continuous Friday-to-Sunday interval.
