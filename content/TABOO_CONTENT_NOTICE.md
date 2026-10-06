# Taboo — deck 1 provenance and editorial review

Date: 17 September 2026. There are 500 cards in each of PL and EN, with five
forbidden terms per card. The finished data source is `taboo_editorial.txt`;
the stable data-line number determines the ID. Do not reorder or remove lines
without a version migration. `tools/build-taboo-cards.rb` regenerates the Ruby
resources and checksums.

These decks were edited for Game Room under the project's GPL-3.0-or-later
license. They are not an import of commercial Taboo, a QC deck or a copy of an
open database. During development, the structure and quality of the forbidden
terms were compared with examples from the open-source
[tabooo](https://github.com/pawelblaszczyk5/tabooo/blob/0ffb860bdb3753093f040b423bf1debb3cea1b1a/frontend/src/helpers/card.ts)
project, published by Paweł Błaszczyk under MIT. That reference material has
about 100 entries per language; it is not the source of the stated 500 entries.
Taboo-Data was not imported, and cards from Hasbro's instructions were not copied.

Each line was reviewed for its target word and five associations; EN versions
do not always translate the Polish restrictions literally. Topics include the
home, food, animals, nature, travel, places, occupations, fantasy, sport, music,
technology, school subjects, events and abstract concepts.
Deliberate differences include Bison/plains versus Żubr/Puszcza Białowieska,
and Goose/honk versus Gęś/gęgać, without carrying Polish wordplay over into EN.
Examples that stigmatized illnesses, names of living politicians, unclear
colloquial target words and unrelated restrictions from the reference material
were left out.

Editorial checks cover spelling, natural wording, false definitions, duplicate
target words, empty fields and repeated forbidden terms. The sets are not a
catalogue of encyclopedic definitions: a forbidden term may be an association
or a contrast. Players remain responsible for judging what was said.

No trial voice rounds with human players have been conducted yet. Data checks
and software tests do not establish that all cards have equal difficulty;
such trials are recommended before public release. No new cards are generated
during play, and the game makes no requests to external text-generation services.
