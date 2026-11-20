# Duck Racing implementation plan

Status: implemented in the working sources; targeted and live-account
verification is in progress on 11 October 2026. This document records the
agreed design and acceptance requirements, not a claim that every trial has
passed. Evidence and remaining verification gaps are kept under the local,
Git-ignored `tmp/duck-racing/` directory. Building, signing and publication
remain outside this request.

Add Duck Racing to Power Games, starting with **Peaceful Pond**. This is a
separate new-game plan, not a continuation of the completed fixes plans.
The first board, its selected 37-card pool, starting feathers, unlimited
uniform card draws and the hand/feather consequences of thawing are the
maintainer's decisions, as are
the challenge selection and the specific overrides recorded below. Questions
use a shared checklist of sets for challenges, question squares and question
cards; a correct answer awards 4 feathers. Questions from squares and cards
are for all players. The distance-based freeze formula below
was designed at the maintainer's request. The decisions recorded below take
precedence over the original research proposals; they are not claims that
Power Games reproduces every rule of the source game.

## Scope

- Polish name: Wyścigi kaczek. Board label: Spokojny staw,
  retaining Peaceful Pond in the reference material.
- Two to eight players, with bots and observers using the existing table
  capacity. Observers and bots occupy places too; this does not increase
  the host's eight-participant limit.
- One board initially. Later boards can supply different square data and
  card selections without creating separate games or duplicating the turn engine.
- Peaceful Pond uses the 37 selected card types listed below as an
  inexhaustible draw pool shared by its players.
  Each eligible card type has the same probability on every independent draw;
  repetitions are allowed. A particular draw may have a type filter, with
  equal probability within that eligible subset. This is an agreed Power
  Games rule, not a claim about the original game's exact draw distribution.
- The research catalogue does not determine a board's card pool. Include
  only the selected types; other boards' selections need a separate decision.
- The current challenge scope is 18 types, including Quiz, an Audio Ball point
  and an Axel Pong point. Longest word and Anagram were removed from the
  selectable set at the maintainer's request on 11 October.
  The rejected activities are outside this implementation, not hidden or
  disabled options waiting to be switched on.
- Reuse tables, invitations, chat, history, host transfer, player replacement,
  local preferences and account saves. No new server tables are proposed.
- No teams, new ranking, new currency outside the match or original-game
  asset extraction in this scope. Use permitted existing or newly created
  audio, and preserve attribution and licences.

## Core game

The short table and invitation summary includes the lap count and question
language. Older metadata without a language does not invent one.

Entering the final lap announces the player's name and plays
`duck_final_lap`, including forward movement caused by cards. This uses the
ordinary accepted-event presentation, so refreshing a snapshot does not
repeat the sound. Moving backwards, continuing within the final lap and
crossing the finish line do not trigger it. A one-lap race already begins
on its final lap and has no extra lap-entry announcement.

Players race around a track for a configured number of laps. Before rolling,
a player may play one card. Cards spend or grant feathers, change movement
or affect other players. Some are placed on the current square; an occupied
card slot cannot receive another. Meeting another duck can start a duel.
Losing all feathers causes a temporary freeze, distinct from ordinary skipped
turns. Questions can award feathers. These mechanics are based on the
[official rules](https://qcsalon.net/en/coursecanards), with the agreed edge
cases and overrides recorded below.

Agreed starting allocation: each player receives **6 feathers per configured
lap**, once at the start of the race (`starting_feathers = 6 * lap_count`).
For example, a three-lap race starts each player with 18 feathers. This is
the chosen Power Games rule, not a claim about the original game's formula;
it does not grant another allocation whenever a lap is completed.

Each player starts with 3 cards. There is no maximum hand size. Draws keep
using the same selected pool, including after the initial deal.

The first racer to cross the finish after the configured number of laps
wins immediately, including movement caused by a card. An exact roll is not
required. Backward movement can cross any number of earlier laps, but
absolute progress cannot fall below the initial start. For example, moving
back one square from lap 2 / square 1 lands on lap 1 / square 30. Do not
clamp backward movement to the start of the current lap.

Represent an ordinary turn as explicit phases: card choice, die roll,
movement and consequences, any challenge, then completion. Keep the phase
and its continuation in replayable state. A dialog closing, reconnect or
host change must not roll again, charge twice or lose the rest of the turn.
Forced cards and automatic effects must not accidentally become a second
voluntary card play.

## Freeze and recovery

Freezing and thawing do not discard, replace or redraw a player's hand.
On thawing, award 5 feathers once. This is a grant, not a reset that removes
feathers earned by another permitted effect during the freeze.

Freeze and other skipped turns count down concurrently on the racer's own
turns. Frozen racers do not participate in ordinary duels or group challenges;
questions addressed to all players remain the exception. Die modifiers lose
a use only after an actual race roll, not while skipping a turn or rolling
inside a challenge.

If the current racer gains a skip or becomes frozen before making the race
roll, the current turn is the first skipped turn. Finish the card's complete
effect and settlement first. A skip gained after moving counts from that
racer's next turn. Frozen and ordinary skip counters still decrease together,
not one after the other.

The selected initial balance rule uses distance ahead of the last active
racer, including both completed laps and progress within the current lap.
Use absolute progress along the race, not merely the displayed square or
the player's ordinal place. Observers and departed seats no longer racing
are excluded; a frozen racer and a bot occupying an active seat still count.

For Peaceful Pond, measure the gap in squares when freezing starts:

| Gap ahead of the last racer | Own turns skipped |
| --- | --- |
| 0–9 squares | 1 |
| 10–19 squares | 2 |
| 20–29 squares | 3 |
| 30 or more squares | 4 |

For a board of length `L`, the same initial rule is
`min(4, 1 + floor(3 * gap / L))`, where
`gap = player_progress - minimum_active_progress`.
The last racer, including a tied last racer, therefore skips one turn.
The four-turn cap prevents an arbitrarily long wait when someone is far behind.

On the 30-square board, lap 2 / square 5 is 10 squares ahead of lap 1 /
square 25. Equal square numbers one lap apart are 30 squares apart, not tied.
Both laps and the distance within a lap affect the result.

Fix the duration at the start of that freeze; later movement or departures
do not continuously lengthen or shorten it. Count the frozen player's own
scheduled turns, not every other player's move. Remaining at zero during
the same freeze does not create repeated freezes or thaw rewards. This is
our initial balancing formula, not a recovered formula from QC; validate it
in short races and races with large gaps before release.

## Peaceful Pond

The following 30-square mapping was transcribed from the
[March 2026 player guide](https://blog.tecwindow.net/4209/duck-racing/) and
confirmed by the maintainer's complete square list on 11 October 2026.
Keep all square names, including repeated names; localize them in every
supported interface language. Track browsing reads the number, name and
effects; position summaries and movement history also include the name.
F means feathers; C means cards; skip means skipped turns.

| Square | English name | Polish name | Effect |
| --- | --- | --- | --- |
| 1 | On the line | Na linii startu | F +1 |
| 2 | Forest edge | Skraj lasu | F +3 |
| 3 | Front pond | Przed stawem | None |
| 4 | Left bank | Lewy brzeg | C +1 |
| 5 | Diving board | Trampolina | F +1; C +1 |
| 6 | South bank | Południowy brzeg | F +2 |
| 7 | Ducklings' nest | Gniazdo kaczątek | Question |
| 8 | Shady water | Zacieniona woda | F −1 |
| 9 | Reed path | Ścieżka w trzcinach | None |
| 10 | In the pond | W stawie | None |
| 11 | Water lilies | Lilie wodne | Skip 1 |
| 12 | On the water | Na wodzie | None |
| 13 | Warm water | Ciepła woda | C +1 |
| 14 | Cosy nest | Przytulne gniazdo | Skip 2; F +2 |
| 15 | On the water | Na wodzie | None |
| 16 | Whirlpool | Wir wodny | Move forward/backward 1–8 |
| 17 | In the pond | W stawie | None |
| 18 | Deep water | Głęboka woda | Skip 2 |
| 19 | Natural shelter | Naturalne schronienie | F +1, C +1, skip 1: independent 60% checks |
| 20 | Ducklings' nest | Gniazdo kaczątek | Question |
| 21 | Water lilies | Lilie wodne | Skip 1 |
| 22 | North bank | Północny brzeg | C +1 |
| 23 | Paddling pool | Brodzik | Everyone C +1 |
| 24 | Off the water | Poza wodą | F −2 |
| 25 | Right bank | Prawy brzeg | C +1 |
| 26 | Resupplying area | Punkt zaopatrzenia | C +2; F +2 |
| 27 | Sandbox | Piaskownica | Pass hands to neighbours |
| 28 | Wooden zone | Zalesiony teren | C +2; F +2 |
| 29 | Puddle of water | Kałuża | C +1 |
| 30 | Finish line | Meta | F +1 |

Agreed: square effects trigger on landing, including movement caused by cards,
not merely on passing a square. Resolve the square first, its placed card
second, and an encounter with the last arriving occupant third. If an effect
moves the duck, resolve the new destination before continuing consequences.
Square 19 makes three independent 60% checks, one per listed effect; any
combination, including all three or none, is possible. Store absolute
race progress separately from the displayed square, so moving backwards
across the start cannot corrupt the lap count. Keep arrival order for shared
squares, rather than deriving it from player-list order.

## Cards

The guide describes 49 cards and 34 challenge families, but explicitly does
not claim a complete catalogue or give a complete card-to-board mapping.
Treat them as a research inventory, not a promise that no other cards or
challenges exist. The maintainer's card and challenge selections take
precedence over that inventory.

### Selected cards for Peaceful Pond

The approved initial pool contains **37 card types: items 1–11 and 23–48**
from the numbered selection list. Keep those reference numbers and English
names so further decisions identify the same cards. Items **12–22 and 49**
are not selected for this pool; adding any of them requires a later decision.
This is the Power Games selection, not a verified reconstruction of QC's
Peaceful Pond deck.

| Reference number | English card name |
| --- | --- |
| 1 | Mine |
| 2 | Interested help |
| 3 | Helix |
| 4 | Hand switch |
| 5 | Yellowbelly die |
| 6 | Challenge |
| 7 | Tar stain |
| 8 | Soporific pill |
| 9 | Paid service |
| 10 | Opportunistic die |
| 11 | Investment |
| 23 | Ejectable seat |
| 24 | Withdrawal |
| 25 | Super glue |
| 26 | Long absence |
| 27 | Detour |
| 28 | Guided missile |
| 29 | Super challenge |
| 30 | Winning die |
| 31 | Shortness of breath |
| 32 | Impulsion |
| 33 | Taste for risk |
| 34 | Home made bomb |
| 35 | Sandwich |
| 36 | Counter-current |
| 37 | Hand mix |
| 38 | Card rob |
| 39 | Planified deal |
| 40 | Repairing rest |
| 41 | Curiosity |
| 42 | Tiny recoil |
| 43 | Good draw |
| 44 | Oil stain |
| 45 | Die normalizing |
| 46 | Altruism |
| 47 | Thick die |
| 48 | Golden sleep |

The maintainer resolved the conflicting Impulsion descriptions in favour of
a 3-feather cost for moving 2 squares. Golden sleep grants its target 6 new
feathers from the game and skips that target's next two turns; the feathers
are not taken from the card's user.

### Card data and drawing

Create one checked card manifest: stable type ID, physical-card ID, cost,
allowed targets, placement mode, tags, effect parameters and source status.
Draw uniformly by eligible card type within the board's selected pool, with
replacement. A type filter only narrows that pool; it never introduces an
unselected card. Each drawn copy gets its own physical ID even when several
copies share a type. Do not implement
deck depletion, copy quotas or reshuffling. There is no maximum hand size;
the initial deal gives each racer 3 cards.
Automatic and passive card categories described by the official rules need
actual identified cards before being considered implemented.

## Selected challenges

Keep the numbers from the original 34-item discussion so subsequent decisions
refer to the same activities. These numbers identify challenges, not squares
on Peaceful Pond. Retain **1, 2, 3, 4, 6, 7, 8, 9, 19, 20, 21, 22, 24, 25,
26, 27 and 28**. Add Quiz as a challenge as well as a square or card event,
plus two-player, single-point challenges in Audio Ball and Axel Pong.

Exclude **5, 10–18, 23 and 29–34** from the initial implementation: roulette,
atomic numbers, unit and number-base conversions, secret code, coloured
buttons, sum 15, weights, balancing scales, treasure or mine, melody repetition,
Braille tasks, drawing a die, picture memory, the digital display and
not-being-last. Do not implement these incidentally as shared challenge code.

The maintainer has accepted the group settlement, bust penalties, speed
conversion, number-guess ranking, Simon scoring, challenge participation,
realtime starting rules and the time/attempt limits from the detailed review.
The accuracy conversion below is an initial design chosen at the maintainer's
request. These choices are not claims about the original game's exact rules.

Every challenge definition needs:

- eligible participants and its trigger;
- instructions and actual controls;
- shared stimulus, private input and permitted public information;
- start condition, deadline and completion condition;
- scoring, ties, missing input and feather transfers;
- rules for disconnects, replacement, host transfer and bots.

### Participants and encounters

Agreed: meeting another duck starts a two-player duel. A targeted challenge
card also involves its user and the chosen opponent; a group challenge card
involves all eligible racers. Questions from squares and question cards go
to all players as specified in the Quiz section.

The [official duel rules](https://qcsalon.net/en/coursecanards) specify that
arrivals are paired with the preceding arrival on the same square. With
A already there, B duels A; C then duels B; D then duels C. Three or more
ducks on a square do not start an all-player challenge or a series of duels
against every occupant. The previous duel's winner does not choose the next
opponent. Track the order of actual arrivals among current occupants, rather
than using seat order, race ranking or a former occupant who has left.

The lap number does not prevent an encounter: sharing a square is enough.
Skip frozen occupants when finding the most recent eligible arrival. Ordinary
skipped turns alone do not exclude a duck from a challenge.

Filter random challenges by participant count. Rock paper scissors, numbered
balls, sound memory, Audio Ball and Axel Pong are two-player activities;
do not select them for a group of more than two and silently leave people
out. Frozen ducks are excluded from non-question challenges, as specified
in the agreed freeze rules above.

### Common settlement and input rules

- Agreed: use the difference between results wherever the challenge provides
  a meaningful numerical comparison. Do not impose a generic 3-feather reward
  or cap. Direct counts such as dice totals, ball scores, word lengths,
  completed sequence lengths and collected pairs use their score difference.
  Timing and scaled accuracy use the conversions below; do not turn
  milliseconds or a raw 0–500 accuracy score directly into feathers.
- Quiz retains its agreed grant of 4 feathers per correct answer. Audio Ball
  and Axel Pong retain their agreed 5-feather transfer for one point.
- Agreed group settlement: a unique winner takes the applicable difference
  from each loser. Scores of 16, 10 and 8 transfer 6 and 8 feathers to the
  winner. A tie for first produces no transfers, including from lower places.
  Independent bust penalties still apply when the best result is tied.
- Agreed balance rule: a player cannot pay more feathers than they hold.
  Settle the complete outcome before checking who freezes, including separate
  burned penalties. For a bust, settle the transfer first and burn the penalty
  from the remaining balance; do not create debt or missing feathers.
  Freeze zero-feather racers before opening a queued follow-on challenge,
  even if they had no feathers available for the just-settled transfer.
- Simultaneous private choices remain private until resolution. First-answer
  challenges publish and verify completed attempts directly in server order,
  without a commit/reveal barrier. Missing input never
  becomes a random answer. If nobody records a valid result or qualifies for
  an agreed fallback, nobody wins. Guess the number permits closest answers.
  In Simon, an eventual mistake ends the attempt but preserves the completed
  sequence score; everyone ending with a mistake does not cancel the result.
- Copy the number, Mental arithmetic, Question about the race and Count the
  ducks end on the first accepted correct answer, with a fixed 4-feather
  transfer per loser. No correct answer means no transfer. Other players'
  unfinished attempts stop when this resolution arrives; late answers and
  retries cannot change it. Local input traces are still validated.
- Order the sounds keeps the agreed speed reward: 1 feather per started second of a loser's slower
  correct completion, capped at 5 feathers per loser and subject to the
  available-balance rule. Compare locally elapsed time rounded to 0.1 s,
  excluding delivery delay; equal measured times tie. With integer tenths,
  the transfer is `min(5, ceil((loser_time - winner_time) / 10))`.
  This cap applies only to speed challenges, not score differences, accuracy
  or the separate fixed stakes. The measurement and validation path still
  needs the live checks described below.
- A player without a correct completion cannot win and pays up to 5 feathers
  to the unique winner. Keep that player's time absent rather than inventing
  a completion at the deadline. If nobody finishes correctly or the best
  correct time is tied, there is no transfer. Reaching the deadline is too
  late to submit a new answer; it must not tie a successful result through
  rounding.
- Copy the number, Mental arithmetic, Question about the race and
  Order the sounds play the recorded “3, 2, 1, drop” countdown after presenting
  the task and a fixed 5-second preparation pause. Never wait for the
  synthesizer or its completion index. Only after the recording ends may input
  open and both measured response time and the existing answer allowance begin.
  Use actual playback completion, not an assumed fixed recording length; trim
  the quiet tail and do not discard the first fresh input in the completion
  frame. Count the ducks first plays the full quack sequence, then a
  3-second pause and countdown, then opens its 20-second response allowance.
  F5 does not replay the countdown or restart the timer.
  Guess the number keeps its two-minute limit and uses distance-based stakes; Simon and
  the other score/accuracy challenges do not gain this preparation pause.
- Selected accuracy reward: normalize rhythm and target accuracy to 0–100%,
  then transfer 1 feather per started 10 percentage points of advantage.
  For a positive gap, use `ceil((winner_accuracy - loser_accuracy) / 10)`;
  equal accuracy ties. Examples: 90% against 60% transfers 3 feathers;
  100% against 40% transfers 6; 83% against 79% transfers 1. Compare the
  unrounded normalized scores; rounding for speech must not change results.
  This is our initial balance rule, not a recovered QC formula. Accuracy
  challenges do not use a speed tiebreak.
- Only the focused game control receives challenge input. Holding a key must
  not create repeated decisions from keyboard autorepeat. Chat remains usable.
- Turn-based challenges choose the starter randomly once, from participants
  who still have a decision to make, then follow the fixed cyclic seat order.
  Dice duel advances after one accepted roll. Blackjack and Risky dice keep
  the same player for the whole attempt; each draw or roll renews that player's
  30-second decision allowance. This does not change the parallel attempts
  in speed challenges or private Quiz and rock/paper/scissors choices.

### Challenge 1 Rock paper scissors

Two players, one private choice each, arrows and Enter; the agreed deadline
is 15 seconds.
Reveal both choices together and use the usual rock/paper/scissors cycle.
Identical choices tie. No repeated rounds merely to force a winner.
The agreed stake is 3 feathers from the loser;
there is no numerical performance gap to convert in this activity.

### Challenge 2 Dice duel

Agreed: Enter rolls. Active cards that modify a player's die also modify this
roll. Feathers are transferred according to the difference between the
effective results, not a fixed challenge fee. For example, a result of 6
against 2 means a transfer of 4 feathers, subject to the loser's balance.

Challenge rolls never consume active card effects, including an effect for
the next roll only. They neither remove a modifier nor reduce its remaining
uses or race-turn duration. Effects are consumed only during the ordinary
duck race, according to the card's rule. This also applies to repeated rolls
in challenge 4.

Two to eight participants, taking turns for one roll each; the unmodified die
has six sides. A unique highest result takes the difference from every lower
result; tied highest results cause no transfers. Each player has 10 seconds
from the start of their own turn, followed by one automatic roll if needed.
Publish that roll immediately and advance to the next unrolled participant.
An Enter press racing the deadline must not produce a second roll.

### Challenge 3 Blackjack

Agreed: compare card totals by closeness to 21 and base the feather transfer
on the difference, rather than charging a fixed 3 feathers. Going over 21
also causes a feather penalty that is removed from the game, not awarded
to another player.

Two to eight players, two cards initially, number cards at
face value and face cards worth 10. An ace is assigned 11 when drawn if
that keeps the total at or below 21; otherwise it is assigned 1. Its value
is then fixed: later cards never revalue an earlier ace. Apply this in draw
order to the initial two cards too. Space draws one card and
Enter stands. Each player completes their entire attempt before the next
unfinished participant acts: drawing below 21 keeps the turn;
hands and totals are public. Announce each initial two-card hand and its total
once when the challenge begins, including a natural 21. Later draws and stands
remain separate public actions. Announce the randomly chosen starter after
the deal. Allow 30 seconds for each decision, not for the
whole challenge; timeout stands automatically. Reaching 21 stands,
exceeding 21 busts. The highest non-busted total wins. There is no dealer,
split, double, insurance or special natural-blackjack bonus. These cards
are separate from the race hand.

Each participant receives a separately shuffled 52-card deck. Physical cards
do not repeat within that deck. Another participant's input timing cannot
change the next card in this player's deck.

Agreed: the highest total at or below 21 wins; a busted total never wins.
With a unique valid winner, each loser transfers the absolute difference
between their total and the winner's total. A busted player additionally
burns the excess over 21. Thus 20 against 17 transfers 3 feathers; 20 against
24 transfers 4 to the winner and burns 3 more. If everyone busts, there is
no winner or transfer, only each player's excess penalty. If valid winners
tie, there are no transfers, but busted players still burn their excess.
Apply the available-balance and settlement-order rules above.

### Challenge 4 Risky dice

Agreed: active die modifiers apply to every roll without being consumed,
as in challenge 2. Enter on the roll command throws the dice. The same player
may keep rolling until the whole attempt ends. Down selects “Save result”,
and Enter on that command stops rolling and keeps the current total, then
passes to the next participant who has not finished.
Do not require Space for repeated rolls or make Enter always stand.
For valid totals, transfer the difference rather than a fixed stake.

Agreed: the ceiling is **25**, with 30 seconds for each decision. Two to eight
players take turns completing their attempts, rolling two dice at a time and
adding their effective values to their own running totals. Rolls and totals
are public. Each own roll starts a fresh 30-second allowance; there is no
separate limit for the whole attempt.
At least one roll is required; timeout saves the current total, making one
automatic roll first if none has been made. Reaching 25 saves the result;
exceeding it ends the attempt. Each of these endings advances to the next
unfinished participant. The highest non-busted total wins. Use the
Blackjack settlement above with 25 replacing 21: 24 against 28 transfers
4 feathers and burns another 3. If all bust, only the excess penalties apply.

### Challenge 6 Guess the number

Numeric input, as agreed on 11 October: all five typed-number challenges
(Guess the number, Copy the number, Mental arithmetic, Question about the
race and Count the ducks) submit immediately on the required final digit.
The answer's digit count is an explicitly accepted public hint, including
for the secret number. There is no debounce or three-digit zero-padding
requirement. Announce the width briefly; do not repeat an explanation of
automatic submission during play. For Count the ducks, give the hint after
playback and keep input closed during playback and preparation. The rulebook
explains the controls. Restoring a draft does not submit it, and an extra
Enter must not send the same edit twice.

T, S, C and V also work in these numeric edit fields. P repeats the current
public task (the displayed number or question), without revealing the secret
target in Guess the number. Modified editing keys remain editing keys, even
when pressed and released within one UI frame. Chat keeps ordinary typing.

Agreed: each player has up to **10 attempts**. If nobody finds the exact
number, the closest submitted answer wins instead of ending the challenge
with no winner.

One shared secret integer from 1 to 999, private attempts with higher/lower
feedback and a 120-second deadline. Compare only each player's closest
attempt, not their last one, number of attempts or elapsed time. Equal best
distances, including two exact answers, tie. A missing answer cannot win.
The winner takes feathers according to the advantage over each opponent:
`d = opponent_best_distance - winner_best_distance`. The number of digits
in the hidden target selects the scale, not the submitted guesses:

- Targets 1–9: `min(5, ceil(5 * d / 8))`. Gaps of 1, 4, 6 and 8 cost
  1, 3, 4 and 5 feathers respectively.
- Targets 10–99: `min(5, ceil(d / 10))`.
- Targets 100–999: `min(5, ceil(d / 100))`.

A missing answer or forfeited private trace cannot win and pays 5 feathers
to the unique winner. Actual transfers cannot exceed the loser's balance;
no winner or a tied closest distance means no transfers. A non-exact winner
uses the same scale, so target 47 with best guesses 46 and 35 costs 2 feathers,
whereas guesses 46 and 48 tie. Bot guesses also cover 1–999. The private
verifier derives the target from the agreed seed after checking the traces;
no client-supplied target or claimed score selects the reward band.

### Challenge 7 Copy the number

Two to eight players hear the same three-digit number and type it. Submit
automatically after the third digit, including a complete pasted number;
Enter is not required. Backspace corrects a draft before it is complete.
Allow 15 seconds and three submissions. The first correct answer accepted
in the shared server history immediately wins and takes 4 feathers from
every loser; do not wait for the remaining players or compare local clocks.
Rereading does not restart time. A restored draft or an extra Enter must not
submit the same edit twice, but entering the same wrong number again is a
new attempt. The other typed-number challenges use the same completion
mechanism with their announced answer width.
The deadline and attempt count are agreed. If nobody answers correctly,
there is no transfer. Late answers and retries cannot settle a second time.

### Challenge 8 Mental arithmetic

Draft: addition/subtraction within 100, multiplication using factors 2–12,
or division with an integer result. Two to eight players, 20 seconds,
three submissions. The first correct answer accepted in the shared history
immediately wins, taking 4 feathers from each loser. Avoid fractions and complex
expressions in the initial pool.
The deadline and attempt count are agreed. Do not compare elapsed times.

### Challenge 9 Question about the race

Draft: a numeric question about public race information, fixed at the start
of the challenge. Two to eight players, 20 seconds and two submissions;
the first correct answer accepted in the shared history immediately wins
and takes 4 feathers from each loser. Normal status shortcuts remain available.
Do not ask for an unambiguous ordinal position when racers are tied.
The deadline and attempt count are agreed. Do not compare elapsed times.

### Challenge 19 Numbered balls

Agreed: keys 1, 2 and 3 immediately take that many balls from the front of
the shared ordered row. There is no separate Enter confirmation. Arrows
browse the remaining balls in their actual order; digits do not navigate
the list. The difference between final scores determines the feather
transfer, capped at 10; equal scores transfer none.

Retained draft: two players take turns over 12 balls with signed values
drawn from ±1, ±2, ±3, ±7 and ±10. Each player's score is the sum of their
balls, not the number collected. Randomly choose who starts; the agreed
turn limit is 60 seconds per decision. Announce the actual values taken,
then whose turn comes next. On timeout take one ball, as in the detailed
proposal. An unavailable count should be rejected, not
silently reduced when fewer balls remain.

### Challenge 20 Longest word

Removed from the available challenges on 11 October. The following is retained
design history, not an active game option.

Draft: two to eight players receive the same nine letters, selected so at
least one five-letter word is possible. Allow 45 seconds and multiple
submissions, retaining each player's longest valid word. Respect letter
multiplicity and accents. Longest word wins, without a speed tiebreak.
Following the agreed difference rule, a valid eight-letter word against a
valid five-letter word transfers 3 feathers; a larger gap transfers more.
The agreed limit is 45 seconds, with unlimited submissions. A participant
with no valid word has length zero and cannot win against a valid word.

### Challenge 21 Anagram

Removed from the available challenges on 11 October. The following is retained
design history, not an active game option.

Draft: show a five-to-eight-letter word with a verified different anagram.
Players submit another dictionary word using every letter exactly once.
Two to eight players, 30 seconds, three attempts; fastest correct answer
wins. Repeating the original word does not count.
The deadline and attempt count are agreed. Use the common speed conversion.

### Challenge 22 Count the ducks

Agreed: two to eight players hear the same sequence of 5–15 non-overlapping
quacks. Draw one steady pace for the whole challenge: 400–900 ms from the
start of one sound to the next, using the current approximately 385 ms clip.
Do not vary the gaps within that sequence; F5 repeats the same pace.
After the full first playback and a fixed 3-second pause, play the recorded countdown. Only after that
recording finishes, open input and start the 20-second answer allowance.
Do not wait for speech completion or repeat this pause on F5. Typing the required
digits submits the count. Allow two submissions; the first correct answer
accepted in the shared history immediately wins and takes 4 feathers from
each loser. F5 replays only the quack sequence, without another countdown or a timer
reset.
The deadline and attempt count are agreed. Do not compare elapsed times.

### Challenge 24 Repeat the rhythm

Initial design: two tones bound to F and J, six to ten beats, identical for
all participants. Allow one extra playback before the attempt. The agreed
limits are 15 seconds to begin, one attempt, and three seconds of inactivity
during the response; do not add a second overall response deadline.
Enter starts the response; F and J record its tones. A second listening
does not restart the readiness deadline.

Selected scoring design, normalized to 0–100%:

- Up to 50 percentage points for the correct tones in their correct places:
  `50 * correct_positions / sequence_length`. Missing tones score zero.
- Up to 50 for the gaps between successive presses. Compare each gap with
  its corresponding recorded interval. An absolute error up to 80 ms earns
  full credit for that interval, over 80 and up to 160 ms earns half, and a
  larger error earns zero. Missing intervals score zero. Divide the sum by
  the expected number of intervals before multiplying by 50.
- The first press establishes the response's time origin; reaction delay
  before it is not a rhythm error. Subsequent presses occupy successive
  sequence positions, so a mistaken extra press cannot be deleted and retried.
- End after the expected number of presses or the inactivity deadline.
  Silence or an unstarted attempt has zero accuracy. Equal final accuracy
  ties; there is no speed tiebreak.

Use the common accuracy conversion: 1 feather per started 10 percentage
points of advantage. These are initial balancing values, to be checked by
listening and live trials, not claimed measurements of input/audio precision.

### Challenge 25 Order the sounds

Updated agreement, 11 October: two to eight players arrange the eight notes
of a major scale from lowest to highest. Digits 1–8 preview the note at that
position; two Shift+digit presses swap positions. There is no sound list or
arrow/Enter selection. An accepted swap plays both resulting notes in
position order, only to the player making the swap.

The first accepted fully correct arrangement ends the challenge for everyone.
Do not compare local completion times. Freeze each opponent's arrangement at
that action and charge one feather per misplaced note, capped at five and at
the available balance. The existing 45-second deadline only ends an unsolved
challenge without a winner or transfers. Previews are local and unscored;
swaps use the ordinary shared action log, not a private completion trace.

### Manual sound preparation, agreed 11 October

Simon, Hit the duck, Repeat the rhythm and the Audio Ball point have an
unscored preview before their normal start. Enter or Space confirms readiness;
all participants must confirm. Bots become ready through the existing runner.
The preview starts neither a challenge clock nor a scored attempt:

- Simon: digits 1–5 play the five tones.
- Hit the duck: digits 1–9 play the nine spatial positions.
- Repeat the rhythm: F/J play the low/high tone.
- Audio Ball: W/Up, D/Left and S/Down play the respective ball for two seconds,
  using the player's chosen sound pack.
- Axel Pong also waits for both players to confirm readiness, after a short
  instruction explaining the goal, Left/Right movement and Up/Space hitting.
  It does not create a second practice physics model.

No speech-completion check determines readiness. Keep chat/help inputs separate
and do not reuse the readiness key as the first game action. Keep participant
heartbeats running while preparing, including Audio Ball and waiting bots.
Other challenges retain their existing entry path.

### Challenge 26 Simon

Agreed: no fixed total time and no fixed sequence-length limit. A mistake
ends the attempt. Allow 5 seconds for the next press, starting only after
the sequence has finished playing and resetting after each accepted key.
The clock must not run during playback; a longer sequence must remain
possible to hear. Do not reset inactivity merely for focus changes or
keyboard autorepeat.

After a successfully repeated sequence, wait one second before playing the
next sequence. This pause does not apply to the initial sequence and does
not consume the five-second response allowance. Input remains closed during
the pause as during playback.

Agreed: the challenge ends only when the last remaining participant makes
a mistake or reaches the five-second inactivity limit. Being the only player
still succeeding does not end it, even if victory is already certain. That
player continues to improve the final result and therefore the feather gap.
The sequence may grow for as long as a player succeeds; do not impose the
previously discussed 30-sound fallback cap or an overall deadline. Any actual
implementation limit must be raised with the maintainer before changing this
completion rule.

Agreed settlement: compare final sequence scores and transfer the difference,
without a 3-feather cap. A score of 16 against 10 transfers **6 feathers** from
the lower-scoring player to the higher-scoring player, subject to the agreed
available-balance rule. Resolve transfers only after every attempt has ended.
Use the agreed group/tie policy in the common rules above.

Two to eight players, five tones on keys 1–5, starting with
one sound and adding one after each completed level. Playback starts at
500 ms between onsets and shortens that interval by 10 ms per completed
sequence, down to 300 ms. Tempo depends on the listener's sequence length,
not another player's progress; all sounds within one sequence are evenly
spaced. The one-second inter-sequence pause and five-second input allowance
are unchanged. Everyone follows the
same growing sequence at their own pace. The score is the length of the
longest fully completed sequence, as explicitly agreed, not the sum of presses
across all levels or a partial final sequence. Equal lengths tie. No replay during a response.
After an error or timeout,
finish that player's attempt once, without resetting the other's progress.

### Challenge 27 Sound memory

Agreed: number keys directly uncover and play sounds. Press the first number,
hear its sound, press another number and hear that sound. Use one game
control, without a separate grid, selector fields or Enter confirmation.
Finding a pair does not grant another turn: play passes to the other player
after both choices, whether they match or not.

Retained draft: two players, ten positions holding five pairs, numbered
1–9 and 0. Matched pairs leave play; unmatched positions turn back over.
The two choices must be different available positions. Most pairs wins.
The agreed deadlines are 15 seconds for the two choices in a turn and
90 seconds overall. A turn timeout hides any unmatched revealed sound and
passes to the other player. End when all pairs are found or time expires;
compare collected pairs. Ordinary chat/history fields are not removed.
Following the agreed difference rule, four pairs against one transfer
3 feathers; five pairs against none transfer 5, not a fixed 3.

### Challenge 28 Hit the duck

Draft: two to eight players hear five stereo targets at nine horizontal
positions. Keys 1–9 select a position, with 1 at the left, 5 in the centre
and 9 at the right. The agreed limit is 3 seconds per target. Scores are 100 for
the exact position, 75 one place away, 50 two away, 25 three away, otherwise
zero. The first digit commits the answer; no answer before the deadline
scores zero. Normalize the sum of five targets by dividing it by 5, giving
0–100% accuracy. Use the common accuracy conversion, not raw points as
feathers: totals of 450 and 300 mean 90% and 60%, transferring 3 feathers.
Compare accuracy, not reaction time. Check stereo accessibility and provide
a way to learn the sound positions before competitive use.

Accepted human shots play `duck_shot` at the chosen digit's stereo position,
not the target's position. Once the recording finishes, speak one word for
the existing score (100/75/50/25/0), then wait two seconds before playing the
next target. Its response clock starts at actual playback onset. The last
shot's feedback finishes before its trace is submitted. These cues are local;
they neither disclose another person's target nor alter accuracy scoring.

### Quiz challenges and questions from squares or cards

Agreed: a quiz question can be a challenge, a consequence of entering a
question square, or an effect of a question card. A correct answer grants
**4 feathers**, using the same reward for all three paths. This replaces
earlier draft rewards and does not require assigning difficulty ratings to
existing questions.

Questions from a square or question card are answered by **all current
players**, not just the person who landed on the square or played the card.
Observers do not answer. Each correct player receives 4 feathers; these are
new feathers, not transfers from incorrect players. Do not exclude a player
from these questions merely because their duck is frozen.

The table settings must provide a **checklist of available question sets**.
The host can select more than one set. All three triggers draw from the same
selected pool; do not create separate settings or a fixed hidden set for
questions from squares or cards. Reuse the existing content catalogue and
display localized set names, with language information where needed.

Store the selection by stable set IDs as part of shared table/game options,
not as a preference that each client can apply differently. Preserve it
through a rematch and save/restore. Resolve a question once from that pool;
clients must not independently draw different questions. The selection is
editable with other table rules before a match, not during an active question.

If questions can occur, require at least one selected, usable set before
starting. Never substitute an unselected set or another language when the
selection is empty, unavailable or incompatible. Report the problem and
allow the host to correct the selection. Default selections and weighting
across sets are now agreed: select only the general set in the chosen language
by default. Other sets require selection. Each selected set has the same
chance, then a question is selected uniformly within it. An unavailable
selected set remains an error, not a silent switch to another one.

Fresh table creation does not remember question sets or their language: use the
creator's interface language (English fallback) and its general set every time,
ignoring older question preferences. The separate challenge checklist remains
remembered. Explicit presets, existing tables and saved games retain their pool.

Private ABCD answers with an agreed 20-second deadline; resolve as soon as every
required participant has answered. Each correct participant earns 4 feathers;
no speed bonus or penalty for an incorrect answer. A duel question involves
the two duelists; a group quiz challenge involves all eligible participants.
Square and question-card questions include all players as specified above.
Freeze the question and eligible participant set when the event starts, keeping
the correct answer private until resolution. Reuse the existing content
provider and private-answer storage, not another Quiz table or the whole
Quiz lifecycle. This work does not rewrite the question sets.

Word challenges use the existing licensed Scrabble dictionaries for the
chosen language, as agreed in the preceding discussion. The question-set
checklist is not a dictionary selector. A missing resource is a visible
limitation, not an unannounced switch of language. Validate answers against
the full available lexicon, but draw source puzzles from a suitable pool;
an anagram must have a verified alternative and a letter selection must
permit a word. Do not scan the full dictionary during a player's turn.

### Audio Ball point

Agreed: exactly two players play for a single point in Audio Ball. The first
player to score wins the challenge and takes **5 feathers from the other
player**. This is a transfer, not an additional reward created by the game.
Do not play a full set or match. After confirming that point and settling
the feathers, resume the pending race turn. Start at the existing **Normal**
difficulty, using Audio Ball's normal progression during the point. Randomly
choose the first server once as part of the shared challenge setup.

Planned integration: reuse Audio Ball's existing play, controls, audio and
bot behaviour through a single-point adapter, not a rewritten approximation.
Preserve personal audio preferences; do not import another table's difficulty
or match length. Do not impose a new overall point deadline.

### Axel Pong point

Agreed: exactly two players play for a single point in Axel Pong. The first
player to score wins the challenge and takes **5 feathers from the other
player**. Finish after that point and resume the pending race turn; do not
start a second point, a complete match or a doubles game. Start at the
existing **Normal** difficulty, using Axel Pong's normal progression during
the point. The agreed mode is **Classic**, with the first server chosen
randomly once as part of the shared challenge setup.

Agreed: automatic hitting follows each player's current local Axel Pong
setting. The challenge neither forces it on nor disables it, and players may
use different settings. Reuse the existing setting and behaviour without
overwriting preferences or adding a separate race-table switch.

Planned integration: reuse Axel Pong's existing singles play, controls, audio
and bot behaviour through a single-point adapter. Use the normal starting
ball-speed setting, not a value inherited from an unrelated Pong table.
Preserve local audio preferences and automatic hitting as agreed above.
Do not impose a new overall point deadline.

For both challenges, keep the same race table and participants. Only the two
selected players control the minigame; everyone else remains outside the
duel. The race's hands, positions, modifiers and pending turn survive the
challenge. Keep its result separate from standalone game statistics.
The agreed balance rule limits a transfer to the loser's available feathers
if fewer than 5 remain. Check freezing after settlement, not during an incomplete
point. Connection setup or an aborted attempt must not itself award feathers.

### Challenge implementation batches

Implement in four working batches: simple choices and dice; number, word
and memory tasks; sound and timed tasks; then the two realtime point adapters.
These are development stages,
not separate board-specific challenge pools. A challenge enters the enabled
list only after its rules, interface, bot behaviour and tests are complete.
Unfinished selected challenges remain visible in the plan, not silently
replaced by a random result or removed from the declared scope. Excluded
challenge numbers are not an implementation backlog for this release.

## Interface

Use the shared game layout and existing card-hand and command controls.
Keep the selected physical card stable when drawing, exchanging hands or
receiving an update. Present the track in a separate navigable view rather
than adding thirty fields to the normal Tab order.

Proposed game-field controls:

- Arrows select a card; Enter plays it or opens its target choice. “Roll the
  die” is the last row in the same list, after all physical cards, not a
  separate button in the Tab order. It is not a card and must not enter
  hand-ordering or card-description operations.
- Space rolls the ordinary race die, when the phase allows it; a visible
  list command does the same. Challenges 2 and 4 use Enter as agreed above.
- D describes the selected card and cost.
- C reads the player's position, lap, feathers and active effects.
- S reads the race standings and other players' public status.
- V opens the track with squares, ducks and publicly visible placed cards.
- T reports the turn or current challenge.

Use shared F1, Ctrl+F1, Ctrl+R, history, chat and participant actions. During
a challenge, bind only its required controls and explain them before input.
Game keys must not consume letters, Enter or Space typed in chat. Opening
help, a menu or another ELTEN window must not stop the shared executor;
focus and drafts survive phase changes. State whether a timed challenge
continues while its field is covered, and do not read hidden-field input.

Keep automatic messages brief, especially during challenges. Announce the
new information rather than reading the entire current state after each
input: a newly drawn blackjack card and total, a newly found sound pair,
or an accepted word. Full hands, matched positions and current results
must remain available for inspection. Unchanged refreshes are silent.
State the winner and actual feather transfers at settlement; do not hide
those consequences merely to shorten speech. Describe a self-targeted or
global card without repeating the player's name as its target. A placed
card needs one placement message, not a second generic play announcement.

Card, square and challenge names use only the current interface language,
without English names appended to their translations. Reuse the existing
roll, card-draw, card-play and shuffle sounds for their actual actions;
refreshing or replaying an unchanged view must not play them again. A
pending request may still reject an actual new action, but empty input
frames and ordinary navigation must not repeatedly say “Please wait”.

Questions from a square or card use their own Magical Hit cue, at gain
0.7 before personal volume. Present the question and enable its input two
seconds after announcing the landing or card, through the existing event
queue. Do not stack a second introduction pause or wait for speech to end.
Ordinary encounter challenges retain their separate cue and introduction.

Training Program, Correct1 confirms the local player's correct answer in
Copy the number, Mental arithmetic, Race question, Count the ducks and an
exact Guess the number hit. A completed, accepted Order the sounds solution
uses it for its solver only. Wrong answers, previews, partial arrangements,
other players and observers receive no such cue. Quiz keeps its existing
countdown and revealed-result sounds. Refreshes must not repeat any cue;
all recordings respect game volume, sound preferences and background muting.
SFX_Spell_IceShoot_02 accompanies a duck becoming frozen and each accepted
turn skipped while frozen. Ordinary skipped turns keep their existing
sound. Status requests and unchanged snapshots must not repeat freezing.

Ordinary race movement announces the destination square, not the unchanged
lap after every roll. Announce a lap when movement actually crosses its
boundary. Do not automatically announce “Preparing race”, “Race started”,
“Listen”, a sequence length or “Repeat”. Keep the initial control instructions
and the status available on request. The five memory tones are C, D, E, F and
G; use the same mapping for the played sequence and the player's input echo.

The question-set checklist is an agreed table option, shared by quiz
challenges, question squares and question cards. The lap count is 1–10,
defaulting to 3. All 18 available challenges are enabled by default; the host can
deselect them. Eligible selected challenges have equal chances. At least
one selected challenge must support the full group as well as duels.
The agreed challenge deadlines are fixed, not additional table settings.
No generic deadline may silently impose a total-time limit on Simon.
An ordinary challenge is cancelled without feather transfers after 90 seconds
without a participant's client activity. A responsive ongoing Simon attempt
can therefore continue indefinitely; short connection interruptions do not
cancel it. Once private results are being revealed, each accepted upload page
renews that participant's 90-second progress deadline. Heartbeats alone must
not keep an irrecoverably stalled upload open forever. Native Pong and Audio
Ball retain their own connection recovery while the point is in progress.
Do not add a redundant board selector
while only one board is available. Put any genuinely local audio preferences
under the existing local-settings mechanism, rather than in shared rules.

## Code and synchronization

Follow [Adding a game](ADDING_A_GAME.md), [Architecture](ARCHITECTURE.md)
and [Private answers and saved games](PRIVATE_STATE.md).

| Area | Planned change |
| --- | --- |
| `games/duck_racing.rb` | Base game contract, options, action validation and deterministic replay |
| `games/duck_racing_support/` | Board/card data, effect resolution, challenge definitions and presentation; split by actual responsibilities |
| `games/duck_racing_support/bots.rb`, `numeric_bot.rb`, `challenge_bot.rb` | Bot decisions through the ordinary action path |
| `games/catalog.rb` | Register the game and its short description |
| `lib/game_surfaces/` | Reuse current surfaces; add a small component only if a challenge cannot be represented safely |
| `games/quiz_party.rb`, `lib/game_content.rb` | Inspect existing question/private-input contracts; share narrow helpers if needed, without changing Quiz rules |
| Existing Audio Ball and Axel Pong engines and clients | Add narrowly scoped single-point adapters, preserving standalone play and the existing realtime transport |
| `tools/data/rulebooks/<LANG>/duck_racing.json` | New complete rulebooks in all supported languages |
| Locale catalogues and localized README files | Interface, controls, feature documentation and credits |
| `test/games/duck_racing/` | Rule, replay, interface, challenge and lifecycle regression tests |

Keep game-specific branches out of `GameScreen`, transport and the
application entry point. Challenge presentation and realtime adapters live
in `lib/duck_racing/`; the shared executor still performs durable writes.

LiveSessions remains the source of ordered moves and results. Plan one
ordinary race executor, not a worker per effect or challenge. The Audio Ball
and Axel Pong challenges reuse their existing Communications clients for
realtime play and the shared realtime clock for physics. Do not move their
per-frame activity to LiveSessions or run duplicate physics in the race
executor. Commit the confirmed point and its feather transfer once through
the ordinary race action path, then close the challenge client and continue
the race. Bind channel messages and results to the race, challenge instance
and authorized seats so a delayed point cannot settle another duel.

Resolve dice and
other randomness once using the shared deterministic mechanism; uncertain
writes retry the same result. Replay must not query the network or generate
fresh randomness. Visual/audio movement can run locally without sending a
separate request for every crossed square or tone.

Each pending decision carries match, turn/challenge and controller identity.
Reject duplicate, late and stale-controller actions. Preserve every accepted
transition when presenting several consequences together. Resolve an effect
chain iteratively with explicit continuation state; a detected invalid cycle
needs diagnostics, not silent dropping of effects or an endless retry loop.

Public turns in Dice duel, Blackjack and Risky dice use the ordinary durable
challenge-action path, like the existing sequential challenges. Only the
current participant may act. Replay, bots, turn speech and the T shortcut
must follow that participant and the current decision deadline. Skip finished
participants, settle only after all have finished, and preserve the existing
feather calculations and controller/revision guards.

Simultaneous secret choices use the existing commitment/reveal facilities.
Do not reveal another participant's choice through the normal view or a bot's
decision context. Durable deadlines use the shared server/game clock; local
audio/input intervals use monotonic time. Never compare raw clocks from
different computers.

For a long private input trace, compress the complete canonical reveal once
and persist its exact wire representation before committing. Send bounded
pages through the existing action path; retries must reuse the same bytes.
Keep the complete original trace and commitment validation. Reject invalid
page bounds, overlaps, oversized expansion and mismatched hashes before
changing the game state. Remove the local committed answer and wire cache
only at the worker's confirmed resolution boundary, never while replaying.

The shared foreground can reuse an owned copy of a newer worker-confirmed
snapshot instead of scheduling redundant reads. It must still use the normal
UI replay/presentation path and exact acknowledgement; this is not optimistic
input or permission to skip validation. Metadata changes, recovery and
uncertain writes retain their conservative path. Duck's historical-event
presenter uses a separate bounded replay cache so examining older prefixes
does not repeatedly discard useful work. Preserve every transition, including
multiple sound-memory reveals in one update.

Timed challenges compare locally elapsed performance as described above;
network arrival order is not a substitute for that measurement. The result
acceptance and validation path must preserve challenge-bound start signals
and rejection of late or duplicate submissions in both local and live trials.
Measure actual input, delivery and resolution delay before claiming fairness
on different connections; this is not automatically identical to QC.
Apart from reusing the existing Audio Ball and Axel Pong realtime paths,
do not add Communications just because an activity is timed, nor assume
it provides a globally ordered race. Any other transport extension needs
its own measured justification and agreed ordering rule.

## Bots and table lifecycle

Bots should evaluate race progress, feather reserves, upcoming squares,
targets and card costs. They may not inspect other hands, unrevealed choices
or future random outcomes. Memory and speed challenges need bounded reaction
and error behaviour, not perfect instant solutions. Use the shared bot delay
and executor; declare any challenge-specific behaviour explicitly.

Preserve host transfer, automatic bot replacement after a confirmed departure
and return as observer. An actual departure or replacement of a challenge
participant cancels that challenge without feather transfers, then resumes
the pending race. Cancellation must invalidate outstanding private answers
and realtime results before a new controller acts. A brief connection loss
without a membership change does not cancel a challenge. Keep the ordinary
private-phase safeguards until the cancellation is durably accepted.
A challenge cannot wait forever for a disconnected participant; its agreed
timeout policy must finish it once.

Save at a completed-turn checkpoint initially. Explain why saving is
temporarily unavailable during unresolved effects or private/timed choices.
Use the existing account archive, consuming it after a confirmed successful
restore. Restore hands, traps, modifiers, arrival order and random state,
then allow the next ordinary turn without rerolling anything.

## Design decisions to preserve during verification

1. Confirm exact effects and costs where the source is ambiguous, discarding
   and forced play, and costs when a target cannot pay the entire effect.
   The initial 37 card types are selected above; there is no finite deck to exhaust.
2. The position of zero-feather checks, skipped turns and victory within
   effect chains, and repeated crossings of the start. Landing order is
   settled: square, placed card, encounter, with a moved destination first.
3. Freeze/skip interaction, challenge eligibility and counting the active
   pre-roll turn as the first skip are settled above. Never check halfway
   through a settlement or drop the remaining effects of a played card.
4. Finish crossing, overshooting, backward movement and encounters across
   different laps are settled above.
5. Eligible selected challenges have equal weights. In rock–paper–scissors,
   a sole timely answer wins and takes 3 feathers; two missing answers
   transfer none.
   Guess the number uses the target's digit count and the difference between
   the best distances, capped at 5 feathers per opponent (see challenge 6).
   The four first-answer challenges take 4 feathers per loser immediately.
   Only Order the sounds retains the elapsed-time comparison and 5-feather cap: a slower correct
   result pays the rounded-up seconds difference, while an incorrect or missing
   result pays 5 without becoming eligible to win. No unique correct winner
   means no transfer. Group/tie
   settlement, balance limits, bust penalties, the dice ceiling of 25, speed
   conversion, accuracy conversion, binary stake and the listed time/attempt
   limits are specified above. Do not reopen these as undecided defaults.
6. Question defaults and weighting are settled above. The two word activities
   are currently unavailable; do not load their dictionaries for a race.
   All three quiz paths use the agreed checklist and
   4-feather reward; square and card questions go to all players. Settle the
   acceptance/validation path for locally measured times; arrival order is
   not evidence of local reaction speed.
7. Reconnect, replacement and abandonment policies for single-point realtime
   challenges must not award the same 5-feather transfer twice. Their two-player
   scope, one-point duration, Normal start, random first server and stake are
   settled. Pong uses Classic and each player's local automatic-hit setting.

Prefer observations or primary descriptions of the original. When a rule
cannot be established, return a narrow choice to the maintainer. Do not call
an invented formula faithful reproduction. A field's listed effect alone
does not settle ordering, probability independence or interactions.

## Implementation order and acceptance

1. Resolve blocking core rules and prepare checked board/card/challenge data.
2. Build and locally verify the race, feathers, modifiers, freeze and ending.
3. Add card effects, placed cards, hand changes and chained consequences.
4. Add challenges in the four batches, including private choices, timing and
   the existing realtime clients used by the two single-point challenges.
5. Connect accessible controls, bots, lifecycle and saves, testing them during
   the earlier stages rather than leaving integration until the end.
6. Write rules according to [the editorial guide](RULES_EDITORIAL.md), with
   controls beside actions, natural language and appropriate lists; complete
   all translations and required audio.
7. Complete targeted regression tests and live-account trials before proposing
   a release. Version, changelog, signing, packaging and publication require
   the maintainer's later instruction.

Local tests must cover every square and card, all challenge outcomes, illegal
inputs, zero feathers, empty resources, simultaneous choices, ties, deadlines,
effect chains, start/finish crossings and deterministic full/incremental
replay. Check the starting-feather formula for each allowed lap count and
verify that neither a completed lap nor restoring a save grants it again.
Test uniform draws with replacement, repeated card types with distinct IDs
and type-filtered draws. Initial hands, square rewards and card-effect draws
must stay within Peaceful Pond's 37 selected types: 1–11 and 23–48. Items
12–22 and 49 must not enter through a generic or filtered draw path.
Check freeze thresholds, tied positions, negative
progress, lap boundaries, a far-behind racer, departure and host transfer
during a freeze. Verify that cards survive freezing, existing feathers are
not erased at thaw, and duplicate delivery cannot grant the 5 feathers twice.
Include eight-place capacity tests and conservation checks where an
effect transfers rather than creates resources. Repeated delivery, uncertain
writes and return from a disconnected phase must not duplicate outcomes.
Check three and four arrivals on one square: A–B, B–C and C–D, with no extra
duels against older occupants. Test different winners of preceding duels,
departures and returns to that square, save/restore and host transfer while
preserving arrival order. Group-card selection must not draw a two-player-only
activity for a larger group.

For the selected challenges, cover Enter with active die modifiers, difference
settlement and burned penalties without creating feathers. Repeated rolls in
challenges 2 and 4 must preserve single-use and multi-turn modifiers; returning
to the ordinary race must consume them according to their card rules. Check
random starters and cyclic turn order in Dice duel and Blackjack with two,
three and more players, including bots, a spectator host and a sole unfinished
player. Check each initial Blackjack hand and total in public history once,
including natural 21, followed by individual draws and stands. Drawing below
21 must keep the same participant's turn until the attempt ends.
In Risky dice, verify that repeated rolls retain the same active participant
until saving, reaching or exceeding 25, or timeout. Each own roll must renew
the 30-second decision deadline without imposing a whole-attempt limit.
Verify per-turn deadline renewal, timeout roll/stand/save, rejection of
out-of-turn and duplicate input, skipped completed players and one settlement.
Race rolling must work both from the last row of the card list and with Space,
without treating the command as a physical card or adding a Tab stop. Check
the separate roll/save commands, the tenth accepted guess and rejection of an
eleventh, nearest guesses without an exact answer, ordered ball
inspection and immediate 1–3 selection, including fewer balls remaining.
Check direct number input in sound memory and turn changes after a match.
Verify the agreed group settlement (16/10/8 transfers 6 and 8), tied leaders
with no transfers, available-balance caps and no negative balances. Blackjack
20/24 must transfer 4 and burn 3; risky dice 24/28 must do the same. Test all
players busting, tied valid leaders with another player busting, and a balance
too small for both transfer and penalty, preserving the settlement order.
Check speed-reward boundaries around each tenth and whole second, the 5-feather
cap, absent/incorrect completions, equal best times, no correct completion and
insufficient balances. Missing results must not become fictitious completion
times. Confirm that the cap does not affect score or accuracy settlement, and
distinguish local completion from network arrival.
Verify the full countdown playback in all six speed challenges: reject early
input, begin response timing only after the recording ends and retain the full
answer allowance. Verify the fixed 5-second pause (3 seconds for Count the ducks) regardless of synthesizer
state, and the first native digit/key in the playback-completion frame.
For Count the ducks, the pause and countdown follow the complete quack sequence; F5 must preserve both the
deadline and the original steady pace without another countdown.
Test onset spacing at 400 and 900 ms and confirm that Guess the number, Simon
and score/accuracy challenges keep their existing timing.
For rhythm, test exact playback, wrong tones, missing intervals, 80/160 ms
boundaries and no penalty for the first reaction delay. For targets, test
each distance, timeout, first-answer commitment and normalization from 500
raw points to 100%. Check accuracy conversion at zero and each 10-point
boundary, plus the 90/60, 100/40 and 83/79 examples, without a 3-feather cap.
For Simon, test a sequence longer than 30 sounds, playback longer than five
seconds, every inactivity boundary, a wrong key and autorepeat. The sole
remaining player must keep playing until an error or inactivity ends the
attempt, even after exceeding every opponent's score. Verify 16 against 10
transfers 6 feathers once, not 3, and settlement waits for the last attempt.
No global deadline may end a valid ongoing attempt. Check difference-based
settlement for word lengths and pair counts, including gaps above 3, and
preserve the separate Quiz and realtime stakes. Excluded activities must not appear
in selection or random draws.

Check question selection with one and multiple sets, deselection, empty and
missing resources, language differences, rematches and save/restore. All three
question triggers must draw only from selected sets and grant exactly
4 feathers for each correct answer, once, including after uncertain writes.
Square and card questions must reach all players, including frozen racers,
but must not accept answers from observers.

For Audio Ball and Axel Pong challenges, test Normal starting difficulty,
Pong's Classic mode and both random first-server outcomes without rerolling
after uncertain delivery,
both possible winners, exactly one completed point, one 5-feather transfer,
a loser with fewer feathers, freezing and resumption of the same race turn.
Check delayed or duplicate
point results, failed setup, reconnects, host transfer, player replacement
and cleanup between successive challenges. Do not carry held keys from the
race into a serve or leave old realtime clients running after the duel.
Check Axel Pong with automatic hitting on, off and different for each
participant; entering and leaving the challenge must not change preferences.
Targeted tests of ordinary Audio Ball and Pong must still pass after any
shared extraction needed for the adapters.

Every implemented behaviour that can be tested on a live table must be
tested there, including edge cases, recovery and regressions in affected
existing games. Local tests supplement these trials; they do not replace
them. Maintain a verification matrix in the local diagnostic report linking
each requirement to its local and live checks. Record the accounts, scenario,
observed result and any limitation. A failed, blocked or unperformed live
check remains open, with its reason; do not mark the feature fully verified
on the strength of a model-only test.

Live trials use one, two, three or four real accounts according to the
scenario, with bots where appropriate. Cover human/human, human/bot,
several humans, a spectator host, a complete race and a rematch. Check host
transfer and replacements, leave/rejoin, save/restore, invitations and
different entry paths. Test chat, speech and sounds while the game remains
covered by Messages, help, menus or a leave confirmation; returning must not
repeat events or steal the chat cursor. Exercise every challenge's actual
input control and audio, not just its model result.

In particular, exercise the question-set checklist through the actual table
settings, then trigger a quiz challenge, a question square and a question card
on the same live table. Verify shared questions, participation of all players
for square/card triggers, private answers, early completion and rewards.
Test each agreed challenge shortcut at its real input control,
alongside chat and covered-window behaviour; model-only checks are not enough.
Use three and four live accounts to reproduce the same-square arrival chain
and a group-card challenge separately, checking who actually receives input
controls and pays or receives feathers. Exercise timed and accuracy scoring
at their real controls, including ties and a larger-than-three feather gap.

Play each realtime challenge on live accounts with two humans and with a bot,
including a race host who is not one of the duel participants. Confirm the
actual point, sound, controls, feather settlement and return to the race;
also check ordinary standalone Audio Ball and Axel Pong for regressions.

After a shared change, test its dependent existing games, especially card
hands, Quiz/private answers and background presentation. Do not rerun the
entire suite by default. Keep reports and diagnostic data outside tracked
documentation. Separate handler-driven checks from physical keyboard and
listening trials. Four accounts on one computer do not establish fairness
or responsiveness across different internet connections; speed-sensitive
challenges need that additional trial before claims about network fairness.

## Presentation and manual challenge trials

Movement history uses separate, short sentences for the roll, the named
landing square and each effect, with one entry per line and no empty lines.
Announce the lap only when it changes, not after every ordinary roll.

On entering a text-based challenge, read its question or task once even if
the game refresh keeps the focus in chat. Preserve the draft and focus;
ordinary refreshes and answer submission must not repeat the initial task.
The task remains in the field header for deliberate inspection. Avoid
reading it twice when a newly focused challenge field would normally speak
the same header. Quiz reads the first displayed answer with the question.
List and button challenges also need an audible introduction: the choices
in rock paper scissors, the roll command in dice duel, or the initial hand
in twenty-one must not rely on a focus refresh to be heard. Observers hear
that they are watching rather than being told to submit an answer.

Count the ducks, Repeat the rhythm, Simon and Hit the duck start with their
audio cue; automatic focus must not speak over it. Manual Tab and help
remain available. Preserve the agreed quiet listening/repeating transitions.
Read each newly accepted dice roll, including the final one, once. Saving
does not repeat the roll; its result remains available in the field. Numbered
balls permits arrow inspection while waiting. All turn-based challenges
announce each return of the player's turn. Their turn shortcut reports the
current player rather than just listing all challenge participants.

`tools/duck-racing-lab.rb` is an optional, source-only test tool, not part of
the release allowlist or a production dependency. Load it after Duck Racing
inside every participating application's namespace. For a trial, create a
private Duck Racing table, enable **Challenge lab (test only)** and leave the
desired challenges selected. Start normally; the playing host chooses a
challenge with the arrow keys and Enter. Two-player challenges offer a pair
selection when more than two players are seated. After settlement, the
challenge list returns without an intervening race move.

The tool reuses normal readiness, input, private-answer verification and
feather settlement. It keeps actual feather balances; frozen players can
take part in laboratory trials only. It does not add a second scoring engine
or expose the tool on ordinary tables. The playing host's authority and the
current session/revision are still checked. A normal application reload
removes the tool; any resumed laboratory table requires it to be loaded on
all participating clients again. Source-only loading is not a test-package
build or an installation change.

## Historical limitation: long private challenges

Long private sound challenges remain a responsiveness concern. Earlier live
Simon trials reaching 31 and 35 sounds produced the correct result and
four-feather difference, but took about 235–244 seconds after the last response.
The 11 October follow-up, with compressed trace pages, owned ready snapshots
and a separate presentation cache, completed the same scores and transfer in
42.071 seconds on the host and 41.898 seconds on the guest, measured from the
last participant's final key. All original inputs were verified on both
clients: 77 logical reveal pages still required 685 physical fragments.
These are different real runs with several combined changes, not an isolated
measurement of any one optimization. The remaining wait is still too long;
do not present this path as ready for release or attribute all of it to the
server without separating preparation, scheduling, replay and network time.
Detailed evidence is kept in the ignored diagnostic reports, not in the
player instructions. No Simon length or time cap was introduced. These
measurements describe the legacy full-trace protocol, not the compact flow
below, which supersedes it for newly started races.

## Compact challenge flow (14 October 2026)

New race starts carry `challenge_flow: 2`. Previously accepted histories
without that marker retain their original begin, advance and trace semantics;
do not reinterpret their recorded events using the new protocol.

- Simon, Repeat the rhythm and Hit the duck start individually with Enter or
  Space after practice. One participant can finish before another starts.
  Local game rules calculate the result and submit only a bounded score,
  not a keyboard or playback trace. The race waits for every participant's
  score before settling feathers. This trusts the client; it is not anti-cheat.
- Guess the number starts independently and retains its ten-guess/two-minute
  limits. Its compact private submission contains at most ten guesses, from
  which the shared rules calculate the result; it contains no timing trace.
- Rock paper scissors and Quiz submit just their private choice. These and
  Guess the number keep salted commitments and reveal only after all commits.
  The final commit opens revealing in that same accepted event.
- Copy the number, Mental arithmetic, Race question and Count the ducks keep
  the first-correct-answer rule and use one future response boundary on the
  existing synchronized clock. Receiving a view later must not restart the
  countdown or allow a response before that boundary.
- Dice duel, Twenty-one, Risky dice and Numbered balls retain their public
  turns. Sound memory retains manual readiness and public reveals. Sound
  order retains the common countdown and shared swaps, needed for partial
  scoring. Native Audio Ball and Axel Pong retain readiness and their existing
  connection/point protocol. No local score replaces a real native point.

The last readiness acknowledgement starts a shared challenge directly, with
no separate begin write. Waiting text identifies the missing participants.
Finished participants neither repeat submission nor keep emitting activity
records. The existing 30-second activity pulse and 90-second inactivity rule
remain for unfinished non-realtime participants, including practice; completed
scores do not time out while others continue. There is no new polling loop,
worker or timer framework.

A final local score is persisted in the existing hidden-submission vault
before sending. An uncertain write recovers the same session/challenge/seat
result, rather than starting a new attempt. Only accepted results or a recorded
closure authorize cleanup. Existing participant-change cancellation, epoch,
stale-action, archive and native realtime guards remain in force.
Historical answers keep their original session scope after archive import.
An independent challenge opened by a new race move uses that move's physical
session, not the archived race-start session; chained challenges retain it.

Compact audio results are constant-sized in the number of sounds or keystrokes.
They still use the normal action codec, so one logical result can occupy more
than one physical LiveSessions record. Targeted tests and live handler-driven
checks are recorded in ignored diagnostics; they do not establish timing
fairness across separate computers or physical-keyboard/audio behaviour.

## Known limitation: history capacity

Very large or long races can fill the LiveSessions history. Power Games
requests 4096 records per table, with the actual allowance determined by
the server. Existing cleanup removes earlier games when a new game starts;
it does not shorten the history of a game that is still running. Chat and
table-management records share that allowance with game actions.

An eight-player, ten-lap local model trial finished after 4556 game actions,
before counting those other records. This establishes neither that the same
race fits on the server nor a guarantee that every eight-player, ten-lap
race can finish. Simon deliberately has no gameplay length cap. New compact
attempts no longer upload a growing key trace, but ongoing activity pulses
and other table records still consume history. Legacy full-trace attempts
also retain their old cost. An arbitrarily long race therefore cannot be
guaranteed to fit in any fixed history capacity. Faster local replay does not
enlarge that capacity.

The maintainer chose to document this limitation for now, without rebuilding
the storage protocol, changing limits, trimming an active game or imposing
a new Simon cap. Any future continuation or checkpoint design requires a
separate review of authenticated history, participant changes, private
answers and recovery; a successful model-only test must not hide this limit.
