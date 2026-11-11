# Third-party notices

Roulette wheel and casino-chip effects use CC0 sounds by Joao_Janz and reg7783.
Sources and edits are documented in `LICENSES/ROULETTE-SOUNDS.txt`.

The bingo drawing effect uses a CC0 sound by deltaknightone.
Its source and edits are documented in `LICENSES/BINGO-SOUND.txt`.

## Krowa: SJP inflection rules

`games/krowa_support/sjp_noun_forms.rb` adapts a small subset of the noun
inflection rules in SJP.PL's `polish.aff`, version 2026-09-01. The source is
[sjp-ispell-pl-20260901-src.tar.bz2](https://sjp.pl/sl/ort/sjp-ispell-pl-20260901-src.tar.bz2),
distributed by [SJP.PL](https://sjp.pl/sl/ort/). We use the offered
[CC BY 4.0](LICENSES/CC-BY-4.0.txt) license. Contact: sjpslownik@gmail.com.

The adaptation selects noun nominative rules, rewrites suffix conditions
as Ruby regular expressions and applies them only to forms present in the
current SJP response. It imports no word list. Unclassified forms retain
the definition lookup's fallback. SJP.PL does not endorse the application.

## Polish general-knowledge question set

Since version 2.0.4.4, the “Wiedza ogólna” (General knowledge) set has used
PolQA and the 1z10 portion of MAUPQA (IPI PAN, CC BY-SA 4.0), together with
questions from Polsat's Milionerzy archive, used on the basis of the
application owner's confirmation of reuse rights. CC BY-SA does not
automatically cover that last subset. Attribution, sources, editorial changes
and the terms for each portion are described in
`content/QUIZ_PL_GENERAL_SOURCES.txt`.

## Unicode normalization

`lib/vendor/unicode_normalize/` contains Ruby's Unicode normalization
implementation, used by Game Room with its own Unicode 17.0.0 tables.
The local adaptation removes the requirement for a particular host Unicode
version and replaces implicit block parameters with explicit ones compatible
with older Ruby. Normalization data remain unchanged; we do not modify
ELTEN's `Encoding` class or disable character normalization.
The relevant license notices are in the file headers and in
`LICENSES/RUBY.txt` and `LICENSES/RUBY-BSDL.txt`.

## Battleship and Mancala

Games by **Dawid Pieper**, integrated from his contributions to this project:

- [PR #8 — Battleship](https://github.com/papierek1997/elten-game-room/pull/8),
  source `f19504ba298eaefff14e86ebfda8c6e37bcf312e`;
- [PR #9 — Mancala](https://github.com/papierek1997/elten-game-room/pull/9),
  source `4c847c8beb5eb2dd7e4b6f45af0f7587a6ee72cd`.

Local integration includes the agreed fixes, Polish translations and new
instructions. The Ayoayo variant retains the author's rules. This is not
a statement that the PRs have been merged on GitHub.

## Sounds

### Bouillabaisse — scoring-card cues

`audio/bouillabaisse_rank.opus` and `audio/bouillabaisse_card.opus`
are lower-pitched derivatives of the existing `audio/draw2.opus` cue,
by three and six semitones respectively. Duration and channel count are
preserved. The explicit authoring script is
`tools/author-bouillabaisse-sounds.rb`; these files use the project's
144 kb/s VBR Opus settings. This processing introduces no new recording
or separate license grant for the underlying sound.

### Thousand — surrender

`audio/tysiac_surrender.opus` uses “Opening/Pop-up.wav” by **GabrielAraujo**,
Freesound [242605](https://freesound.org/s/242605/), supplied by the user
with its [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) notice.
The complete HQ Ogg preview was converted to 144 kb/s VBR Opus, 48 kHz,
20 ms frames, audio mode and complexity 10. Channels, duration and level
are preserved; the original file remains unchanged outside the project.

### Thousand — contract results

The user supplied these HQ Ogg previews with their CC0 1.0 notices:

- `audio/tysiac_contract_made.opus`: “done sound” by **Licht2003**,
  Freesound [808521](https://freesound.org/s/808521/), for a fulfilled contract.
- `audio/tysiac_contract_failed.opus`: “Done sound.ogg” by **TheMrAngelGames584**,
  Freesound [674827](https://freesound.org/s/674827/), for an unfulfilled contract.

Both complete recordings were converted to 144 kb/s VBR Opus, 48 kHz,
20 ms frames, audio mode and complexity 10, preserving channels,
duration and level. The supplied originals were not changed.

### Poker — betting and pot sounds

These six recordings were supplied with
[PR #37](https://github.com/papierek1997/elten-game-room/pull/37).
The integrated Opus files preserve the contribution's audio bytes; they
were not encoded again during integration. The contribution converted
Freesound HQ Ogg previews to Ogg Opus, 144 kb/s VBR, 48 kHz, 20 ms frames,
audio mode and complexity 10.

The fold sound uses the complete “Failure Jingle.ogg”, sped up from about
3.2 to 2 seconds without changing pitch, with a gain of 1.15. The other
five recordings were converted without trimming, normalization or gain
changes. Channel counts and the imported files' metadata were retained;
the authors' attribution is recorded below.

| Application file | Original title and author | Source | License |
| --- | --- | --- | --- |
| `Audio/poker_fold.opus` | Failure Jingle.ogg — TitanKämpfer | [Freesound](https://freesound.org/people/TitanKaempfer/sounds/689902/) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `Audio/poker_check.opus` | Typewriter snippet02 — cabled_mess | [Freesound](https://freesound.org/people/cabled_mess/sounds/360602/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/poker_call.opus` | poker_chips2.wav — fartheststar | [Freesound](https://freesound.org/people/fartheststar/sounds/201806/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/poker_raise.opus` | clatter09 — SilverDubloons | [Freesound](https://freesound.org/people/SilverDubloons/sounds/817566/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/poker_pot.opus` | Coins - 27.wav — DWOBoyle | [Freesound](https://freesound.org/people/DWOBoyle/sounds/140372/) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `Audio/poker_all_in.opus` | AllInPushChips.wav — Joma86 | [Freesound](https://freesound.org/people/Joma86/sounds/532861/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) |

Full license texts: [CC0 1.0](LICENSES/CC0-1.0.txt) and
[CC BY 4.0](LICENSES/CC-BY-4.0.txt). The authors do not endorse the
application. Preserve the attribution, source links and modification
notice when distributing these sounds.

### Farkle — banking points

`Audio/farkle_bank.opus` uses “Save complete (PSX UI SFX Free)” by
heyheytheree, supplied as the [Freesound HQ Ogg preview](https://freesound.org/s/873103/)
under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
The full license is included in [LICENSES/CC-BY-4.0.txt](LICENSES/CC-BY-4.0.txt).
The complete recording was converted with `tools/encode_audio.rb` to
Ogg Opus, 144 kb/s VBR, 48 kHz, 20 ms frames, audio mode and complexity 10.
Channels, level and metadata were preserved; there was no trimming,
normalization or pitch change. The author does not endorse the application.

### 1000 miles (Mille Bornes)

The twenty-three `Audio/mille_*.opus` effects use recordings of vehicles,
brakes, a horn, liquid, air, tools, a tire, a collision and a success cue
from Freesound, SoundBible and BigSoundBank. These are not Playroom or
RS Games sounds. The licenses cover only the specified recordings, not
older application assets.

Freesound recordings came from public HQ MP3 previews, not lossless masters.
Air Wrench Short came from the PCM WAV file provided by SoundBible.
The Driving Ace, bicycle braking, handbrake release and turn-signal sounds
came from full BigSoundBank WAV/BWF files, not lossy previews.
The complete recordings were transcoded with `tools/encode_audio.rb` to
Ogg Opus: 144 kb/s VBR, 48 kHz, 20 ms frames, complexity 10, audio mode,
without trimming, normalization, channel changes or added layers. The
collision effect uses an in-game playback gain of 0.7; the file was not
normalized. It is a recording of physical metal and glass effects made by
its author, not a real road accident. Driving Ace uses a playback gain of
0.75 and Right of Way 0.8. The 50- and 75-mile pass-bys use 0.35,
100 miles 0.5, and the wheel-change air wrench 0.5; 25 and 200 miles retain
1.0, while Instant Repair uses 0.65. This limits peaks and loudness
differences during playback without changing the stored files' levels.
The new Speed Limit braking sound uses 0.35, tire puncture 0.8, and the fuel
cap and turn signal 0.7. Those last two recordings have small peaks above
full scale when decoded to floating point; playback gain prevents clipping
without re-encoding or normalization.
Refueling is represented by liquid being poured into a bottle, and fuel
draining by water draining from a metal sink; these are not recordings
of actual fuel. Driving Ace uses the complete recording of a passing,
honking car, including its quiet start and end. Right of Way uses a short
police siren, and a successful safety-card counter uses a musical success cue.
The 25-, 50- and 75-mile cards use three different recordings of cars passing
on a street, 100 miles a wet-road pass-by, and 200 miles a Le Mans racing
pass-by. These are complete recordings with quiet starts and ends, not
fragments of an engine-rev loop. They are not measurements of five speeds.
Tire protection is represented by closing a protective case's latch, not
inflation or puncturing. Tire puncture uses a separate recording, “PUNCTURE”,
described by its author as a tire puncture; wheel change uses an air wrench
on a bolt, and repair a short ratchet recording. Extra Tank uses the fuel
cap and filler-flap closing (the full 8.133125 s, without shortening).
Speed Limit uses bicycle braking; its removal uses a car's handbrake
release. Driving against traffic uses a horn, and its removal a turn signal.
These are separate recordings and symbolic associations with actions,
not duplicates of distance, refueling or red-light sounds. Instant Repair
uses the complete short recording of a cordless drill: a metaphor for quick
mechanical service, not a recording of every kind of car repair.
The containers of two shorter effects (Right of Way and the counter) were
losslessly repackaged into 20 ms Ogg pages for compatibility with ELTEN's
BASS decoder; Opus packets, metadata and audio samples remained unchanged.

| Application file | Original title and author | Source | License |
| --- | --- | --- | --- |
| `Audio/mille_accident.opus` | Car Crash (with Glass) — magnuswaker | [Freesound](https://freesound.org/people/magnuswaker/sounds/592388/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_red_light.opus` | Tires Squeaking.aif — RutgerMuller | [Freesound](https://freesound.org/people/RutgerMuller/sounds/104026/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_dirty_trick.opus` | Powerup/success.wav — GabrielAraujo | [Freesound](https://freesound.org/people/GabrielAraujo/sounds/242501/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_distance_25.opus` | Car passing by — Aiwha | [Freesound](https://freesound.org/people/Aiwha/sounds/415483/) | [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/) |
| `Audio/mille_distance_50.opus` | Car Passing — Johnnyfarmer | [Freesound](https://freesound.org/people/Johnnyfarmer/sounds/209767/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_distance_200.opus` | rbh Le Mans passby 05.wav — RHumphries | [Freesound](https://freesound.org/people/RHumphries/sounds/1930/) | [CC-BY-4.0](http://creativecommons.org/licenses/by/4.0/) |
| `Audio/mille_distance_75.opus` | Car passing by.wav — hinzebeat | [Freesound](https://freesound.org/people/hinzebeat/sounds/171447/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_driving_ace.opus` | Car Honking at 90 km/h #3 — Joseph SARDIN & Axeline T. | [BigSoundBank](https://bigsoundbank.com/car-honking-at-90-km-h-3-s3438.html), [license terms](https://bigsoundbank.com/licenses.html) | [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_fuel_drain.opus` | Drain Gurgling 2.wav — F.M.Audio | [Freesound](https://freesound.org/people/F.M.Audio/sounds/554761/) | [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/) |
| `Audio/mille_distance_100.opus` | Passing Car (Wet road) — Breviceps | [Freesound](https://freesound.org/people/Breviceps/sounds/462862/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_counterflow.opus` | Car Horn.wav — DuranBurrus | [Freesound](https://freesound.org/people/DuranBurrus/sounds/547667/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_puncture_proof.opus` | close-latch-pelicase — Eelke | [Freesound](https://freesound.org/people/Eelke/sounds/387193/) | [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/) |
| `Audio/mille_instant_repair.opus` | power drill — AlaskaRobotics | [Freesound](https://freesound.org/people/AlaskaRobotics/sounds/551504/) | [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_refuel.opus` | pour 2 — piotrkier | [Freesound](https://freesound.org/people/piotrkier/sounds/700153/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_right_of_way.opus` | Siren.ogg — egomassive; based on Police Siren Yelp.mp3 — MultiMax2121 | [Freesound](https://freesound.org/people/egomassive/sounds/536773/), [original recording](https://freesound.org/people/MultiMax2121/sounds/156868/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_start.opus` | SFX_Car_Engine_Outside_Start.wav — GiocoSound | [Freesound](https://freesound.org/people/GiocoSound/sounds/401558/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_tire_puncture.opus` | PUNCTURE — SamuelGremaud | [Freesound](https://freesound.org/people/SamuelGremaud/sounds/457442/) | [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_extra_tank.opus` | auto gas cap screw back on +lid close.wav — kyles | [Freesound](https://freesound.org/people/kyles/sounds/452546/) | [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `Audio/mille_speed_limit.opus` | Bike Brake #1 — Joseph SARDIN | [BigSoundBank](https://bigsoundbank.com/bike-brake-1-s1087.html) | [CC0-1.0](https://bigsoundbank.com/licenses.html) |
| `Audio/mille_end_speed_limit.opus` | Handbrake, released #1 — Joseph SARDIN & Axeline T. | [BigSoundBank](https://bigsoundbank.com/handbrake-released-1-s3104.html) | [CC0-1.0](https://bigsoundbank.com/licenses.html) |
| `Audio/mille_end_counterflow.opus` | Car turn signals #3 — Joseph SARDIN & Axeline T. | [BigSoundBank](https://bigsoundbank.com/car-turn-signals-3-s3108.html) | [CC0-1.0](https://bigsoundbank.com/licenses.html) |
| `Audio/mille_wheel_change.opus` | Air Wrench Short — Lightning McQue | [SoundBible](https://soundbible.com/1975-Air-Wrench-Short.html) | [CC-BY-3.0](https://creativecommons.org/licenses/by/3.0/) |
| `Audio/mille_repair.opus` | Ratchet.wav — KenRT | [Freesound](https://freesound.org/people/KenRT/sounds/319996/) | [CC0-1.0](http://creativecommons.org/publicdomain/zero/1.0/) |

Full license texts: [CC0 1.0](LICENSES/CC0-1.0.txt),
[CC BY 3.0](LICENSES/CC-BY-3.0.txt) and [CC BY 4.0](LICENSES/CC-BY-4.0.txt).
The authors do not sponsor the application. Preserve the links, attribution
and conversion notice when distributing these assets.

### Audio Ball

`Audio/audio_ball_wrong_turn.opus` — [Hit on metal - 1](https://freesound.org/s/190022/)
by **Aiwha**, licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
The user supplied the high-quality Ogg preview and license notice on
23 October 2026. The complete stereo recording was converted with
`tools/encode_audio.rb` to Ogg Opus, 144 kb/s VBR, 48 kHz, 20 ms frames,
audio mode and complexity 10. Its level, channels and metadata were preserved;
no trimming or normalization was applied. It replaces the normal goal
recordings for a doubles wrong-turn fault. The original remains outside
the application. The local license text is `LICENSES/CC-BY-4.0.txt`.

The preparation sound, `Audio/audio_ball_prepare.opus`, comes from
“auto real older car door close rattly.wav”, **kyles**,
https://freesound.org/s/452549/, licensed under **CC0 1.0**,
https://creativecommons.org/publicdomain/zero/1.0/.
The supplied Vorbis preview was transcoded to Opus 144 kb/s VBR, 48 kHz,
20 ms frames; mono and level were preserved, without trimming or pitch changes.

On 23 September, the three default flight sounds were replaced with
user-supplied files:

- `Audio/audio_ball_up.opus` — `Freesound/ball-high.ogg`;
- `Audio/audio_ball_left.opus` — `Freesound/ball-middle.mp3`;
- `Audio/audio_ball_down.opus` — `Freesound/ball-down.ogg`.

Changes: stereo-to-mono mix (0.5 L + 0.5 R where the source was stereo),
removal of silence only at the edges, adjustment of dynamics and loudness
relative to the Audiodisc pack, and Opus 144 kb/s VBR/48 kHz/20 ms encoding,
libopus audio, complexity 10. No pitch changes; originals were left untouched.

The user-supplied files are accompanied by information about these recordings:
“Golf Balls Rolling.wav”, **221227**, https://freesound.org/s/655487/,
**CC BY 4.0**, https://creativecommons.org/licenses/by/4.0/;
“Rolling ball”, **ChrisGrundlingh**, https://freesound.org/s/765635/,
**CC0 1.0**, https://creativecommons.org/publicdomain/zero/1.0/;
“Household_Large_Bottle_Roll_02.wav”, **StephenSaldanha**,
https://freesound.org/s/127871/, **CC BY 4.0**,
https://creativecommons.org/licenses/by/4.0/.
However, the renamed files do not unambiguously identify those sources;
the mapping between recordings, authors and licenses needs confirmation
before public redistribution. They do not automatically inherit the previous
files' licenses. The authors do not thereby endorse the game.

### Audio Ball — Audiodisc pack and ball stop

At the user's request, six supplied recordings from the `audiodisc` folder
were added: `discUp.ogg`, `discCenter.ogg`, `discDown.ogg`, `rocketReady.ogg`,
`rocketStop.ogg` and `rocketGoal.ogg`. Their runtime copies are
`Audio/audio_ball_audiodisc_{up,center,down,ready,stop,goal}.opus`.
The default ball-stop sound, `Audio/audio_ball_stopped.opus`, comes from
the supplied `Freesound/ball-stopped.ogg` file.

Vorbis was transcoded to Ogg Opus, 144 kb/s VBR, 48 kHz, 20 ms frames,
libopus audio, complexity 10. Stereo and available metadata were preserved,
without normalization, gain or pitch changes. Then, at the user's request,
only the edge silence of the default ball-stop sound was trimmed: about
196 ms from the start and 39 ms from the end, with a 2 ms margin. Audiodisc
sounds were not trimmed. Originals remain unchanged outside the repository.

No source identifiers or author/license information were supplied for these
seven files. The folder's origin does not establish a CC0 license or a right
to public redistribution. We do not apply the application code's license
to them; rights need confirmation before publication. Resource mapping is
described in [AUDIO_BALL.md](docs/AUDIO_BALL.md).

### Earlier assets

On 21 September 2026, all 123 recordings were standardized to Ogg Opus
144 kb/s VBR (48 kHz, 20 ms frames, libopus audio, complexity 10).
Three Krowa music tracks already used those parameters; the remaining
120 files were transcoded from the existing WAV/Vorbis sources, not merely
renamed. Mono/stereo, authorship information and other available metadata
were preserved, without loudness normalization or trimming. Where some WAV
files contained both a year and a full date, the full date represents both.
Originals were kept outside the distribution. Lossy conversion grants no
new rights to the recordings and does not guarantee identical sound.

Most files in `Audio/` come from published build 176. `connect.opus` and
`disconnect.opus` were later replaced, and `chatmsg.opus` was added from the
sound set supplied by the author. The repository has no separate document
confirming these files' original source and license. Before applying a
uniform license to the assets, supply that information or replace them
with sounds whose licenses are clear.

`hit1.opus`, used when completing a property group in Monopoly, and
`notice.opus`, used by Game Room notifications, come from the supplied
Quentin Playroom set. The repository also lacks separate license confirmation
for these files.

### New-table notification

`Audio/table_notice.opus` — [Menu Dual Click](https://freesound.org/s/145440/)
by **Soughtaftersounds / Varazuvi**, supplied with a
[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) license notice.
The author's specified notice: **Copyright © 2011 Varazuvi™ www.varazuvi.com**.

Source: Freesound `145440_Menu Dual Click_preview-hq-ogg.ogg`, downloaded
on 23 September 2026. At the user's request, the level was increased by
**9.6 dB** to bring its measured loudness closer to `notice`, then transcoded
to Ogg Opus 144 kb/s VBR, 48 kHz, 20 ms frames, preserving stereo and the
full recording. No dynamic compression or limiter was used; the original
remained unchanged. This sound is for new tables; invitations still use
`notice.opus`.

### Duck Racing

`Audio/duck_note_c.opus` — [C4.wav](https://freesound.org/people/joesh2/sounds/577691/)
by **joesh2**, dedicated to the public domain under
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
The public high-quality MP3 preview was downloaded on 12 October 2026.
`tools/prepare-duck-marimba.rb` takes the first 150 ms, with a 2 ms fade-in
and a 40 ms fade-out, to retain the challenge's existing short-note timing.
Stereo and the source level are preserved. `tools/encode_audio.rb` encodes
the prepared recording as Ogg Opus 144 kb/s VBR, 48 kHz, 20 ms frames.
Simon and sound ordering transpose this marimba C4 to other notes.
It replaces the earlier synthetic tone; the downloaded source remains
outside the application. The local license text is `LICENSES/CC0-1.0.txt`.

The rhythm challenge uses two snare recordings by **TheEndOfACycle**:

- F: `Audio/duck_rhythm_f.opus` — [Smacky Snare Drum](https://freesound.org/s/673494/).
- J: `Audio/duck_rhythm_j.opus` — [Clicky Snare Drum Hit](https://freesound.org/s/669855/).

Both are dedicated to the public domain under
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
The user supplied the high-quality Ogg previews and their license notices,
downloaded on 12 October 2026. `tools/encode_audio.rb` converted the complete
recordings to Ogg Opus 144 kb/s VBR, 48 kHz, 20 ms frames, audio mode and
complexity 10. Stereo, levels and available metadata were preserved; no
trimming, normalization or pitch shift was applied. The originals remain
outside the application. The local license text is `LICENSES/CC0-1.0.txt`.

Sound Memory uses five distinct recordings, without pitch shifting:

- `Audio/duck_memory_bark.opus` — [Single Dog Bark](https://freesound.org/people/kwahmah_02/sounds/277058/), by **kwahmah_02** (0.389 s, stereo).
- `Audio/duck_memory_bell.opus` — [SingleDing](https://freesound.org/people/NoisyRedFox/sounds/759839/), by **NoisyRedFox** (0.601 s, mono).
- `Audio/duck_memory_drop.opus` — [Single Water Drop](https://freesound.org/people/paespedro/sounds/174718/), by **paespedro** (0.472 s, stereo).
- `Audio/duck_memory_clap.opus` — [Clap 1.wav](https://freesound.org/people/Sorinious_Genious/sounds/561089/), by **Sorinious_Genious** (0.396 s, stereo).
- `Audio/duck_memory_zip.opus` — [zipper short.wav](https://freesound.org/people/ref57/sounds/361382/), by **ref57** (0.650 s, stereo).

All five are dedicated to the public domain under CC0 1.0. The public HQ
MP3 previews were downloaded on 12 October 2026. The complete recordings
and channels were retained, without trimming.
Attribution was added to the audio metadata, then `tools/encode_audio.rb`
converted them to Ogg Opus 144 kb/s VBR, 48 kHz, 20 ms frames, audio mode
and complexity 10. Sources remain outside the application; the local
license text is `LICENSES/CC0-1.0.txt`. Their playback loudness was subsequently
matched to approximately -24 LUFS using the Opus output-gain header. The
encoded audio packets, lengths, channels and attribution remain unchanged.

`Audio/duck_quack.opus` — [Cartoon - Duck Quack](https://freesound.org/people/Breviceps/sounds/445960/)
by **Breviceps**, dedicated to the public domain under
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
The source page explicitly permits copying, modification and distribution.
The publicly available high-quality MP3 preview was downloaded on 11 October
2026, downmixed to mono and transcoded to Ogg Opus 144 kb/s VBR, 48 kHz,
20 ms frames. The complete 0.383-second recording was retained, without
volume changes. The original download is a development input, not a second
copy in the installed application. The local CC0 text is in
`LICENSES/CC0-1.0.txt`.

`Audio/duck_countdown.opus` — [3 2 1 drop](https://freesound.org/s/802499/)
by **Sadiquecat**, dedicated to the public domain under
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
The user supplied the Freesound high-quality Ogg preview and its license
notice, downloaded on 11 October 2026. The quiet tail was trimmed to 2.132
seconds, with a 5 ms fade at the cut to avoid a click. The recording was
converted with `tools/encode_audio.rb` to Ogg Opus, 144 kb/s VBR,
48 kHz, 20 ms frames, audio mode and complexity 10. Mono, the original
level and available metadata were preserved, without pitch changes.
The source recording remains unchanged outside the application.
The local license text is in `LICENSES/CC0-1.0.txt`.

`Audio/duck_challenge.opus` — [XQCMinous - A2](https://freesound.org/s/639454/)
by **JWPH_2017**, licensed under
[CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/), for noncommercial use.
The user supplied the Freesound low-quality MP3 preview and its license
notice, downloaded on 11 October 2026. The full mono recording was converted
with `tools/encode_audio.rb` to Ogg Opus, 144 kb/s VBR, 48 kHz, 20 ms frames,
audio mode and complexity 10, preserving available metadata. Playback in
the game uses gain 0.21811668, before the user's volume setting.
The original recording remains unchanged outside the application. This
sound's license is separate from the game code's license.

`Audio/duck_question.opus` — [Magical Hit](https://freesound.org/s/430769/)
by **SailorErick**, dedicated to the public domain under
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
The user supplied the Freesound high-quality Ogg preview and its license
notice. On 12 October 2026, the complete stereo recording was converted
with `tools/encode_audio.rb` to Ogg Opus, 144 kb/s VBR, 48 kHz, 20 ms frames,
audio mode and complexity 10, preserving its level and available metadata.
It is played at gain 0.7 (30% quieter), before the user's volume setting,
when a square or card opens a question for everyone. No trimming or
normalization was applied; the original remains outside the application.
The local license text is in `LICENSES/CC0-1.0.txt`.

`Audio/duck_correct.opus` — [Training Program, Correct1.aif](https://freesound.org/s/181860/)
by **timgormly**, dedicated to the public domain under
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
The user supplied the Freesound high-quality Ogg preview and its license
notice. On 12 October 2026, the full stereo recording was converted with
`tools/encode_audio.rb` to Ogg Opus, 144 kb/s VBR, 48 kHz, 20 ms frames,
audio mode and complexity 10. Its level and available metadata were
preserved, without trimming or normalization. The original remains
unchanged outside the application. This personal confirmation is used for
the selected Duck Racing number challenges and a solved sound order, not
for Quiz. The local license text is in `LICENSES/CC0-1.0.txt`.

`Audio/duck_frozen.opus` — [SFX_Spell_IceShoot_02](https://freesound.org/s/790466/)
by **Omiranda14**, licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
The user supplied the Freesound low-quality MP3 preview and its license
notice, downloaded on 11 October 2026. On 12 October, the full stereo
recording was converted with `tools/encode_audio.rb` to Ogg Opus, 144 kb/s
VBR, 48 kHz, 20 ms frames, audio mode and complexity 10. Its level and
available metadata were preserved, without trimming or normalization.
It accompanies freezing and turns skipped while frozen. The source
remains unchanged outside the application. The local license text is in
`LICENSES/CC-BY-4.0.txt`.

`Audio/duck_shot.opus` — [[SEMI-RAW] P38 AC42 Shot (7)](https://freesound.org/s/710311/)
by **smill.and.welson**, licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
The author's source credit is [Great Northwest Weaponry](https://www.youtube.com/@GreatNorthwestWeaponry),
with [the source recording](https://www.youtube.com/watch?v=voXPXBbwffg) and
[the permission reference](https://www.youtube.com/watch?v=zWGpr2Ku_H0&lc=UgyjzPhBkrJCWs8R-zt4AaABAg)
included in the supplied license notice. The user supplied the high-quality
Ogg preview and its license on 12 October 2026. The complete 0.9935-second
stereo clip was converted with `tools/encode_audio.rb` to Ogg Opus, 144 kb/s
VBR, 48 kHz, 20 ms frames, audio mode and complexity 10. Its level and
channels were preserved; no trimming or normalization was applied. In Hit
the duck, playback is panned to the position chosen by the player.
The original remains outside the application. The local license text is
in `LICENSES/CC-BY-4.0.txt`.

`Audio/duck_final_lap.opus` — [Flamenco Finale 7.wav](https://freesound.org/s/41750/)
by **digifishmusic**, licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
The user supplied the high-quality Ogg preview and its license on
12 October 2026. The full stereo clip was converted with
`tools/encode_audio.rb` to Ogg Opus, 144 kb/s VBR, 48 kHz, 20 ms frames,
audio mode and complexity 10, preserving its level and channels without
trimming or normalization. It announces entry into the final lap.
The original remains outside the application. The local license text is
in `LICENSES/CC-BY-4.0.txt`.

### Wrong quiz answer

`Audio/quiz_wrong_answer.opus` — [Dat's Wrong!](https://freesound.org/s/587253/)
by **Beetlemuse**, licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
The user supplied the recording as `587253_Dat's Wrong!_preview-hq-ogg.ogg`
with licensing information. On 6 October 2026 it was transcoded to Ogg Opus
144 kb/s VBR, 48 kHz, 20 ms frames, preserving the full recording, channels
and metadata. At the user's request, its volume was reduced by 10%
(amplitude multiplier 0.9). The original was not changed. This sound's
license is not the game code's license.

### Cat, head, tail

The game and its original implementation were supplied by **TD Programs**
(account `td-programs`) in
[PR #12](https://github.com/papierek1997/elten-game-room/pull/12), commit
`7930486d9051e557b36d392af558139921fda606`. The author cites Pig from
RS Games as an inspiration. The integration preserves the author's scoring;
the PL/EN rules, the bot's decision when a draw is secured and the D shortcut
interface were refined.

The five supplied `Audio/cht-*.opus` recordings were preserved byte for byte,
without re-encoding. The submission does not include their original sources
or separate license terms. Obtain this information from the author before
public distribution; the code's license is not automatically applied to
them, nor is an infringement assumed.

### Domino and Mexican Train tile sounds

Three recordings by **poenia**, supplied by the user with
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) license information:

- `Audio/domino_refill.opus` — [Domino_sfx_refillPlayers](https://freesound.org/s/745031/), dealing tiles;
- `Audio/domino_move_tile.opus` — [Domino_sfx_moveTile](https://freesound.org/s/745028/), playing a tile;
- `Audio/domino_take_chip.opus` — [Domino_sfx_takeChip](https://freesound.org/s/745032/), drawing from the boneyard.

The sources are Freesound `preview-hq-ogg` files downloaded on
18 September 2026. Initially only their names were changed; they later
underwent the conversion described above.

### Reshuffling cards

`Audio/card-shuffle.opus` — [Card Shuffle](https://freesound.org/s/201253/)
by **empraetorius**, licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
The user supplied the Freesound `preview-hq-ogg` file with licensing
information, downloaded on 18 September 2026. Initially it was only renamed;
on 21 September it was transcoded to Opus with the parameters listed above.

### Additional doubles footsteps and UNO buzzer

`Audio/pong_move_double.opus` comes from the user-supplied
`pong-move-double.ogg` file in their Freesound directory.
`Audio/buzzer.opus` comes from the supplied Quentin Playroom set.
On 21 September 2026, they were transcoded to Opus 144 kb/s VBR, 48 kHz,
20 ms frames, preserving mono, metadata and levels, without trimming.
Originals remain outside the distribution. Separate licenses for these
recordings have not been confirmed; that does not make the whole project's
license apply to them.

### New Battleship sounds

The user supplied `hit_ship1.ogg`, `hit_ship2.ogg`, `rocket_launch1.ogg`,
`rocket_launch2.ogg`, `rocket_launch3.ogg` and `rocket_miss.ogg` from their
own Freesound directory. Initially their names and contents were preserved
without transcoding; current equivalents use `.opus` and the parameters
listed above. The missing `hit_ship3.ogg` was not added. The user materials
include recording license information, but the mapping between original
names and these six renamed files has not been unambiguously confirmed.
No single common license is assigned to them on that basis.

### Table conference notification

`Audio/conference_created.opus` uses [Message Notification 3](https://freesound.org/s/740422/)
by **AnthonyRox**, released under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
The user supplied the Freesound `preview-hq-ogg` recording and its license notice.
On 21 October 2026 it was converted to Opus 144 kb/s VBR, 48 kHz,
20 ms frames, preserving channels, level and the full recording.

### Scopa bonus

`Audio/scopa.opus` uses [PS1 Pick up SFX 18](https://freesound.org/s/869686/)
by **SignatureSoundsOrg**, released under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
The user supplied the Freesound `preview-hq-ogg` recording and its license notice.
It was converted to Opus 144 kb/s VBR, 48 kHz, 20 ms frames, preserving
channels, level, metadata and the complete recording.

`Audio/scopa_deal.opus` uses [1 carte mélange-10](https://freesound.org/s/161075/)
by **Julien Nicolas**, released under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/).
This recording is restricted to non-commercial use. The user supplied the
Freesound `preview-hq-ogg` recording and its license notice. It was converted
to Opus 144 kb/s VBR, 48 kHz, 20 ms frames, preserving channels, level,
metadata and the complete recording.

`Audio/scopa_take.opus` uses [Dealing Card](https://freesound.org/s/240777/)
by **f4ngy**, released under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
The user supplied the Freesound `preview-hq-ogg` recording and its license notice.
It was converted to Opus 144 kb/s VBR, 48 kHz, 20 ms frames, preserving
channels, level, metadata and the complete recording.

### Krowa — dictionary and recordings

Krowa was supplied by **paulinux** in PR #10 from the GitHub account
`paoscripts` (commit `50ea3081e6d6e7a59ee63eee8b7809cb643d7e50`). The noun
database and eight `Audio/krowa-*` recordings were initially preserved
byte for byte. On 21 September 2026, at the user's request, the three music
tracks `krowa-single`, `krowa-race` and `krowa-word-tower` were transcoded to
Opus 144 kb/s VBR stereo (48 kHz, 20 ms frames), without volume filters.
The last file changed its extension from `.mp3` to `.opus`. The five effects
were then also converted to this format, preserving their channel counts;
the music was not re-encoded again. The database was not changed. Originals
were retained outside the distribution. The Word Tower track's metadata
identifies “Once Again”, Moavii, 2024, publisher “Free To Use Music”; it was
preserved in the Opus file. This does not replace information about license terms.
Duplicates were not removed and word order was not changed. The submission
does not give the database's full provenance or the recordings' distribution
terms; obtain this information from the author before public distribution.
Missing information is neither a statement of infringement nor a reason
to assign the whole repository's license to these assets. Definitions
shown on request come from SJP.pl and credit that source in the window.

### Typoholism — error effects and Survival recordings

The five effects `Audio/typing_error_1.opus` through `typing_error_5.opus`
come from `Error1.opus` through `Error5.opus`, supplied by paulinux.
They were encoded once to
Opus 144 kb/s VBR, 48 kHz, 20 ms frames, complexity 10, preserving stereo
and complete recordings without level filters. Originals remain outside
the repository. Public redistribution terms have not been confirmed;
the repository's code licence is not automatically assigned to them.

The recordings `easy.opus`, `medium.opus`, `hard.opus` and `endgame.ogg`,
supplied by paulinux, were included as `typing_survival_easy.opus`,
`typing_survival_medium.opus`, `typing_survival_hard.opus` and
`typing_endgame.opus`. Originals were encoded once to the same Opus standard,
without level changes, trimming, normalisation or channel-count changes.
Metadata was retained. Their public redistribution terms also need confirmation.

### Typoholism — Polish braille tables

`Pl-Pl-g1.utb` and `Pl-Pl-g2.utb` were supplied by paulinux. Their original
bytes, headers and contraction rules are preserved. The first table and
the supporting files `spaces.uti`, `text_nabcc.dis`, `latinLetterDef6Dots.uti`,
`digits6Dots.uti` and `litdigits6Dots.uti` originate in Liblouis; supporting
files were obtained from the local NVDA installation. Their headers identify
authors and LGPL 2.1 or later. The licence text is in
`LICENSES/LIBLOUIS-LGPL-2.1.txt`; source:
https://github.com/liblouis/liblouis/blob/master/COPYING.LESSER.

The tables are embedded in `content/mania_pisania_braille_tables.rb` and
materialised in the program cache so Liblouis can read includes from a signed
package. The generator does not alter table content. The package also embeds
the Windows x86 and x64 Liblouis 3.39.0 libraries and the dependency closure
of all 32 selectable literary, contracted, computer and regional tables for
English, Czech, Spanish, Russian and Polish, as listed in
`lib/mania_pisania/braille_catalog.rb`. Supplemental include/display files are
bundled as dependencies, not offered as independent translation tables.
NVDA is not required for these languages.
Official binaries and corresponding source are available from
https://github.com/liblouis/liblouis/releases/tag/v3.39.0 under LGPL 2.1 or later.
Users may select another compatible Liblouis table in the game's settings.

The original integral `pl-pl-g1.utb` from local NVDA is preserved separately
as `pl-pl-integral.utb`, without byte changes. This keeps integral braille
independent of the two supplied tables and avoids Windows filename collisions.

The supplied `Pl-Pl-g2.utb` does not identify a separate author, provenance
or redistribution terms. Confirm these before public redistribution. Local
use does not assign the application's licence or the first table's licence
to this table.

### Typoholism — additional word dictionaries

English, Czech, Spanish and Russian word forms are generated from the pinned
wooorm/dictionaries sources using native Hunspell affix expansion and spelling
validation. Provenance, processing and source links are documented in
`content/mania_pisania_words_SOURCES.md`. Full upstream licence/credit notices
are included in `LICENSES/TYPING-WORDS-{EN,CS,ES,RU}.txt`. Polish uses a selection
of frequent inflected forms from IPI PAN's Corpus of Contemporary Polish (KWJP),
with paulinux's final manual exclusions preserved in the reviewed source list,
licensed under Creative Commons Attribution 4.0. Attribution, source and licence
links are in `LICENSES/TYPING-WORDS-PL.txt`; the pinned input and selection policy
are recorded with the other dictionaries. Hunspell is a build-time tool for the
other languages, not a runtime dependency.
