# Editing quiz questions

A question should sound as though it was written by someone who knows the
subject and can explain it. Players should be thinking about the answer,
not trying to work out what the author meant. The three wrong answers are
just as important as the question and the correct answer: they should test
knowledge, not give the solution away.

These rules apply to writing, importing, expanding, repairing old sets and
translating questions, regardless of language. Read the entire document before
starting this work. It also applies to content from PRs and existing question
databases. It does not authorise rewriting existing sets as part of unrelated
changes or altering wording the user has asked to preserve. The user's
specific instructions take precedence.

## Scope and approach to the material

First establish the sources, subject, language, audience and scope of changes.
Distinguish between:

- New questions: original writing based on verified facts.
- Adapting an existing database: preserve good wording, making changes only
  within the agreed scope. Do not rework a good question just to make it different.
- Repairing a weak set: the old question is a lead to investigate, not a source
  of truth. After verification, rewrite the question and all its answers,
  rather than swapping a few words in the old template.
- Translation: preserve the fact being tested and the meaning of all answers,
  but use natural target-language constructions rather than copying the
  original word order.

Read the accepted questions in the set. Treat them as a guide to difficulty,
tone and level of detail, not as a template for mass reproduction. Do not
impose your own question limit or pad the set with weak entries to reach a
number. For large collections, work in batches that allow you to read and
check every item.

## Facts and sources

Every new question must have a verified basis. Find a passage in an allowed
source that confirms exactly what you are asking about. Read its context:
finding a name in a search does not by itself confirm the person, event,
causal relationship or time.

- In literary material, distinguish an event from a rumour, supposition,
  a character's account, a legend or the content of a painting. Where needed,
  ask “Według opowieści…” (“According to the story…”) rather than presenting
  an account as an undisputed fact.
- Do not mix books, games, screen adaptations, editions and alternative
  histories. Add a title or other qualification where it actually establishes
  the scope. In a book-based set, even the wrong answers must not be borrowed
  from excluded adaptations.
- If the user has limited the sources to supplied books, verify the facts in
  those books. Model knowledge, a wiki or another quiz question is no substitute.
- For information that changes over time, specify the necessary date or period
  and check a source for that period. Avoid undated questions about the
  “obecnego” (“current”) record holder.
- Correct obvious typos within the permitted scope. Do not reconstruct an
  illegible transcript by guessing. Set unresolved text aside for clarification
  or reject it, rather than inventing the missing event.
- Check the rights to use the material and preserve attribution and required
  provenance information. Public availability does not grant permission to
  copy an entire set; rewriting does not remove licence obligations.

In editorial notes, link every new or changed question to its source:
a title and chapter, a page in a specific edition, a range of lines in a file,
or an address and a specified passage. Briefly record which fact was confirmed.
For line numbers, identify the file and how the lines were counted. The
evidence must let someone find the passage again, not merely assert “checked”.

Private book texts, long quotations and working reports do not belong in the
installer and must not automatically be added to the repository. Keep the
report in the ignored `tmp/` directory or an agreed location outside the
repository. Preserve the required provenance and licence in the data as
described in the [source notice](../content/QUIZ_DATA_NOTICE.md).

## Natural wording

Use ordinary, correct quiz language: specific, without bureaucratic wording,
embellishments or unnecessary introductions. Natural wording does not mean
colloquial asides, forced jokes or deliberately leaving errors in place.

- Start with the actual question. Instead of “W kontekście wydarzeń
  przedstawionych w utworze, jaka postać pełniła funkcję dowódcy…”, the shorter
  “Kto dowodził…?” will usually do. Retain any context needed to answer.
- Ask directly about the action or relationship. “Kim była żona X?” sounds
  better than “Jaką osobę przypisano X w charakterze małżonka?”. Do not,
  however, confuse marriage, partnership and kinship.
- Avoid constructions that sound like a data export, such as
  “X — zawód tej postaci?” or “Do jakiej kategorii przynależności państwowej przypisano X?”.
  Choose the term that matches the source: citizenship, nationality,
  birthplace and service to a particular ruler do not mean the same thing.
- Do not add “w uniwersum”, “w książkach z cyklu”, “spośród wymienionych”
  or “jak wiadomo” to every item. These expressions are not forbidden;
  keep them only when they clarify something in that question.
- Do not force variety merely by replacing “kto” with “jaka postać”.
  Short questions such as “Kto…?”, “Gdzie…?” and “Dlaczego…?” are normal.
  Variety should come mainly from the content and the way knowledge is tested.
- Do not cut the text down to telegraphic fragments. Two simple sentences
  can be clearer than one sentence with several asides.
- Do not increase difficulty through convoluted syntax. A less familiar fact
  may make a question difficult, but the question itself should remain clear.

Read the question and answers as the player will hear them, without looking
at the source note. If you have to return to the beginning to identify the
subject or understand the sentence, revise the wording.

## An unambiguous question

The question must work on its own, even when randomly placed between
questions about entirely different subjects. Do not refer to “poprzedniego pytania”,
“wspomnianego bohatera”, “tego miasta” or “powyższych wydarzeń” unless
the referent appears in the same item.

Before accepting it, check:

- Are you asking about one specific fact? If you combine facts, the whole
  answer must be unambiguously assessable.
- Is it clear which person, battle, version of a work or stage of the plot
  is meant? Add the necessary surname, place, period or title, not a scene summary.
- Do words such as “pierwszy”, “największy”, “jedyny” or “najstarszy”
  have a clear measure and scope? Do not turn an opinion or a disputed claim
  of precedence into a certainty.
- Does “dlaczego” ask for a cause stated in the source, rather than an
  arbitrary interpretation?
- Does the question already contain the solution or rule out some answers?
- Does the answer depend on colour, italics, page layout or another clue
  that cannot be heard through speech synthesis?

Do not leave three possibilities listed in the question when the game
presents four answers. Players should not be able to reject the fourth merely
because it was not mentioned in the question. Make the smallest necessary
edit: “Która z trzech rzek…” can become “Która z rzek…”. After removing
the list, however, check again for ambiguity: the original options may have
narrowed the meaning of the question.

Avoid double negatives. Questions of the form “Który… nie…” may be used
sparingly if the negation is clear when read aloud as well. Do not make the
outcome depend on overlooking a small word.

## Four answers

The standard format is one correct answer and three distinct wrong answers.
You must be able to justify each of the three as a plausible mistake and
then rule it out within the exact scope of the question.

1. Keep answers in the same category. For a question about a city, give
   cities; about an occupation, occupations; about a ruler, people who could
   reasonably be confused with one another. Do not mix a country name with
   a continent name unless the question genuinely allows that shared level
   of answer.
2. Match the context: period, region, field, role, fictional universe and the
   relevant characteristics of the person. If the question refers to a female
   character's husband, do not add a woman as an easily eliminated answer.
   Do not infer gender from the name alone, however; check the actual person.
3. Match the grammar of all four options to the question: case, number,
   gender and preposition. None may be eliminated on linguistic grounds alone.
4. Keep a similar level of detail and style. Do not surround one complete,
   precise description with three vague ones. Lengths need not be identical;
   do not lengthen names with artificial additions to make them look equal.
5. Check for aliases, synonyms, different spellings of the same name or
   partially overlapping answers. “Włochy” and “Italia” do not make two
   independent options in a question about a country.
6. Check all answers after changing their order. Do not use “obie powyższe”,
   “A i C”, “żadna z pozostałych” or similar references to the list.
7. Do not invent fake people, places or terms merely to fill empty slots.
   A question that genuinely tests recognition of a nonexistent concept may
   be an exception, provided that purpose is clear.
8. Do not label an answer false merely because it did not appear in one
   passage you found. Check whether it could genuinely be a second solution.
   If that remains unresolved, narrow the question in line with the source,
   replace that answer or set the item aside.

An example for assessing the construction, not an instruction to add the question:

> W którym państwie leży uzdrowisko Karlowe Wary?
>
> A. Czechy
> B. Słowacja
> C. Austria
> D. Węgry
>
> Poprawna odpowiedź: A.

All the options are countries from a reasonable geographical context.
The set “Czechy, Bałtyk, Europa, Warszawa” would mainly test recognition of
categories, not the location of the spa town.

Questions that genuinely have only two alternatives, such as yes/no, do not
fit this format. Do not add “czasami” and “nie wiadomo” as supposedly
distinct answers. Reject those items. If three fair mistakes cannot be
found, do not rescue the question with absurd options.

## Variety and repetition

Review not only individual questions, but also neighbouring sections and the
whole set. Several dozen valid questions about who met whom can still make
a monotonous quiz.

Depending on the material, cover characters and their relationships, events,
politics, systems of government, wars, geography, culture, everyday life,
nature, knowledge of the world and the meaning of terms. Do not add categories
for which the source provides no good questions. Category names should be
short and clear, and the grouping broad enough to help the player rather than
fragment the set.

Compare the fact being tested, not just identical sentences. “Kto zabił X?”
and “Z czyjej ręki zginął X?” are duplicates. A question about the perpetrator
and one about the location of the same death may be separate if both facts
matter and neither question merely splits the other into trivial details.

Do not automatically remove every question about the same character or
every question with the same correct answer. Examine their meaning. When
expanding a set, compare new proposals both with one another and with the
existing database.

Stop expanding when what remains consists mainly of repetition, uncertain
facts or incidental details without interesting context. Do not claim to have
reached a mathematically maximum number of questions. State the actual scope
of the review.

## Principles shared by all languages

A set must sound natural in its own language, not merely be understandable
after translation. The language of the questions is a game resource and need
not match the interface language. Adding a Polish set does not require versions
in every UI language. Every version actually prepared must undergo full
editorial review.

- Preserve diacritics, the spelling of names and the language's normal
  punctuation. Do not remove accents or write the entire question in capitals.
- Use established geographical names and names from the relevant literary
  edition. Do not invent translations of names and titles that already have
  an established local form. Be consistent within the set.
- Read the question with each answer. In inflected languages, translating
  names without the required inflection can give away the correct answer.
- Do not mechanically transfer idioms, word order or constructions such as
  “jaki jest nazywany…”. If a sentence needs rephrasing, rephrase it while
  preserving the exact fact being tested.
- Wordplay, homonyms, letter counts, rhymes and grammatical riddles need a
  separate assessment after translation. The translation itself may destroy
  the solution or create a second correct answer. Do not silently substitute
  a different fact: set the question aside or agree on an adaptation.
- Pay attention to date formats, units and decimal numbers. Do not change a
  value by confusing a separator or a measurement system.
- Do not rely solely on back-translation. It can confirm meaning, but does
  not establish that the target-language wording is natural.

### Polish

Watch the inflection of surnames and place names, gender agreement and
distinctions between relationships. “Małżonek” is not better than “mąż” or
“żona” when the source says directly who is meant. Usually prefer
“Gdzie urodził się…?” to “Jakie było miejsce narodzin…?” and
“Czym zajmował się…?” to “Jaki zawód przypisano…?”. Do not, however,
replace every similar sentence with a single pattern.

Avoid automatic calques and excessive verbal nouns.
“Kto dowodził obroną miasta?” is clearer than “Kto był osobą
odpowiedzialną za realizację dowodzenia obroną miasta?”. The case of the
answer must also fit “z kim”, “komu”, “przez kogo” and “z czyjego rozkazu”.

### English

Use natural question word order, appropriate tenses and articles. “Who led…?”
or “Where was … born?” is usually enough instead of “Which character was
responsible for the act of leading…?”. Do not use “Which of the following…”
in every question, but keep the expression where it is useful.

Choose a consistent variety of English for the set, in line with its sources
and the agreed requirements. Do not alter quoted proper names merely to
standardise spelling. If “a” or “an” before an answer gives the choice away,
restructure the question or choose all options so that none can be ruled out
by the article alone.

### Czech

Write in Czech, not as a Polish sentence with the words replaced. Check
grammatical government, cases, word order, prepositions and words that resemble
Polish words but have different meanings. Preserve Czech characters and
established proper names. “Kde se … narodil?” is usually more natural than
an elaborate question about “místo narození”; match the verb's gender to
the person.

### Spanish

Preserve both question marks and accents, including those in “qué”, “quién”,
“cuál” and “dónde” when used interrogatively. Check the articles, gender
and number of the answers. “¿Dónde nació…?” does not need the elaborate
“¿Cuál fue el lugar de nacimiento de…?”. The choice between “qué” and
“cuál” depends on the construction, not on a single equivalent of the
Polish “jaki”.

Choose a neutral or specified variety of the language and check regionalisms.
A word common in one country does not always have the same meaning in another.

### Russian

Watch inflection, gender, verbal aspect and the correct spelling of names.
Do not transfer Polish syntax or English noun constructions.
“Где родился…?” usually sounds more natural than “Каково было место рождения…?”.
Do not accidentally mix Latin letters with similar-looking Cyrillic characters.
For “е” and “ё”, preserve distinctions needed for meaning, pronunciation and
proper names; do not replace characters in bulk without checking.

### Additional languages

Follow the full shared process and add relevant, verified language notes to
this document. Do not assume that inflection or naming rules from a related
language are sufficient. If you cannot reliably assess the target language,
mark the material as requiring editorial review rather than presenting a raw
translation as finished. There is no need to create a separate copy of this
guide for each language; keep a single source for the rules.

## Mandatory review before integration

Follow these steps for every new or changed item. For large sets, record
progress so that no material is missed when work resumes. A sample is used
to agree on style; it does not replace a review of the remaining questions.

1. Confirm the fact and its scope in the source. Record an editorial reference.
2. Write or revise the question within the permitted scope of changes.
3. Choose three plausible mistakes and check why each is wrong.
4. Read the question without the source and without marking the correct answer.
   Check that it is self-contained and understandable after a single reading.
5. Try to show that a second answer also fits. Look for an alias, a different
   period, another version of the event or a broader meaning of a word.
   Do not approve an unresolved ambiguity.
6. In a separate pass, read the entire new batch for natural wording:
   syntax, monotony, unnecessary additions, grammatical agreement of the
   answers and clues that give the solution away.
7. Check semantic duplicates and thematic grouping against the entire
   database. Then perform technical validation and refresh the reader-facing
   export.

If other agents are authorised for the task, give them these instructions
and the source boundaries as well. Use cross-review, but the person integrating
the set remains responsible for duplication and overall consistency. This
document does not itself authorise starting helpers. Without them, perform
a separate editorial pass yourself; do not call it an independent review.

An item's review outcome is: accepted, revised and rechecked, set aside with
a specific unresolved issue, or rejected with a reason. Only the first two
groups enter the active database. Removing already published content must
remain within the task's scope. Do not shift unfinished editing onto the user
by saying that “the rest can be fixed while playing”.

## Technical validation and integrating a set

Automation can find an empty answer, a repeated name, broken encoding or an
outdated export. A passing test cannot by itself confirm factual accuracy,
natural wording or the plausibility of the three wrong answers. Do not use
a list of “AI-sounding words” or an automated detector's score as a criterion
for accepting or rejecting a question.

- Use the existing formats in `content/` and the tools described in
  [TOOLS.md](TOOLS.md). Among other things, `tools/build-quiz-pack.rb` checks
  the number of answers, duplicates and required fields; it is not a
  subject-matter editor.
- When importing, supply the correct attribution, source and licence. The
  tool's `CC0-1.0` default is not evidence that the material has that licence.
- Preserve the identity of existing questions where the set requires it.
  Do not restore a rejected item under a new identifier. The question number
  in the TXT is only a sequential number for reading, not a permanent ID.
- Questions are separate resources, not UI translation entries in PO/MO.
  [TRANSLATIONS.md](TRANSLATIONS.md) explains the separation. Do not change
  the interface language when selecting a set or translate the interface
  as a side task.
- Run targeted tests for the changed data, its registration and its export.
  Reference tests are `test/games/quiz/question_integrity_test.rb`,
  `test/games/quiz/reviewed_questions_test.rb` and
  `test/games/quiz/text_export_test.rb`; for the book-based Witcher set,
  also `test/games/quiz/witcher_books_test.rb`. Match the scope to the
  specific change.
- After approving the data, update the relevant expected counts, versions
  and checksums in the tests. Do not delete regressions or change a reference
  merely to stop a test from detecting an error.
- After changing question text, answers or categories, run from the repository
  directory:

```console
ruby tools/export-quiz-text.rb
ruby tools/export-quiz-text.rb --check
```

The readable copies in `docs/quiz-questions/*.txt` have numbers starting at 1
on a separate line before each question, answers A–D and the correct answer,
without technical IDs. After removing an item, numbering must remain
continuous. Do not edit the TXT manually instead of the source. Exports and
private editorial materials are not installer resources.

Also check any new format, display method or language in the game's actual
readout, within the authorised testing scope. For wording-only corrections,
choose proportionate checks; do not present a data test as a listening check
or a live game test.

## When the work is complete

A finished set has verified sources and usage rights, individually checked
questions, natural target-language wording, one correct answer per item and
three plausible mistakes. New items have undergone semantic duplicate review,
technical validation and a TXT update.

In the summary, give the numbers of accepted, deferred and rejected questions,
the main reasons for rejection and the actual scope of verification. Do not
promise perfection or call questions written with AI assistance “not
AI-generated”. Judge the finished content, not claims about how it was created.

A missing source, an unresolved second answer or target-language wording that
has not been reviewed means the item is unfinished. First revise and recheck it
or set it aside outside the active set. These steps are part of the author's
work, not something the user should have to discover after release.
