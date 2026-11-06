# Typoholism word dictionaries

The Polish pack `mania_pisania_words.rb` was supplied by paulinux. Its checksum
and ordering are retained for saved-game compatibility.

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
Old tables without a word-language option keep the original Polish pack.

Reproduction commands are in `docs/BUILDING.md`; input hashes, full-export
hashes/counts and runtime hashes/counts are in `tools/data/typing-word-packs.json`.
Keep existing packs immutable when updating dictionaries: changes to ordering
or words require a new pack identity and a saved-game compatibility policy.
