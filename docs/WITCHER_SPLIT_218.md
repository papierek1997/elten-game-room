# Witcher question sets — data version 3

## Result

The Polish Quiz Party catalogue offers three Witcher sets after selecting the language:

- `Wiedźmin`: all 384 retained questions;
- `Wiedźmin — gry`: 144 questions;
- `Wiedźmin — książki i ekranizacje`: 240 questions, comprising 231 literary questions and 9 screen-adaptation questions.

Every retained ID occurs once in exactly one detailed set. The full set uses the same question record as its detailed counterpart. The two detailed sets therefore partition the full set rather than copy it.

## Medium review in build 218

Data version 2 classified all 6,571 imported records by medium. Explicit wording in the question was considered first, followed by the medium of the subject and concrete answer in Wiedźmin Wiki categories captured on 13 September 2026. The review checked 3,971 unique subject/answer labels through the Wiki API and changed 2,351 assignments relative to the supplied preliminary map.

Questions that did not already name their medium received a natural phrase such as `w grach z serii Wiedźmin`, `w książkach z cyklu Wiedźmin` or `w ekranizacjach Wiedźmina`. That review established the original partition and prompt clarity; it was not a complete factual verification of every answer and distractor.

## Full content audit in data version 3

The follow-up audit mapped all 6,571 records to their source relation and fetched 2,542 current Wiedźmin Wiki pages with revision IDs on 14 September 2026. It reviewed every prompt and all four options, plus 78 generator schema/origin combinations and an independent cross-cutting pass.

The result removes 6,187 questions, replaces 35 complete records and retains 349 unchanged. Every schema classified as unsafe and sixteen additional high-risk schema/origin combinations are removed in full. Free-text death descriptions, uncertain residences and deaths, non-exhaustive broad relationships, misclassified work types, duplicate facts, malformed labels, nonparallel answer classes, true distractors, unsupported source relations and confirmed medium conflicts were removed or repaired. Details and limitations are in `content/QUIZ_WITCHER_AUDIT.md`.

## Runtime design

`content/quiz_witcher_pl_data.rb` remains the only full question database. It now stores the final reviewed prompts and options. `content/quiz_witcher_pl_medium_data.rb` stores only the compact retained ID-to-medium map. `content/quiz_witcher_pl_sets.rb` materializes the set selected by the table. Registration does not parse either large resource, and every pack verifies its own version-3 checksum after lazy load.

## Reproducibility

The base revision is `b795e1a74e51f0eec3545b5ef636cfc71f86a698`. The complete removal manifest, complete edit manifest and 6,571-row audit ledger are stored in `content/`. Run `ruby tools/rebuild-audited-witcher-quiz.rb --check` to reconstruct and verify all three sets.

The original medium-classification generators remain `tools/fetch-witcher-wiki-metadata.rb` and `tools/audit-witcher-medium-split.rb`.
