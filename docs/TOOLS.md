# Maintenance tools

The `tools/` directory contains 12 standalone tools. It is not part of the runtime or
the installer. Run commands from the repository root.

| Tool | Purpose |
| --- | --- |
| `translations.rb` | Extract, update, create and compile Gettext catalogs; `check` makes no writes. [Instructions](TRANSLATIONS.md). |
| `compile-rulebooks.rb` | Generate rules from `tools/data/rulebooks/` according to `rulebook_sources.json`; `--check` makes no writes. |
| `generate-krowa-nouns.rb` | Reproduce Krowa nouns from `data/krowa_nouns.txt`; `--check` makes no writes. [Provenance](BUILDING.md#krowa-noun-source). |
| `build-scrabble-dictionaries.rb` | Build Scrabble EN/PL dictionaries in `content/`; argument: source directory containing `wordlist-20210729.txt` and `sjp/slowa.txt`. |
| `build-taboo-cards.rb` | Validate and build Taboo EN/PL cards in `content/` from `content/taboo_editorial.txt`. |
| `build-quiz-pack.rb` | Validate JSON questions and create the specified Quiz set; options in `--help`. |
| `export-quiz-text.rb` | Readable copies of Quiz questions in `docs/quiz-questions/`; `--check` makes no writes. |
| `encode_audio.rb` | Encode an original recording to Opus; arguments: input, new output, optionally FFmpeg and FFprobe. [Profile](BUILDING.md). |
| `generate-pong-echo.rb` | Generate Pong's echo effect from deterministic PCM to Opus. |
| `stage-release.rb` | The sole staging interface: runtime-file list, dependency verification and SHA-256 snapshot. [Procedure](BUILDING.md). |
| `benchmark-runtime.rb` | Repeatable measurements of CPU, allocations, replay, views and bots. [Methodology](BENCHMARKS.md). |
| `spades.rb` | Train and evaluate Spades bot profiles: `train` or `evaluate`. [Usage](BOT_TRAINING.md). |

`support/` contains libraries shared by these commands and tests.
`training/` contains full-match simulation, training and strategy comparison
outside the application. Configuration data and licenses stay alongside the tools.
`rulebook_option_chapters.json` maps options to rulebook chapters;
this editorial index is checked by `test/ui/rulebook_authoring_test.rb`.

Tests are run by [test/run.rb](../test/run.rb). Quality and translation-completeness
checks are ordinary tests; the reference-corpus generator is
in `test/fixtures/`. Details: [TESTING.md](TESTING.md).

Historical data-update tools, single-release audits, old comparison strategies
and command aliases have been removed. Their history remains in Git.
Do not rerun the historical question selection.
Changing a generator does not authorize changes to its data or audio.
