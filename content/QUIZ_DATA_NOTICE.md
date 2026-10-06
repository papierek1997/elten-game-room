# Quiz Party data: provenance and review limits

The initial import came from budyn1211's PR #3, revision
`efa6e640a57901e7b01e5ac2158e84f1c3375435`. Its three original data files
are identified by SHA-256 in the development report `QUIZ_IMPORT_REPORT.json`,
which lists excluded records and retained IDs. The English pack retains
that provenance. The Polish general-knowledge and Witcher packs have since
been replaced; their current sources and review limits are described below.

## English

See `OPEN_TRIVIA_QA_NOTICE.txt` and `OPEN_TRIVIA_QA_LICENSE.txt` for the
upstream OpenTriviaQA attribution, revision and CC BY-SA 4.0 terms. On top
of the PR's transformations, this integration normalizes display markup,
changes “All/None of the above” to “All/None of these” for shuffled options,
and excludes questions depending on a previous question. The modified
English data retain the same license.

## Russian

The Russian general-knowledge pack is an original editorial set prepared for
ELTEN Game Room and released under CC0-1.0. It does not translate or derive
questions from the English or Polish imports. The source intentionally writes
the letter «ё» wherever standard Russian spelling requires it.

## Current Polish general knowledge

From data version 7 (Power Games 2.0.4.4, build 243), the Polish general
knowledge set is a new combined adaptation of PolQA, MAUPQA's 1z10 and
Milionerzy questions. It replaces, rather than extends, the former Wikidata
question database. The identifiers `quiz.wikidata.pl` and `quiz.wikidata`
are retained only for the existing set selection; they no longer describe
the source or its license. See `QUIZ_PL_GENERAL_SOURCES.txt` for attribution,
fixed source revisions, editorial changes and the separate rights of each
portion. In particular, this new set must not be labelled CC0.

Data version 8 makes approved minimal wording edits to 410 questions whose
embedded answer lists gave away which fourth option to reject. Factual clues
and the source style are retained; grammatical answer forms and a small number
of dependent choices are adjusted where necessary. No question is added or
removed: all 14,887 IDs, categories, source records and their order remain.
This is a focused wording review, not a new factual audit of the entire set.

## Current Polish Witcher books set

From Power Games 2.0.4.5 (build 244), `quiz.witcher.books.pl` replaces all
three previous Witcher sets. Questions cover Andrzej Sapkowski's Ostatnie
życzenie, Miecz przeznaczenia, five saga volumes, Sezon burz and Rozdroże
kruków, plus Droga, z której się nie wraca and Coś się kończy, coś się zaczyna.
The latter two stories are always named in the question. The alternative
wedding story is not treated as a continuation of the saga.

The new collection expands an independently edited books-only draft.
A subsequent review used selected topics from the retired database as
leads for further reading, not as factual evidence or ready-made questions.
Those topics were rewritten with new answer sets and checked against the
supplied books; game and screen-adaptation facts were excluded. Answers in
the collection were checked against the supplied literary texts.
Questions and distractors have their own wording;
the books and the private verification excerpts are not distributed in the
application. Each question identifies its literary source. The set includes
spoilers throughout the books. Difficulty labels are editorial estimates,
not measurements from player testing.

The literary works remain the works of Andrzej Sapkowski. No public-domain
or CC0 status is claimed for them, and the former Fandom pack's license
declaration must not be applied to this new set. The earlier provenance
notes below are retained solely as the history of the removed imports.

## Earlier Polish imports and retired Witcher sets

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

### Witcher medium split in data version 2

Build 218 reviews all 6,571 retained Witcher question IDs for the medium from
which the particular fact comes. The full Polish set remains available, while
two derived sets expose games and books together with screen adaptations. All
three views use one source database and a compact ID-to-medium map; the large
question database is not copied for either derived set.

The review compares the question wording, the medium of the concrete answer,
the supplied preliminary map and categories returned by Wiedźmin Wiki for
3,971 unique subjects and answers. It corrects 2,351 assignments relative to
the preliminary map and adds a natural medium qualification to 5,810 prompts
that were not already unambiguous. IDs, answers, distractors, difficulty and
thematic round categories remain unchanged. Four damaged imported performer
labels are repaired in prompt text; no answer is rewritten by this audit.

This is a complete classification and clarity review, not a complete factual
verification of all answers. The full decision list, the comparison with the
preliminary map and the captured source metadata are stored outside the signed
application under `diagnostics/witcher-medium-audit-218`.

### Full factual and language audit after build 219

Every question then present in the English general, Polish general and Polish
Witcher sources received one recorded decision. Retained answers were checked
against captured Wikidata statements, Wikipedia article revisions or Polish
Witcher Wiki article revisions as appropriate. A matching word alone was not
treated as proof: numerical answers had to occur as an actual quantity, and the
source context had to identify the fact asked by the prompt. Questions that
remained unconfirmed were removed; wording and answer keys were corrected when
the evidence supported a precise repair. The Witcher source was also checked
again for the medium of the concrete fact, so the detailed game and books/screen
views continue to form an exact partition of the retained source.

The independent Polish general audit by Balteam at commit
`9be74abfa6968270bfc04312833767bd83833ac3` was compared by original stable ID,
not copied blindly. Its schema-aware removals and replacements were accepted
where they supplied stronger evidence; local search false negatives were kept
when that audit supplied a verified structured relation. The complete combined
decision ledger, removal list, correction list and evidence URLs are stored in
`diagnostics/quiz-factual-audit-220`.

The final audited runtime sets contain 13,836 English general questions, 10,939
Polish general questions and 5,069 Witcher questions. The Witcher views contain
2,654 game questions and 2,415 book/screen questions. These audited data sets
were first packaged in version 1.1.8, build 220.

After build 221 had been signed, all 20,730 removals were reconsidered in a
separate conservative recovery audit. It restored only questions for which the
exact fact, the full answer set and (for Witcher questions) the assigned medium
could be confirmed. The source sets at that stage therefore contained 13,903 English
general questions, 11,088 Polish general questions and 5,137 Witcher questions.
The Witcher views contain 2,670 game questions and 2,467 book/screen questions.
The complete second-pass ledger is stored in
`diagnostics/quiz-recovery-audit-after-221`. These data are newer than the
already signed build 221 package and are not contained in that package.

## Rebuilding the historical imports

Use a checkout of the exact revision above, then run from the Game Room root:

```text
ruby tools/import-reviewed-quiz-packs.rb PATH_TO_REVIEWED_CHECKOUT content
```

This command describes the historical import, not the replacement Polish
general set in data version 7. Running it on a current checkout would overwrite
that new set. Its data should instead be maintained through the generated
`quiz_pl_wikidata_data.rb` resource and `QuizPackWriter`, with a fresh checksum
and regenerated readable lists after edits.

Only the pinned data hashes are accepted (LF/CRLF checkouts are supported).
The importer writes small registration files, lazy Ruby data resources and
the cleanup report. It does not access the network or modify the source
checkout. The runtime verifies each selected pack against its generated
SHA-256. `tools/build-quiz-pack.rb` uses the same lazy format for future
JSON imports and preserves supplied source information.
