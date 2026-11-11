# Question creator

The main lobby has a **Create your own quiz question sets** entry. Anyone
can propose questions for an installed set or create a new set. Proposals are
sent to `papierek` by ordinary ELTEN private message, not published into the
playable question database. Sources are optional.

## Player workflow

The entry opens the set library, including locally recovered changes. An empty
library announces Ctrl+N. That shortcut (also in its context menu) creates a
new set or an existing-set proposal. New sets collect title, language and an
optional description; **Save** persists the empty set and returns to the library.

Enter opens a set with five actions, in order: **Add a question**, **Browse
questions**, **Add a category**, **Delete draft**, **Send to the author**.
Browsing opens a separate numbered list; Enter edits the selected question.
Delete and the list's Remove question action share one confirmation and the
ordinary draft save/recovery boundary. The empty-list placeholder has no
deletion action; removing a row keeps selection beside it.
Ctrl+N adds a question from either an empty or a populated question list; the
empty-list message explains the shortcut. The set menu keeps its existing
**Add a question** action. Yes/No and other short selectors accept both horizontal
and vertical arrow keys.
Adding a question to a set with no categories shows a notice asking the user
to create at least one category first. It does not open an empty question.
Delete on the library uses the same deletion action as the menu.
Existing-set proposals choose a language first, then press Enter to open a
separate window of matching sets. Escape returns to the language choice;
set labels contain titles only. This reads metadata, not entire packs.
Deleting a draft requires confirmation and returns to the set library only
after success; cancelling or failing leaves the draft available.

The question editor has four answer fields (A is always correct), a category
list, optional source/note and **Save**. The last category item is **Add a new
category**: Enter opens a nested editor without rebuilding the question form.
Saving selects the new category; cancelling keeps the previous selection and
all typed fields. The category is saved independently of the pending question.
When saving the question afterwards, retain that new draft snapshot reference.
Older questions are reordered in the editor's copy only; saving keeps the
correct answer but moves it to A. Cancelling does not alter delivery digests.
Incomplete questions can be saved. Each save
stages local recovery and then saves a private account file. Escape on a changed
question offers Save, Continue editing or Discard unsaved changes.

Before sending, all missing fields are listed in a persistent read-only dialog,
with question numbers and answer letters. This is a completeness check, not an
editorial assessment: repeated questions and answers are allowed. Structural,
encoding and size limits remain enforced. Sending creates one ZIP attachment
containing readable `questions.txt` and structured `questions.json`.

Context actions remove questions/sets and edit new-set details. Selection lists
use Enter and Escape without visible Open/Cancel buttons. Ctrl+R refreshes the
library on demand; there is no polling. Enter in a multiline editor does not send.

## Draft storage

`EltenLink::Apps.private_resources` stores one compressed JSON file per draft
snapshot. Private storage belongs to the account, not a particular computer.
No public application files or application tables are needed. The three tables
from the earlier creator have been removed. The separate, ephemeral Quiz
reporting flow below does not use this draft storage or an editorial inbox.

Resource names contain a draft UUID and a snapshot UUID. Uploading an existing
filename does **not** replace a resource, so retries reuse the snapshot identity
and check its metadata and digest before another upload. Read-back validation
precedes deletion of the previous snapshot. Only the exact baseline resource
opened by this editor can be replaced. Concurrent edits on different computers
may produce two drafts; neither branch is silently overwritten.

The local, account-partitioned `quiz_creator_recovery.json` is recovery storage,
not the normal draft library. Current fields are staged before an action; a
failed cloud save leaves them editable and available locally. Successful cloud
saves remove the local copy. Recovery uses the host's atomic `update_json` and
does not replace a malformed existing file with an empty default.
The set UUID is not a version identifier: it also contributes to the immutable
submission digest. Recovery and in-memory unsaved edits distinguish branches by
their baseline resource ID/name. A second branch is kept in the optional
`branches` map of the same account entry; existing version-1 `drafts` entries
remain readable without migration. Cleanup requires the selected branch's
snapshot and content, not merely its set UUID. Deleting, submitting or saving
another cloud branch must not erase unrelated local work, including edits kept
only in memory after a disk failure. Read-only visits do not rewrite recovery.

## Message delivery and failure handling

Delivery uses the public SDK's `Messages.messages`, `Messages.send_text` and
native attachment upload. An immutable content digest identifies the submission
in the subject, body and attachment filename. Before an explicit retry, the
creator looks for the exact message in the sender's conversation with `papierek`,
checking sender, recipient, subject, marker and attachment name. It never
automatically resends after an uncertain response. If status cannot be checked,
the draft remains available.

A confirmed delivery is recorded locally, then in a small private account file
named `quiz-sent-<content digest>.json`. Its contents are read back before deleting
the sender's exact matching message and then the draft. Account-wide receipts
survive opening an old draft on another computer after sender-mailbox cleanup.
They are not shown in the library and use no public files or tables. Cleanup
failure keeps the draft for an explicit retry; it is not another send. Receipt
writes are reconciled after uncertain uploads in the same way as draft writes.

The message and attachment remain the author's review copy. Self-addressed
messages from `papierek` are never removed. Later edits are not applied to the
message or installed quiz packs. Failed receipt persistence leaves the sender's
message in place as evidence; the creator does not delete that evidence first.

ELTEN messages do not expose an idempotency key. This retry reconciliation is
not a server-enforced exactly-once guarantee: simultaneous sends of the same
draft from two computers, or external deletion of both delivery evidence and
receipts before an uncertain retry, can still produce duplicates. A failed message after native
attachment upload can also leave an unattached upload managed by ELTEN; the
SDK has no attachment-deletion operation.

## Bounds and execution

- Up to 1000 questions per draft; sending requires at least one complete
  question. Saved blank or incomplete questions are reported, not silently omitted.
- Up to 16 MiB of decoded draft JSON, with bounded decompression and digest
  checks. The account's shared private-file quota also applies.
- One ZIP of at most 4 MiB, including TXT and JSON, so the creator uses the
  ordinary account attachment limit rather than a premium-only allowance.
- All disk and network work uses finite managed tasks. Native request timeouts,
  cancellation and account checks apply at operation boundaries. There is no
  periodic polling, game-time network reporting or custom HTTP transport.

## Ephemeral reports from Quiz and Duck Racing

Ctrl+B marks the displayed question; Ctrl+Shift+B marks the previous one.
`GameRoomQuizReports::Tracker` keeps only the current/previous snapshots and
marked questions in memory for this table visit. It copies the question and
displayed answer order, not players' private answers. Intermediate round states
must not replace the snapshot: they can retain an old question ID with a new
round number and answer order. No shortcut sends a move, opens a form or performs
network work. Marks survive rematches at the same table, not an account change.

Duck Racing captures the local client's displayed quiz question for both
field/card questions and challenge questions, without exporting player answers.
Other challenges do not replace the last question. A closed or mismatched client
cannot contribute a snapshot.

After the table screen returns and releases its layout, Yes opens a simple issue
description for each marked question; No discards all marks. The form shows
the correct answer as stored in the set, not during play. Cancelling Leave
does not open this prompt. There are no report drafts, receipts or saved history.
Sending uses a finite managed task and the creator's bounded, account-checked
SDK client, but none of its file-storage operations.

Each report has a unique message marker. Before an explicit retry, the sender's
exact conversation is checked for confirmation. A confirmed send is remembered
in RAM before removing only the matching sender copy. Cleanup retries do not
resend. Self-addressed reports from `papierek` preserve the author's inbox copy.
If sending fails, the same form retains its text for retry; skipping it discards
that report. This reconciliation is not a server-enforced exactly-once guarantee.

## Editorial review and verification

The author can read the message and download its attachment using ELTEN or its
MCP-accessible native SDK. JSON pins the target pack's identity and version for
existing-set proposals; TXT provides numbered questions, ABCD answers and the
correct letter. Editorial work follows [QUIZ_EDITORIAL.md](QUIZ_EDITORIAL.md).
Submission itself never edits installed content.

Targeted tests in `test/quiz_contributions` cover validation, optional fields,
partial drafts, large sets, interrupted file and message operations, retry
reconciliation, account changes, isolation, native forms and all interface
languages. Live checks use clearly marked temporary drafts and messages on
the authorized accounts; only those test resources are removed afterwards.
