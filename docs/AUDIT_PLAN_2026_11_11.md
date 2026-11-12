# Power Games extended audit — 11 November 2026

Status: completed on 12 November 2026 after full fresh source pass 11 found no
new confirmed defect or necessary improvement; independent final evidence gate
accepted 749 current logic files / 150,063 lines plus 2 separately validated payloads.
Detailed closure and limits remain in ignored tmp/audit-20261111/README.md and
clean-pass-11/closure.json. Earlier passes with repaired findings are not clean
passes. This reusable process was started by the maintainer after approving
the extended scope and adding cleanup/shared-mechanism consistency. Baseline:
`e235f1fa2f257927728939631fd9ab9a84f466d8`, initially clean. This is a new audit,
not a claim that the [22 October review](AUDIT_PLAN_2026_10_22.md) was complete
or that its evidence proves current behavior. Deathmatch remains separate.

Work autonomously on confirmed in-scope defects and useful, demonstrated
improvements. Keep major changes to rules, externally visible behavior,
architecture or host APIs as explicit decisions for the maintainer. Do not
change server schemas/protection/quotas, private user data or ELTEN itself.
No release, version bump, package, installation or publication is authorized
by this audit alone. Reports and probes belong in ignored `tmp/audit-20261111/`.

## Reusing this plan or resuming a run

This document defines a repeatable process; its date and baseline identify the
current run, not the sources/API to use forever. For a new authorized audit:

1. Read current AGENTS and linked contracts, inspect the actual branch/working
   tree, required host pin, runtime and existing CI state. Record a new baseline
   and exclusions; do not infer them from this conversation or an old report.
2. Create a fresh ignored run directory such as `tmp/audit-YYYYMMDD/` (a unique
   suffix if already occupied). Inventory current maintained paths and hashes,
   generated inputs/assets, test discovery and live-client/account ownership.
   Old findings are leads and regressions, not current read/test coverage.
3. If resuming THIS run, read its progress/findings/review records first, retain
   valid evidence whose source/dependency hashes and context still match, and
   requeue changed or incompletely reviewed parts. Never reset the ledger just
   because a turn or process was interrupted. Track source reads separately
   from static scans, native tests, live-account trials and listening.
4. Allocate disjoint bounded read scopes and stable review handoffs. Record
   who actually read each range; an agent's read is not the primary auditor's
   personal read or another independent whole-project pass. Keep one editor
   and one live-test schedule. Supporting agents cannot expand permissions.
5. Start with shared/high-risk paths, cover the remaining inventory and finish
   each pass. Use the repair/verification and completion rules below; new
   scope, missing evidence or an unfinished reviewer must remain visible.
6. At handoff, report the current pass, reviewed/unread scopes, pending findings,
   active trials/resources, exact next step, test outcomes and limitations. Do
   not describe a partial run as complete. Preserve useful regressions and
   current technical guidance without adding private reports to the repository.

For this run, `inventory.json`, `reviews.json`, `PROGRESS.md`, batch reports and
reviewer/analyst evidence in the ignored run directory are the continuation
record. Future audit runs need fresh inventories and explicit source snapshots;
the scope and acceptance criteria here remain reusable.

## Coverage and evidence

Inventory maintained production code, games/bots, shared surfaces/forms,
transport/randomness/private state, saves/recordings, tournaments, statistics,
notifications/settings, loaders, tools, tests/fixtures, generators and CI.
Read maintained logic in full, with its callers and dynamic entry points.
Record hashes, actual reviewed ranges, findings and remaining coverage; a
search, static scan or passing test is not a full source review. Review
generated outputs through their maintained inputs and generators. Validate
literal data/binary assets appropriately without claiming full factual,
linguistic, legal or listening certification of every item. Preserve protected
creator-supplied texts and do not rewrite unrelated rules/question sets.

Each finding records expected/observed behavior, reproduction, cause, risk,
affected consumers, correction and its evidence. Separate hypotheses and
preferences from confirmed defects. A broken test is not automatically a
product defect; a passing fixture is not proof of the real interaction.

## Review tracks

1. Correctness and authority: game rules, scoring, round/match completion,
   ties, elimination, defaults, bots, random receipts, hidden information,
   validation and permissions; interactions between otherwise correct layers.
2. Accumulating cost: beginning/middle/end of long games, successive rounds,
   rematches, menu cycles and app reloads. Separate CPU/allocations, memory,
   requests, file reads, replay/projection cost, queues, workers, timers,
   callbacks and resource release. Distinguish bounded warm-up from continued
   growth. Heavy experiments stay local; do not flood the public server.
3. Complete interaction: open, choose, edit, confirm, cancel and return.
   Verify native control type, selected default, stable item identity/caret,
   editable-key behavior, availability and a usable path out of each state.
4. Speech and audio sequence: duplicate prompts, stale/full captions on local
   navigation, announced-before-committed results, turn order, interruptions,
   missing/overlapping cues, background delivery and catch-up deduplication.
   Inspect exact ordered output and count emissions, not just matching words.
5. Consistent menus/shortcuts: logical order, ordinary actions before rare or
   destructive actions, no duplicate destinations, Enter matching the default
   action, context menus/help matching actual availability, and text editing
   retaining its native navigation/copy shortcuts. Do not impose a global key
   when a game has a justified semantic difference.
6. Responsiveness/concurrency: rapid successive inputs, simultaneous chat,
   moves/points/phase changes, adding multiple bots, cancellation during work,
   stale replies and uncertain writes. Serialize only actual dependencies;
   retain exact-once behavior, private boundaries and bounded queues.
7. Lifetime/recovery: leave/return, host or participant changes, reconnection,
   hidden/parallel scenes, rematches and same-process reloads. Include native
   registrations, retained app namespaces, saves/recordings/import/export,
   ownership and cleanup only of resources created by the trial.
8. Bots/content/tests: compare strategy decisions on identical permitted
   views/deals/seeds and bound search cost. Check rules/help/translations
   against actual controls. Audit test discovery/isolation, fake conveniences,
   historical inputs, native/binary boundaries and regressions that do not
   reach the defect they claim to cover.
9. Maintainability and dead code: prove that removed code is not reached via
   registries, reflection, callbacks, templates, host hooks, package manifests,
   generators or supported archives. Remove real dead branches, redundant
   layers and duplicated mechanisms; route genuinely equivalent behavior
   through the existing shared framework. Preserve authority, ordering,
   diagnostics, state ownership and distinct realtime/turn-based schedulers.
   Dawid Pieper's cleanup (`f2f6ae6`) is an example of purposeful simplification,
   not a patch to reapply. Fewer lines alone do not prove a useful improvement.
10. Reusable framework and contributor guidance: identify equivalent mechanisms
    currently reinvented by games or modules. Move justified shared behavior
    into existing capability/specification, lifecycle and presentation layers,
    with explicit ownership, safe defaults and bounded extension points. Keep
    game rules separate; do not add game-ID switches or a general abstraction
    for an unproven single use. Migrate affected real consumers together and
    check their distinct states, cancellation, refresh and resource release.
    Update AGENTS, adding-a-game guidance and relevant technical contracts in
    the same batch: describe when to reuse the mechanism, minimal working
    integration, required hooks/data, invariants, lifecycle, errors, tests and
    common mistakes. Remove obsolete contradictory instructions and verify
    examples against current code so future authors and AI need not infer the
    correct path or copy an outdated game implementation.
11. Independent documentation audit: review contributor/AI instructions even
    where no runtime change or framework extraction is needed. Cover setup,
    required host API, architecture/ownership, game/variant registration,
    options and defaults, native UI/focus/text keys, messages and sound order,
    bot strategy and bounded computation, randomness/privacy, persistence,
    tournaments/results, translations/rulebooks, dependencies, testing,
    packaging and PR acceptance. State what is mandatory, conditional or an
    example; provide exact current entry points and runnable scoped commands.
    Explain common failure modes and how to demonstrate correct behavior.
    Check examples and cross-links against maintained code, consolidate
    contradictory/outdated instructions and distinguish developer guidance
    from player documentation. Precision means explicit actionable contracts,
    not redundant prose, unsupported guarantees or making every optional hook
    compulsory. A future author using AI should be able to follow the guide
    from implementation through verification without the maintainer supplying
    missing integration requirements by trial and error.

## Repair, measurement and verification

Reproduce first. Repair in coherent batches, updating all affected existing
tests/fixtures at the same time. Where practical prove that the regression
fails on the faulty behavior in an isolated local process. Compare before
and after using identical data and verify state, actions, history, scoring,
ownership, event order and subsequent RNG before accepting a speed gain.
Measure cold/warm paths, resource slopes and operation counts rather than
relying on one unstable millisecond result. Record the conditions and limits.

After every UI correction exercise the resulting native interaction, including
the modal itself and its return path. Native speech capture is distinct from
audible listening; native-handler input is distinct from physical key input.
Use real accounts and ordinary game flows for changed runtime paths and their
actual dependencies. A model state alone cannot demonstrate live UI/audio.
Complete a match when the change concerns match completion/results or growth
over the match; keep genuinely local checks short. Shared changes need
representative consumers from the affected families, not only the reporting
game and not every unrelated game. Test-only/tooling/CI changes use their
actual local paths, not invented live matches. Reuse valid evidence for
unchanged paths and retain initial failures separately from final results.

Use an owned, single live-test schedule. Preserve the maintainer's active
client/table; prefer the existing test accounts and clients, launching existing
test copies normally when needed. Do not automate authentication or modify
security settings. Do not manufacture expected ACKs or put faulty baselines
into live clients. Remove only trial-owned state/probes and leave the agreed
corrected sources available as appropriate to the tested deployment.
While the maintainer uses the computer, all permitted ELTEN interface actions
must go through its MCP/native application contract. Do not use Computer Use,
OS keyboard injection, window activation or another desktop-control channel.

## Roles and completion

One primary auditor owns the full inventory, maintained-file edits, integration,
measurements and live trials. One independent read-only reviewer examines
bounded high-risk contracts and every stable patch batch, including the tests
and evidence. On 11 November the maintainer also authorized one additional
read-only analyst when it materially accelerates review. This analyst receives
disjoint game-model/strategy/growing-cost scopes, records actual reviewed
ranges/hashes and sends reproducible findings to the primary; it neither edits
maintained files nor operates live accounts. The independent reviewer still
checks the integrated fixes and verification, including analyst discoveries.
For the fifth control pass, the primary used the maintainer's conditional
approval for one further reader: a fresh independent model reviewer covers
an initial 43 explicitly handed-off model files previously read repeatedly by
the primary, followed by further recorded transfers of unread scope when a
reader finishes sooner. All effective assignments and actual read ranges stay
in the same pass ledger; a handoff is not a reset or inherited source credit.
This is a disjoint `fourth` ledger, not an additional whole-project audit or
permission to edit, test, use MCP or control windows. Other roles keep their
explicit scopes. Record such a handoff before reading and avoid simultaneous
writes to another reader's ledger. No further agents or conflicting parallel
editors are implied; future runs must use their own authorized role allocation.
The primary may explicitly authorize a narrow local regression or isolated
maintained-file fix for a confirmed finding, naming the allowed files and
verification. That does not grant broader editing or live-test authority;
the primary still independently reads the exact final patch and evidence.
For a new complete control pass, rotate disjoint reading scopes when useful:
the previous model analyst can inspect shared UI/coordination/tools, while the
reviewer reads models previously owned by the analyst. The primary keeps all
edits and live operations. A role change creates no inherited source-read credit
and does not remove independent review of stable fixes. Freeze the new explicit
file/reader manifest and start empty current-hash ledgers for every reader.
Give the reviewer a precise snapshot/scope, requirements, risks and output
contract without prescribing a verdict. Resolve findings through evidence,
re-review affected fixes, and record gaps; agreement is not a guarantee.

Finish each source pass rather than resetting its cursor after every finding.
Fix/verify batches and revisit their genuine dependencies. Before declaring
completion, conduct one whole maintained-source pass with no new confirmed
defect or demonstrated improvement requiring further edits. A finding repaired
during a pass does not make that pass clean. Cleanup/optimization findings
also invalidate clean status; stylistic preferences do not justify endless
changes. Keep source-pass coverage distinct from targeted/live test coverage:
a new full read does not require replaying every unchanged test campaign.

The final report accounts for all files and findings, independent review,
actual fixes and measurements, verified runtime paths, deferred material
decisions and untested boundaries. An interrupted or partial pass is not clean;
unresolved in-scope defects cannot be relabeled as a defect-free result.
Neither a clean pass nor passing tests guarantees that no possible bug remains.
