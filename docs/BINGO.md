# Bingo

One free ticket per seat, 1–8 players. The table selects 30, 75, 80 or 90 balls.
The 30-ball game uses a 3×3 ticket and full house. The 75-ball game uses a 5×5
ticket with a free centre and B/I/N/G/O columns of fifteen numbers. The 80-ball
game uses a 4×4 ticket with four twenty-number columns. In 75/80-ball games,
choose a line, four corners or full house before starting. Lines include rows,
columns and either diagonal. The 90-ball game uses a 3×9 ticket, five numbers
per row and increasing values down each nonempty column. It plays for a line,
two horizontal lines and full house on the same ticket. Earlier stages are
announced; the final stage decides the match. Simultaneous winners share a draw.

Sources:

- [Sky Bingo rules](https://support.skybingo.com/app/answers/detail/sky-bingo-game-rules/)
- [Mecca: 90-ball bingo](https://www.meccabingo.com/bingo/90-ball)
- [Betfair: 80-ball bingo](https://support.betfair.com/app/answers/detail/231-bingo-what-are-the-rules-for-80-ball-bingo/)
- [Jackpotjoy: 30-ball rules and column ranges](https://www.jackpotjoy.com/uk/blog/bingo/how-to-play-30-ball-bingo-online)
- [AGLC bingo program](https://aglc.ca/sites/aglc.ca/files/aglc_files/GAIN_Resource_Manual.pdf)
  describes the 75-ball B/I/N/G/O ranges.

## Power Games controls and adaptations

Automatic marking is the default. The shared session runner calls a ball every
3–30 seconds (default five), marks tickets and checks the announced pattern.
No UI/speech/keyboard work runs in the model or executor. Drawing continues
behind other windows through the existing shared presentation bridge.

Manual mode replaces the timer with a per-call ready barrier. Enter on a called
ticket number marks it; M enters the number directly. B claims the current
pattern and finishes that player's call. R, or the Ready action, finishes a call
without a claim. All players may mark concurrently. The next draw waits for
everyone, allowing screen-reader navigation without a speed race. Claims from
the same call are collected before awarding a stage. After an intermediate
90-ball award, everyone can claim the next target on the same call or confirm
ready again. A called number may be marked later; a false claim or an uncalled
number changes nothing. If the drum empties with no valid claim, the match draws.
This ready barrier is an accessibility adaptation, not a timed commercial rule.

L repeats the last ball, D browses all calls. The ordinary F1/Ctrl+F1 help,
history, chat and volume controls remain shared. Tickets are grids, not card
hands. Spectators have call history and status but no player ticket or moves.

## Synchronization and reproducibility

An authenticated server seed creates the tickets. Each subsequent call uses a
new native dice draw to select an index in the remaining ball pool. The final
single ball uses two equally equivalent indices because native dice require
at least two sides. Numbers cannot repeat. Ticket generation uses
GameRoomRandom.shuffle and records no unseeded replay randomness.

Only the elected executor writes start/draw actions through action_for and
GameRepository. Manual events contain the call and goal indices; concurrent
input is accepted only inside that exact marking phase. Participant replacement
uses the normal decision-event projection. The native event time schedules the
next automatic call; an absent clock does not make the next call immediately
due. Server acceptance, current session/revision guards and uncertain writes
stay in the existing LiveSessions path. Tickets are public replay data.

## Sound

[Bingo Spinner by deltaknightone](https://freesound.org/people/deltaknightone/sounds/634197/)
is CC0. Its public HQ preview was downloaded, shortened to the final 2.5 seconds,
faded and reduced by 2 dB, then encoded as Audio/bingo_draw.opus. See
[BINGO-SOUND.txt](../LICENSES/BINGO-SOUND.txt). The game declares this cue through
the shared sound selector, so game volume and accepted-event deduplication apply.
