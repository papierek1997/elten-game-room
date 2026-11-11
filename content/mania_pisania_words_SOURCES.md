# Typoholism word dictionaries

The Polish pack `mania_pisania_words_pl.rb` contains the final 29,987 forms
reviewed by paulinux in `tools/data/typing-polish-words.txt`. This plain list is
the authoritative source: do not refill it from a corpus or restore removed
entries. The runtime pack contains exactly its words, sorted and compressed.
`tools/build-typing-polish-words.rb` validates the list without editing it and
regenerates the pack and manifest hashes. Invalid or duplicate entries cause
an error rather than silent filtering.

The initial 30,000 inflected forms came from the
[Corpus of Contemporary Polish (KWJP)](https://kwjp.pl).
The source is `freqlists/kwjp100-slowa-orth-all.csv.gz` from
[IPI PAN's data repository](https://github.com/ipipan/kwjp100-varia/tree/26d82bd8b906dfed1cfcf8f903b1650b56daeabf),
commit `26d82bd8b906dfed1cfcf8f903b1650b56daeabf`, under CC BY 4.0.
Attribution and licence links are in `LICENSES/TYPING-WORDS-PL.txt`.

The historical starting selection kept lowercase forms of 3–12 Polish letters,
with dispersion (`1-DP`) of at least 0.05 and explicit token exclusions, ranked
by descending adjusted frequency (ARF), with Unicode order breaking ties.
This policy is retained as `initial_selection` in the manifest for provenance;
it no longer generates the current pool. The owner removed 13 forms from the
starting selection. Inflections are attested in the corpus, not expanded from
affixes. The removed automatic frequency generator must not replace this review.

The former supplied Polish list and Polish Hunspell list have been removed,
including their pack-selection metadata. All Polish games use this pack;
previous Polish saved word sequences are intentionally unsupported.

The English (`en`, US spelling), Czech (`cs`), Spanish (`es`, Spain) and Russian
(`ru`) packs come from [wooorm/dictionaries](https://github.com/wooorm/dictionaries/tree/8cfea406b505e4d7df52d5a19bce525df98c54ab/dictionaries),
commit `8cfea406b505e4d7df52d5a19bce525df98c54ab`.
Each original dictionary's complete licence and attribution notice is preserved
in `LICENSES/TYPING-WORDS-EN.txt`, `TYPING-WORDS-CS.txt`,
`TYPING-WORDS-ES.txt` and `TYPING-WORDS-RU.txt` respectively. The dictionaries
retain their own licences; they are not relicensed as application code.

These sources derive respectively from SCOWL (English), the Czech dictionary
revised by Miroslav Pošta, the Spanish RLA-ES dictionary, and Alexander I.
Lebedev's Russian dictionary. Refer to the original notices for all contributors
and the applicable permissions, including the Czech GPL and Spanish LGPL terms.

The build-time exporter uses the native Hunspell library at commit
`7d725f1929a4189a3b8188649af6a6b3e302f469`. It enumerates dictionary roots,
prefixes, suffixes, cross-products and continuation affixes. Hunspell applies
Unicode conditions and checks every candidate against the original dictionary.
The selected dictionaries use UTF-8 and the normal one-prefix/two-suffix model.
Forbidden and compound-only forms that are not valid standalone words are
excluded. This enumerates finite dictionary/affix forms, not arbitrarily long
compound combinations or forms absent from the source dictionary.

Full exports preserve case, accents and punctuation, use UTF-8 and one unique
word per line, and are sorted by Unicode codepoint. Runtime packs retain words
of 3–12 Latin/Cyrillic letters, preserving case and accents. They are compressed
into blocks of 2048 words. The game opens blocks on demand and keeps a bounded
cache; it does not inflate the complete dictionaries during play.

Language belongs to the table's options, independently of each participant's
interface. The same pack checksum, seed and index produce the same word.
Tables without a word-language option use Polish.

Reproduction commands are in `docs/BUILDING.md`; input hashes, full-export
hashes/counts and runtime hashes/counts are in `tools/data/typing-word-packs.json`.
Other language packs retain their existing contents and saved sequences.
