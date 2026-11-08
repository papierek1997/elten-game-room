require_relative "../../support/dice_games"
require_relative "../../../lib/liars_dice_secrets"
include DiceGamesSupport
secrets = GameRoomLiarsDiceSecrets
vault = HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new)
random = GameRoomRandom::SeededSource.new(814)
context = GameRoomGames::ActionContext.new(session_id: 91, hidden_submissions: vault, random_source: random)
state = {round: 1, session_id: 91, players: %w[Alice Bob], commits: {}, reveals: {}, counts: {'Alice'=>5}, seed: nil}
value = secrets.envelope(state, 'Alice', context, create: true)
reference = random.dup
check(value && secrets.envelope(state, 'Alice', context, create: true) == value, "Commit retry replaced the private secret")
check(random.roll(count:3,sides:1000).values == reference.roll(count:3,sides:1000).values, "Commit retry consumes random state")
state[:commits]['Alice'] = value.commitment
check(secrets.dice(state, 'Alice', context).nil?, "Dice visible before server draw")
state[:seed] = 'a'*32
check(secrets.dice(state, 'Alice', context).size == 5, "Own dice unavailable")
check(secrets.dice(state, 'Bob', context).nil?, "Other player's dice disclosed")
encoded = secrets.encode(value.payload['seed'] + value.nonce)
check(encoded.bytesize == 44 && secrets.decode(encoded) == value.payload['seed'] + value.nonce, "Private reveal exceeds stack dialect")
check(secrets.decode(encoded + 'a').nil? && secrets.decode('!'+encoded[1..]).nil?, "Invalid secret encoding accepted")
context.session_id = 92
check(secrets.dice(state, 'Alice', context).nil?, "Secret leaked between sessions")
puts "Liar's dice secrets: persisted commitment retry, RNG state, private views, session isolation and bounded wire encoding passed"
