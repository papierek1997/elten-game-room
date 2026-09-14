# Quiz Party data: provenance and review limits

The source for this local integration is budyn1211's PR #3, revision
`efa6e640a57901e7b01e5ac2158e84f1c3375435`. The three original data files
are identified by SHA-256 in `QUIZ_IMPORT_REPORT.json`. That report lists
every excluded record and the IDs of every cleaned record. Question IDs
are retained, so a record can be compared with the exact original import.
Each generated pack also stores its import URL; explicit article links
found in the input are retained as `source_links` in the question data.

## English

See `OPEN_TRIVIA_QA_NOTICE.txt` and `OPEN_TRIVIA_QA_LICENSE.txt` for the
upstream OpenTriviaQA attribution, revision and CC BY-SA 4.0 terms. On top
of the PR's transformations, this integration normalizes display markup,
changes “All/None of the above” to “All/None of these” for shuffled options,
and excludes questions depending on a previous question. The modified
English data retain the same license.

## Polish imports

The PR declares the Wikidata pack as CC0-1.0, credited to “ELTEN Game Room”,
and the Witcher pack as “CC BY-SA 3.0 (Fandom, Wiedźmin Wiki)”, also credited
to “ELTEN Game Room”. These declarations are preserved; they are not an
independent verification of the original authorship or licensing chain.

The submitted material does not include the Wikidata queries, source page
revision IDs or original extraction scripts. This integration cannot
reconstruct missing source history or claim that its importer is an
original Wikidata/Fandom scraper. Before wider distribution, the contributor
should supply those details and attribution appropriate to the original
sources, especially for the Witcher data.

The local cleanup is reproducible from the pinned PR. It removes the known
missing-name/import-fragment questions and duplicate residence/nickname
templates, normalizes wiki labels and preserves available links. It is not
a manual fact-check of every question, distractor or paraphrase in the data.

### Witcher data version 3

Build 218 introduced the three-set medium split over 6,571 retained Witcher
question IDs. The full Polish set and two derived sets use one shared database;
the detailed game and books-with-screen sets partition the IDs without copying
the large question resource.

A follow-up content audit mapped all 6,571 records to their source relations and
fetched 2,542 current Wiedźmin Wiki pages with revision IDs on 14 September
2026. Every prompt and all four options were checked, together with 78 generator
schema/origin combinations and an independent cross-cutting review. The audit
removed 6,187 records, replaced 35 complete records and retained 349
unchanged. Data version 3 contains 384 questions: 144 game questions, 231
literary questions and 9 screen-adaptation questions.

The audit verifies that questions follow the cited current community-wiki
revisions. It is not independent primary-source research into the fictional
canon. Complete removals, replacements, source revision IDs and reproducibility
data are in `QUIZ_WITCHER_AUDIT.md`, `QUIZ_WITCHER_REMOVALS.json`,
`QUIZ_WITCHER_EDITS.json` and `QUIZ_WITCHER_AUDIT_LEDGER.json`.

## Rebuilding these files

Use a checkout of the exact revision above, then run from the Game Room root:

```text
ruby tools/import-reviewed-quiz-packs.rb PATH_TO_REVIEWED_CHECKOUT content
ruby tools/rebuild-audited-witcher-quiz.rb
```

Only the pinned data hashes are accepted (LF/CRLF checkouts are supported).
The importer writes small registration files, lazy Ruby data resources and
the cleanup report. It does not access the network or modify the source
checkout. The runtime verifies each selected pack against its generated
SHA-256. `tools/build-quiz-pack.rb` uses the same lazy format for future
JSON imports and preserves supplied source information.
