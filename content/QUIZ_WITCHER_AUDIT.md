# Polish Witcher quiz content audit

## Scope

This audit covers every question in the data-version-2 Polish Witcher pool before the audit changes:

- 6,571 questions in total.
- 962 questions about mages.
- 1,066 geography questions.
- 3,265 questions about less-known characters.
- 435 monster and bestiary questions.
- 182 witcher questions.
- 661 ruler and royal-family questions.

The full set and the two detailed sets are not three copies. The full set uses one shared question database. The games set and the books-and-screen set are disjoint filters over that database, so every retained ID occurs in exactly one detailed set and once in the full view.

## Verification performed

- All 6,571 records were mapped back to their source article and generator relation.
- 2,542 distinct Wiedźmin Wiki pages were fetched through the MediaWiki API with current revision IDs and timestamps on 14 September 2026.
- Every prompt, correct answer and three wrong answers were checked for source-relation support, additional true values, semantic class, granularity, grammar, malformed import text and answer leakage.
- Seventy-eight generator schema/origin combinations were reviewed for whether the source field or category proved the wording used by the question.
- A separate cross-cutting pass checked all 6,571 rows and identified 233 surplus semantic duplicates as well as malformed, overlapping, nonparallel and currently unsupported answer sets.
- Findings were applied only when they were source-backed or mechanically reproducible. A missing field-level medium tag alone was not treated as proof that a stable character fact was false.
- Edits use complete replacements validated against the current source relation. Records without a safe complete replacement were removed.

Wiedźmin Wiki is a community source. This audit verifies that the quiz follows the cited current wiki revisions; it does not replace the wiki with independent primary-source research.

## Result

- 6,187 questions removed.
- 35 questions edited.
- 349 questions retained unchanged.
- 384 questions remain playable.

| Category | Before | Removed | Edited | After |
|---|---:|---:|---:|---:|
| Mages | 962 | 787 | 0 | 175 |
| Geography | 1,066 | 1,046 | 2 | 20 |
| Less-known characters | 3,265 | 3,167 | 14 | 98 |
| Monsters and bestiary | 435 | 410 | 0 | 25 |
| Witchers | 182 | 130 | 14 | 52 |
| Rulers and royal families | 661 | 647 | 5 | 14 |
| **Total** | **6,571** | **6,187** | **35** | **384** |

The resulting catalogue contains:

- `Wiedźmin`: 384 questions;
- `Wiedźmin — gry`: 144 questions;
- `Wiedźmin — książki i ekranizacje`: 240 questions, comprising 231 literary and 9 screen-adaptation questions.

Both detailed sets retain all six thematic categories and all three difficulty levels.

## Important corrections

- All 360 free-text “how did this character die?” records were removed. Their options mixed generic descriptions such as murder or execution with more specific causes, killers and outcomes, so more than one option could be defensible or the answer could be inferred from wording.
- All 555 broadly worded relationship records were removed. A non-exhaustive infobox relationship list cannot prove that three other story characters are unrelated.
- Surplus copies from 233 semantic duplicate groups were removed.
- Every one of the 3,261 questions in the 32 schema/origin combinations classified as unsafe was removed, together with 2,111 questions in sixteen additional high-risk schema/origin combinations covered by the stricter parent policy.
- Location, book and game options were repaired only when a complete source-checked replacement used parallel answer classes; otherwise the record was removed.
- Branch-dependent game deaths, uncertain facts and medium conflicts were qualified or removed.
- Current source contradictions, true distractors, answer leakage, malformed English/import fragments and grammar-based answer clues were removed or repaired.

## Audit files

- `QUIZ_WITCHER_REMOVALS.json` contains every removed ID, its complete old question, reasons and evidence URLs.
- `QUIZ_WITCHER_EDITS.json` contains every complete replacement and its old record.
- `QUIZ_WITCHER_AUDIT_LEDGER.json` records all 6,571 outcomes, source revision IDs, source timestamps, schema review and hashes of the ten canonical reports stored in `witcher_audit_reports/`.
- `witcher_audit_reports/` contains the canonical partition, cross-cutting and schema reports whose hashes and coverage are verified by the rebuild command.

## Reproducibility

- The audited base revision is `b795e1a74e51f0eec3545b5ef636cfc71f86a698`.
- Data version 3 is reconstructed from that revision, the removal manifest and the edit manifest.
- Run `ruby tools/rebuild-audited-witcher-quiz.rb --check` to verify the generated shared database, medium map, set counts and checksums without writing files.
- Runtime checksums are stored in the audit ledger and verified when each lazy pack loads.
