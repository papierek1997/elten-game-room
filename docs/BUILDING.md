# Testing and building

## Tests without ELTEN

Game-logic tests are standalone Ruby scripts. Translation-tool tests
also require the standard GetText gem:

```console
bundle install --gemfile tools/Gemfile.i18n
```

Ruby 4.0 is recommended, matching the current ELTEN environment.
Host-contract tests also require matching host sources (currently ELTEN
3.0.4). Set `ELTEN_HOST_SOURCE` to the directory containing `src/` and `locale/`.
In CI, the host sources are pinned to a specific commit in the test workflow.
The current pin is `3418d67dea40ee116f4a8ba545b1c409fd04706f` (release 3.0.4).
The earlier RC1 does not provide the required parallel-scene contract.

```console
ruby test/run.rb --report tmp/test-results.json
```

The runner executes scripts in separate processes and continues after a failure,
recording each result. The default limit is 180 seconds per script;
it can be changed with `--timeout`. A failure, timeout or unapproved skip
returns a nonzero exit code. A missing required dependency is not a success.
Directories, filenames or file patterns at the end of the command limit
the scope to selected checks, for example `test/games/spades` or
`test/transport/game_sync_test.rb test/transport/transport_test.rb`.
Directories are searched recursively, excluding helpers and fixtures.
The layout of games and shared layers is described in [docs/TESTING.md](TESTING.md).
`--suite models|transport|ui|native|tooling|integration` selects one layer;
`--list` shows the scope. Do not combine `--suite` with a manual file list. CI retains
the report even on failure. During the current cleanup, the restriction in
`AGENTS.md` to tests affected by the change remains in force.

## Runtime code generators

```console
ruby tools/compile-rulebooks.rb --check
ruby tools/generate-krowa-nouns.rb --check
ruby test/code_quality_test.rb
```

Rulebooks come from `tools/data/rulebooks/*.json`, and the list of owners and outputs from
`tools/rulebook_sources.json`. The compiler writes only to
`games/generated/rulebooks/`; it does not replace methods in maintained game code.
Monopoly board profiles are still generated from the current board definitions.
Gettext covers the generated rules. After changing text, update the catalogs
as described in the translation instructions below.

Both generators' `--check` mode fails on a mismatch
without fixing any files.

### Krowa noun source

The first 98 178 lines of `tools/data/krowa_nouns.txt` preserve the exact text of
`GameRoomKrowa::NounData::WORDS` from commit `0c86d03`,
without sorting, deduplication or word changes. SHA-256 of the UTF-8 text with LF:
`5e9e97a7681e662e97527a794846f965a0b789e1f47b3c06c5fc8404490d0389`.
The inputs to the old `generate_noun_data.ps1`, mentioned in the
original header, could not be established. This preserves the repository state so that
the Ruby can be reproduced, without reconstructing the former dictionary selection or changing credits and licenses.
The TXT and generator stay outside the installer; the runtime uses the generated Ruby.
Nine entries approved by the project author were appended to the list:
łam, zacios, zaciosy, prosię, silnia, silnie, afro, szmat and ksero.
On 5 October 2026, a further 60 approved entries were appended (34, followed by
another 26), without changing the previous order. The current file contains
98 247 lines; the generator
and its test check this. Adding a noun does not create a local
definition: explanations are retrieved from SJP on demand through the existing path.

## Interface translations

Edit one PO file per language, such as `locale/PL.po`. After editing, run
`ruby tools/translations.rb compile PL`, followed by
`ruby tools/translations.rb check PL`. MO and the Polish fields in rulebook documents
are generated from PO. Edit changelog entries in `lib/game_room_changelog.rb`
and their translations in PO; they are displayed directly by the application.
Word dictionaries, questions and game cards remain separate resources.
Full instructions: `docs/TRANSLATIONS.md`.

Keep the flat `locale/<LANG>.mo` layout: native builders store catalogs
as language records with two-letter codes, and the source-mode runtime
looks for this exact path. PO/POT files are not included in staging.
`test/tooling/locale_build_contract_test.rb` checks both manifests,
staging, and the actual `build-eltenapp.rb` and `build-eltsetup.rb` from
`ELTEN_HOST_SOURCE`, using a temporary application with Game Room's catalogs.
It checks the packages with the native reader and compares the bytes of every MO.
It neither creates a game release nor uses signing keys.
This test also requires `rubyzip` and `zstd-ruby`, as specified in the host's Gemfile;
CI installs versions 3.2.2 and 2.0.6 in the `native` suite.

The manifest in `__app.rb` must retain LF, as specified by `.gitattributes`:
ELTEN 3.0.4's parser does not accept CRLF at the closing `=end Elten3AppInfo`.
On Windows, a restricted token can also cause the builder's absolute
glob to return an empty result. That result is a test failure, not a valid
package; neither the file's existence nor its signature alone counts as verification.

## Running from source

For an integration test, place the application directory so that `__app.rb` is
in ELTEN's development-program directory, for example
`dev_apps/game_platform/`. Run ELTEN from source or in debug mode and
open ELTEN Game Room from the programs menu.

Use a separate test profile if the test can change table data.
Do not copy the profile, logs or MCP settings into the repository.

## Unsigned package

### Default recording format

All effects, voices, loops and music in `Audio/` use **Ogg Opus,
144 kb/s VBR, 48 kHz, 20 ms frames**, audio mode and complexity 10.
Preserve the original mono/stereo channels, volume level, complete recording and metadata.
Do not upmix mono to stereo, remove credits or normalize as an incidental change.

```console
ruby tools/encode_audio.rb C:/originals/new-sound.wav C:/src/elten-game-room/Audio/new-sound.opus
```

The tool requires FFmpeg with libopus and FFprobe in PATH; their
paths can also be passed as the third and fourth arguments. It refuses to overwrite an existing file.
Keep the original outside the package. For the next encoding, use the original,
not a previous lossy conversion. Do not re-encode a valid 144 VBR Opus file.
The asset identifier stays extensionless, for example `new-sound`.

Packaging does not perform conversion: it rejects other formats and files merely
renamed to `.opus`. It checks the Ogg/Opus header; the bitrate and frame size
are ensured by the tool's profile, not the extension. Before accepting recordings,
check decoding through ELTEN's BASS/bassopus, restarts, loops used by
the game, duration, levels and listening quality. Technical checks do not replace listening.

The targeted test `ruby test/tooling/mille_audio_continuity_test.rb` requires FFmpeg
and FFprobe in PATH. It decodes the five distance recordings, Driving Ace, red light,
puncture and puncture protection, extra tank, speed limit,
end of speed limit and wrong-way driving in 1000 Miles. It checks for varying samples,
complete decoding, and quiet beginnings and endings (50 ms windows at least
20 dB below the loudest window). It guards against the return of cut-off engine
loops, but does not assess realism or listening enjoyment.

### Installer staging

Packages are built by the tool from the ELTEN repository, but do not pass
the entire project directory to it. First prepare a new, nonexistent release
directory outside the repository. Example:

```console
ruby C:/src/elten-game-room/tools/stage-release.rb --source C:/src/elten-game-room --destination C:/build/game-room-runtime
ruby C:/src/elten3/tools/build-eltsetup.rb --unsigned C:/build/game-room-runtime C:/build/ELTEN-Game-Room.eltsetup
```

The explicit `--workspace-staging` opt-in instead permits only a new,
direct child directory of `<source>/Workspace/`. `Workspace` itself must already
exist and must not redirect to another directory through a symlink or junction.
Do not specify its root, a nested subdirectory or a location outside
that Workspace, including through an alias from another directory. In a Git repository,
`git check-ignore` must confirm that the entire
`Workspace/` is ignored; the tool does not change `.gitignore`. Example:

```console
ruby tools/stage-release.rb --source D:/Gameroom --destination D:/Gameroom/Workspace/runtime-test --workspace-staging --manifest D:/Gameroom/Workspace/runtime-test-inventory.json
```

The flag requires `--destination`; it is not used with `--check`. Without it,
staging must still be outside the source tree. The checks for canonical paths, a nonexistent
destination, the path-length limit and an inventory outside staging remain in place.
`Workspace` and its supporting materials are not part of the runtime-file inventory
and are not included in the package, including during subsequent staging from the same sources.

The Ruby used for building must have the dependencies required by ELTEN's tool,
particularly `zstd-ruby`. The simplest option is to use the runtime
prepared alongside ELTEN's sources.

## Signed package

Only the release author prepares a signed package:

```console
ruby C:/src/elten3/tools/build-eltsetup.rb --cert C:/private/author.crt.pem --key C:/private/author.key.pem C:/build/game-room-runtime C:/build/ELTEN-Game-Room-signed.eltsetup
```

The certificate and key must remain outside the repository. `.eltsetup` files
are also untracked — distribution takes place through ELTEN's program catalog.

`tools/support/release_files.rb` is the shared release-content list. It retains code,
data, audio, compiled translations, manifests, licenses and source information.
It excludes tests, tools, working documentation, import reports, editorial
materials and source translation catalogs. These files remain in the repository.
The script checks Ruby dependencies, required assets and copy consistency.
The repository's `tools/stage-release.rb` prepares staging and an optional,
deterministic hash inventory as a file next to it:

```console
ruby tools/stage-release.rb --destination C:/build/gr --manifest C:/build/gr-inventory.json
ruby tools/stage-release.rb --source C:/build/gr --manifest C:/build/gr-inventory.json --check
```

Without `--destination`, the tool only checks the sources and creates the specified inventory.
The inventory's parent directory must already exist. The inventory must be outside staging;
the check also accounts for Windows case aliases and the resolved
paths of existing directories. Invalid boundaries are rejected before any write.
The tool does not sign, install or publish the package. The old workspace script
`../tools/build-game-room.ps1` is an external convenience, not a dependency for
reproducing staging. On Windows, the new wrapper limits the staging path to
80 characters. An overly long path can cause
ELTEN's tool to return empty glob results; a valid signature alone does not prove
that the package contains code.
Specify a short subdirectory, not a drive root itself (such as `Z:/`): otherwise, the native builder
may store absolute paths instead of relative names and fail to recognize
translation or sound directories. The final content check rejects such a package.

## Preparing a release

The main `README.md` and the translations in `content/readme/{EN,CS,ES,RU}.md` are
required installer assets. The program reads the appropriate file through
`asset_path`, according to the interface language, when README is selected in the main menu.
Do not create a second copy of the text in code or include all of `docs/`.
The documents are ordinary files next to the code container in `.eltsetup`.

1. Perform checks within the approved scope. For packaging-only changes,
   check `test/tooling/release_files_test.rb` and targeted binary tests,
   including `test/tooling/release_binary_loading_test.rb GOTOWA_PACZKA`. Tests and their
   helpers come from the repository; production code must come from the installer.
2. Change the version number, build and changelog only as instructed by the author.
   Reissuing the same build does not require a new changelog entry.
3. Prepare staging, build the signed package and verify manifests, the runtime,
   the author's signature, the exact file list and each file's consistency with its source.
   Do not hide missing data by loading it from the local repository.
4. Perform targeted loading of the finished package, including on-demand data,
   rules, translations and required sounds. Do not put tests
   in the installer merely to satisfy old assumptions in the tools.
5. Installation, publication and pushing to GitHub require a separate instruction.
