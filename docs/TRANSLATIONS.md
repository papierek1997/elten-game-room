# Interface translations

Edit one standard Gettext PO per language. The `locale/` directory contains:

- `CS.po`, `ES.po`, `PL.po`, `RU.po`: editable Czech, Spanish, Polish and Russian catalogs.
- `<LANG>.mo`: the four compiled runtime catalogs.
- `game-room.pot`: the generated English-message template.

English uses source messages and needs no `EN.po` or `EN.mo`. Keep the flat
`locale/<LANG>.mo` paths: both ELTEN builders encode these files as language
records with two-letter codes, and the source runtime reads the same paths.
The release staging list includes only MO files from this directory.

The catalogs contain interface labels, announcements, rules/help and the
in-app changelog. Scrabble/Krowa dictionaries, quiz questions, Taboo cards,
game IDs, board data and recordings remain separate gameplay resources.

## Editing and compiling

Use Ruby 4.0 and install the build-time dependencies once:

```console
bundle install --gemfile tools/Gemfile.i18n
```

Edit `msgstr` in Poedit or another Gettext editor. Preserve English `msgid`,
contexts, `%{name}` placeholders and plural variants. Empty translations use
the existing fallback; fuzzy and obsolete entries are not compiled.

After changing English messages or rulebook structure:

```console
ruby tools/compile-rulebooks.rb
ruby tools/translations.rb update
```

`update` refreshes references, adds empty entries and writes the POT while
preserving existing translations. It does not delete historical or dynamic
messages merely because static extraction cannot find them.

After editing a PO:

```console
ruby tools/translations.rb compile PL
ruby tools/translations.rb check PL
```

Compilation writes MO and refreshes Polish text in `tools/data/rulebooks/*.json`.
Release notes come from `lib/game_room_changelog.rb` and their PO/MO translations;
no separate Markdown copy is generated. For rules translated from the English
structure, edit wording in PO. `check` is read-only and fails on stale output.
Omitting the language processes every PO. Neither command edits PO or POT.

The former locale JSON fragments, context sidecar and compatibility manifest
have been removed. Commands do not recreate them. Existing wording regressions
use one independent reference fixture under `test/fixtures/`, never an exporter
that copies the current translation into its own expected result.

## Independently authored rulebooks

A complete rulebook may need a different chapter order in another language.
These documents live in `tools/data/rulebooks/<LANG>/<game>.json`. All supported
languages have complete editions: `EN/`, `PL/`, `CS/`, `ES/` and `RU/`.
Each file owns its sections, titles, paragraphs and
`option_chapters` mapping. Edit this source, not a second copy in PO or generated
Ruby. It is a complete document, not an interface-translation fragment.

Run `ruby tools/compile-rulebooks.rb` after editing these files. The compiler
embeds them in the existing generated game modules. At runtime a complete
localized book replaces the older English-based sections for its language,
including English itself. The root-level books and PO-based path remain the
fallback; they are not the editing source for a complete edition. Current table settings
and the application's live shortcut reference are still generated normally.
The installer needs only the generated Ruby, not these authoring JSON files.
PO compilation leaves the independently authored documents unchanged.

When changing chapter IDs, update that document's `option_chapters` mapping.
Run `test/ui/localized_rulebooks_test.rb`, the rulebook generator tests and
native navigation tests. Check every affected language, not just Polish.
The coverage test requires a complete book for every registered game in each
language declared by the manifest. Add those books when adding a language.
Write commissioned editions naturally in their own language, following
`docs/RULES_EDITORIAL.md`, regardless of who is credited as author. Preserve
existing rules or translations supplied or selected by the creator as the text
to use, unless editing is requested; report outdated passages separately.
Material provided only as a reference is not a ready-to-use text to preserve.

## Adding a language

The user guide is maintained separately from Gettext: Polish in `README.md`,
English, Czech, Spanish and Russian in `content/readme/<LANG>.md`.
The README item in the main menu selects the interface language through
`GameRoomReadmeView.path`; it does not use the optional known-language list.
When a feature, shortcut or menu path changes, update the affected sections
in every language together. Preserve the author's edits and removals.

Every new interface language also needs a complete README translation,
an entry in `GameRoomReadmeView::FILES`, and an explicit release-file entry
in `GameRoomReleaseFiles::README_TRANSLATIONS`. Run `test/ui/readme_test.rb`
and `test/tooling/locale_build_contract_test.rb` to check language coverage,
native headings and contents links, and exact document bytes in the installer.
Keep the Markdown structure and working links; do not flatten the guide or
copy its text into Ruby. A fallback language does not count as a translation.

```console
ruby tools/translations.rb new DE --name "Deutsch"
ruby tools/translations.rb compile DE
ruby tools/translations.rb check DE
```

`new` creates only a PO and refuses to overwrite one. Translate the draft
before compiling it; declare the new language in both `manifest.json` and
the embedded manifest in `__app.rb` when it is ready to ship. A translation
does not require that language in the host. The checked-in plural defaults
are in `tools/plural_forms.json`; an unsupported language can provide explicit
`--plural-forms`. No CLDR download or runtime Gettext dependency is needed.

`import-mo LANG` is an explicit recovery operation for a missing PO. It reads
the complete MO, preserving contexts and plural forms, and refuses to overwrite
an existing PO. Ordinary compilation reads only PO.

## Build compatibility

```console
ruby test/run.rb test/tooling/locale_build_contract_test.rb
```

Set `ELTEN_HOST_SOURCE` to the pinned ELTEN 3.0.4 checkout described in
[BUILDING.md](BUILDING.md). The test runs its unmodified
`build-eltenapp.rb` and `build-eltsetup.rb` on a disposable fixture, reads both
with the native loader and compares every MO byte and language ID. It also
checks manifest/staging agreement, English fallback and absence of PO/POT
from the package. It does not build a Game Room release, sign or install one.
