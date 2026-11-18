# Cheat

`games/cheat.rb` owns one reducer for ordinary tables, bots and archived games.
`games/cheat/presentation.rb` declares the packet hand, local confirmation and
phase-specific commands; `games/cheat/bot.rb` supplies bounded own-hand candidates
and an observation-only strategy. The existing executor performs every write.

The five profiles are ascending (default), descending, same/neighbouring rank,
fixed-rank Bluff and single-card suit play. Ordinary profiles allow 2–8 players;
Bluff allows 3–6. LiveSessions has eight total places, including observers and
bots, so the traditional 2–10 range cannot be offered by this host.

One public-seed shuffle deals all 52 unique cards. Accepted action ordinals bind
each packet and reaction to its current boundary. Compact values stay within
the native 64-character limit. Reactions proceed in seat order without a timer;
only explicit acceptance or a challenge advances them. Card counts are public
statuses, not point scores. The single winner is exported without inventing
remaining places or small points.

Face-up suit openings are public immediately. For face-down plays, a challenge
reveals only the latest packet. Older face-down pile cards remain concealed in
the UI after collection or Bluff removal. Normal
protocol 8 still carries a public deal seed: this is interface concealment,
not cryptographic secrecy against a modified client. Cheat does not opt into
server-private tournament hands: native transfers disclose cards. Ordinary
archives retain reactions and passes; local unsent packet selection is UI state.

## Turns and interaction

Ascending and descending play advance the declared rank after every accepted
packet, including a challenged packet. Collection does not reset the cycle or
change the next seat. Neighbouring-rank play also keeps the previous claim as
its reference. Bluff resets passes when the pile closes: a successful challenger
opens next, while a failed challenge gives the opening to the packet's author.
If everyone passes, the last author opens again. In suit play the pile recipient
opens face up after a challenge.

Enter prepares the current card together with the selected packet; Shift+Enter
toggles a selection. The declaration, where selectable, and final confirmation
remain local until submission. Escape cancels without losing the prepared cards.
K challenges and Space declines a challenge only during the player's ordered
reaction. X passes until the pile closes only in Bluff. H reads the own hand;
S reads public card counts; C reads the public pile/declaration state. F1 and
Ctrl+F1 use the shared shortcut help and complete multilingual rulebook.

A concealed final play cannot win until reactions settle. A face-up final suit
opening wins immediately. Challenge presentation sequences the request, reveal,
outcome and collection sounds before speaking the resolution; refreshing a
snapshot must not play the same accepted event twice.

## Rule sources and adaptation

- [Bicycle: I Doubt It](https://bicyclecards.com/how-to-play/i-doubt-it/): the
  52-card ascending game, one-to-four-card plays, challenges and the last play.
- [Pagat: Cheat](https://www.pagat.com/beating/cheat.html): ordinary next-seat
  continuation after a challenge and descending/neighbouring alternatives.
- [Pagat: I Doubt It and Bluff](https://www.pagat.com/beating/doubt.html): fixed
  pile rank, passes, concealed removal and the next opener after a challenge.

Checked 18 November 2026. The commissioned Power Games profile also specifies
king–ace adjacency, whole-deck Bluff dealing, true public packet counts,
ordered untimed reactions and a challengeable final play in every concealed
profile. Suit play uses a face-up opener, checks suit alone and gives the pile
recipient the next opening. These are explicit adaptation choices, not claims
of one universal traditional rule. There are no jokers, extra decks or Force.

## Targeted verification

Select `test/games/cheat` with `test/run.rb --list` before running it. Its cases
cover the production reducer, native packet/declaration/confirmation controls,
bounded secret-independent bots and explicit human matches through ordinary
executors on the native local broker. Add shared card, modal, sound, archive,
catalog and content checks using [the test map](TESTING.md).
Local broker, captured native speech, live accounts, physical keyboard input
and audible playback remain distinct forms of evidence.
