# Independent interface languages

Game Room settings include Primary interface language, then Known languages
(native multi-selection), at the start of the General category.
Known languages are optional and independent of the primary language. Language changes are
staged with the other settings: Save writes them, Cancel discards them. Quit
ELTEN completely and start it again to apply them to the entire program, including
menus and the main-screen widget. Neither closing Power Games nor the host's F12
soft restart reloads its translated data: `Programs.load_all` retains existing
Runtimes, and `load_sig` returns early for an already loaded entry.

The local `settings.json` stores language codes, not names or list indices:

```json
{"interface_language":"pl","known_languages":["en","pl"]}
```

For a new configuration, the primary language follows ELTEN when that language is
available in Game Room, otherwise English. Known languages start empty; they
are not imported from the account or selected when the primary language changes.
Existing explicit selections are preserved. There is no profile request or
write. Saving makes the choices explicit; subsequent ELTEN language/profile
changes do not overwrite them.

## Lookup and isolation

For each message, lookup tries the primary language, then the other selected
non-English languages in the order displayed in the list, then the original
English text. Selection order does not assign priority. Selecting English among
known languages does not stop lookup before another known translation. English
is complete source text, not a missing EN.mo catalog: selecting English as primary
always yields English.
Context and plural forms follow the same chain, using each catalog's plural rule.
An empty or unavailable translation is a miss, not a reason to hide the message.
Cat, head, tail explicitly allows a common-message fallback within each language:
its own context first, then the common entry, before trying another language.
Other contextual lookups stay isolated unless they explicitly opt in. The game
title itself remains Cat, head, tail in every interface language.

`GameRoomLocalization` reads the settings and MO catalogs at startup. It never
changes `Configuration.language`, the account profile, or the host dictionary.
Translation calls do not read disk or account data. Each catalog has isolated
messages and a bounded, parsed plural expression; catalog headers are not Ruby
code and are never evaluated as such.

Production Ruby scopes use `GameRoomLocalization::Translations`, a lexical
refinement. Put `using` **inside** each root class/module that calls a translation
helper. A top-level `using` fails when the host evaluates source inside its loader
method. Each separately loaded file/reopened module needs its own declaration.
Top-level content registration calls the translator explicitly. The AST coverage
test detects unscoped translation helper calls in production files.

Host-provided controls can still announce their roles in ELTEN's language.
Recorded announcer audio is unchanged. Interface language changes do not change
an existing table's question/card/dictionary language, game options, content
identity or other players' interfaces. New computer names follow the local UI language where a matching
name pool exists; existing saved name tokens are not rewritten.

## New-table content defaults

The creation form and a new widget preset use `table_creation_options`, not
locale-sensitive replay defaults. For games declaring `content_language_option_key`,
the initial content language matches the creator's Power Games interface language
(regional IDs such as `pl-PL` match `pl`). If no matching content is offered,
English is selected. Known languages and the host's separate interface language
do not influence this choice. Quiz, Scrabble and Taboo use the shared content-pack
selector; Categories and Duck Racing declare their own language option keys.

Build dependent set choices from these initial options before opening the form.
Explicit options, existing presets and remembered selections take precedence;
Duck Racing remembers its question language together with its set checklist.
For a checklist stored without a language, its installed set IDs identify the
language when the match is unique. Unknown IDs remain visible for correction.
Do not use this creation helper in normalization, replay, rematches or archive
restoration. `default_options` remains deterministic, and recorded content IDs,
versions and checksums retain their validation. Selection uses metadata only,
without loading dictionaries or question packs.

## Adding another interface translation

Supply an additional valid UTF-8 GNU MO catalog, such as `locale/CS.mo`, using the
same English message IDs, contexts and interpolation placeholders. Declare its
code in both program manifests' `supported_languages` and include it when packing.
There is no need for the host to have a Czech translation. Available choices come
from Game Room catalogs, plus source English. `X-Language-Name: Čeština` in the
catalog header supplies a native display name even when host language-name data
is absent. Invalid/missing catalogs are not offered as installed translations.

The current catalogs are Czech, Spanish, Polish and Russian, each with one
editable `locale/<LANG>.po` and one compiled `<LANG>.mo`. English uses source
messages. Historical JSON fragments and their exporter have been removed.
Only Polish fields in root-level fallback rulebooks are refreshed from PO;
complete editions under `tools/data/rulebooks/<LANG>/` remain independently
authored sources. Release notes live in
`lib/game_room_changelog.rb` and use the same PO/MO translation workflow.
See `docs/TRANSLATIONS.md` for editing, source updates and adding another language.

## Verification

Focused tests cover catalog selection, missing entries, contexts/plurals, startup
preference loading/caching, binary source scopes, settings focus/selection,
Save/Cancel, restart messaging, and the unchanged language/content of the host.
Real-host integration uses `ELTEN_HOST_SOURCE` and runs in an isolated Ruby
process, not in an active ELTEN session. Offline forms/loader checks are not a
claim of a live NVDA interaction test.
