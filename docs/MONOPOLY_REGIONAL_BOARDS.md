# Regional Monopoly board data

`content/monopoly_regional_data.rb` contains separate profiles for eighteen
QC editions: all 840 spaces, original street, station and utility names,
colors, starting cash, currency and the bank's building supply.
`content/monopoly_boards.rb` assembles boards from this data. Poland remains
Game Room's own 40-space edition, not a board obtained from QC.

`games/monopoly.rb` uses the board parameters when starting a match,
paying the Go salary, charging rent, enforcing building limits and sending players to jail.
Fixed fees and bonuses are proportional to the Go salary; prices,
rents, auctions and property valuations respect the currency scale. Space numbers,
distances and dice rolls are not scaled.

## Observations from the QC client

Source: QuentinC Gameroom 2026.8.15, our own trial games with one bot.
The complete layouts of all editions below, cash before a move,
and the available bank building supply were read. Base prices and rents were read from 34
property cards on the Twelve Nations board. In addition, the first card
of every other edition was read (the second in the American edition), and for Europe also the last
street, a station and a utility. Values for the other regional cards are derived by
applying QC's shared table to the observed currency multiplier, not by separately
reading every card on every board.

| Edition | Spaces | Starting cash | Amount scale | Houses/hotels |
|---|---:|---:|---:|---:|
| Atlantic City | 40 | 1500 $ | 1 | 32/12 |
| London | 40 | 1500 £ | 1 | 32/12 |
| Europe | 40 | 15000000 € | 10000 | 32/12 |
| Rome | 40 | 1500 euro | 1 | 32/12 |
| Latin America | 60 | 9750 ¤ | 3 | 48/18 |
| Barcelona | 40 | 15000000 € | 10000 | 32/12 |
| Turkey | 40 | 1500 TL | 1 | 32/12 |
| Slovakia | 40 | 1500 € | 1 | 32/12 |
| Serbia | 40 | 15000000 RSD | 10000 | 32/12 |
| Czech Republic | 40 | 37500 CZK | 25 | 32/12 |
| Russia | 40 | 1500 RUB | 1 | 32/12 |
| Ukraine | 40 | 1500 UAH | 1 | 32/12 |
| Romania | 60 | 35000000 RON | 10000 | 48/18 |
| Balkans | 60 | 7000 ¤ | 2 | 48/18 |
| Indonesia | 60 | 35000000 Rupiah | 10000 | 48/18 |
| Southeast Asia | 60 | 7000 ¤ | 2 | 48/18 |
| India | 40 | 1500 ₹ | 1 | 32/12 |
| Twelve Nations | 60 | 7000 ¤ | 2 | 48/18 |

The large board has 34 streets in 12 groups, 6 stations and 4 utilities.
Station rents in base units: 25, 50, 100, 200, 400, 600.
Utility multipliers for the dice total: 4, 10, 25, 50; these are also
subject to currency conversion.

Indonesia has jail on space 51, not 11. Its Go to Jail space
is at position 41. Latin America sends players from space 51 to 11. The other large
boards send them from 41 to 11. Numbering in this document starts at 1;
game-state indices start at 0.

## Still adaptations, not confirmed QC data

Do not describe these boards as complete one-to-one copies of QC.
The public board-format description at https://qcsalon.net/en/faq separates the currency
multiplier, capital, salary and bank supplies; salary itself cannot be inferred
with certainty from property prices.

- The Go salary was observed for Europe (2000000) and Twelve Nations
  (500). The other profiles assume 200 times the scale for 40 spaces, or 250
  times the scale for 60 spaces. `salary_observed: false` means no confirmation
  from QC gameplay, not a verified regional value.
- The first eight colors retain the previous house costs of
  50/50/100/100/150/150/200/200 times the scale. QC samples confirm six
  of these groups. The additional white, brown and purple groups use 250, 275
  and 400 times the scale based on individual observed streets. Uniform
  costs across each color have not been separately verified for every street.
  The unobserved cost for the gray group is now derived from half the price of its cheapest
  street (350 times the scale), with equal building costs across the color. This is
  the rationale for an adaptation, not an additional QC observation.
- Fixed fees and bonuses are tied to each board's salary: income tax
  is one salary, luxury tax half, and jail and lucky snake eyes a quarter.
  Monetary card amounts preserve their proportions relative to the classic salary of 200.
  Arithmetic is integer-based, rounded to the nearest unit,
  with halves rounded up. For Twelve Nations, this gives taxes of 500/250
  and jail/bonus amounts of 125. For India, the amounts remain 200/100 and 50, preserving
  the observed tax of 200. We do not multiply the amounts by the currency scale again.
- Repairs in the first eight groups retain the base rates times the currency scale.
  Additional buildings costing more than the classic 200 units have proportionally
  higher repair fees. A house costing 800 on the Twelve Nations board (the 400 tier)
  pays twice the rate. Property prices, rents and observed building-cost samples
  remain unchanged.
- Game Room's card count, card types and jackpot variant are retained. Card
  destinations are selected from the board layout: the most expensive street, Go, the last street
  of the middle color group, the first street after jail and the first station. On a
  40-space board, this preserves the existing destinations; on a large board it also covers
  the additional colors, and in Indonesia the street after the jail on space 51.
- Bots' cash reserves account for the local salary and actual rents.
  Purchase and trade valuations are still based on actual property prices.
- Poland has no confirmed equivalent in the QC list.

These are explicitly stated limits on compatibility with the reference platform. Do not
hide them at release. Full compatibility requires further readings of
salaries, building costs, fees and decks.

The data contract and its use are checked by `test/games/monopoly/regional_test.rb`.
This is not independent confirmation of all QC amounts.
