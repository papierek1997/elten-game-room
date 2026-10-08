# Third-party notices

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
