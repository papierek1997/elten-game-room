require_relative "../../support/makao_positions"

game = GameRoomGames::Makao.new
bot = "bot:1:1"
players = ["Alice", bot]
repository = NewGames116Repository.new(players)

# Makao and catching are deliberately legal outside the ordinary turn.  The
# shared screen uses this opt-in while a local computer is waiting or thinking.
assert(game.actions_during_bot_turn?, "a computer turn still blocks Makao shortcuts")
state = playing_makao_state(
  game, players, { "profile" => "simple" },
  current: bot,
  hands: { "Alice" => ["9S"], bot => %w[6C 7D] },
  top: "9H"
)
status, = game.action_for({ "kind" => "command", "action" => "makao" }, makao_replay(state), "Alice")
assert(status == :ok, "Makao cannot be declared during a computer turn")
state[:makao_windows][bot] = true
state[:hands][bot] = ["7D"]
status, = game.action_for({ "kind" => "command", "action" => "catch" }, makao_replay(state), "Alice")
assert(status == :ok, "a missed Makao cannot be caught during a computer turn")

# A custom-profile bot must receive the same joker-as-jack choices as a human.
state = playing_makao_state(
  game, players,
  { "profile" => "custom", "jokers" => true, "jack_requests_rank" => true },
  current: bot,
  hands: { "Alice" => ["8S"], bot => ["X0"] },
  top: "7H"
)
jack_choices = game.legal_actions(makao_replay(state), bot).filter_map do |action|
  next if action["action"] != "play" || JSON.parse(action["cards"]) != ["X0"]
  action["choice"] if action["choice"].to_s.start_with?("J")
end
expected_jack_choices = GameRoomGames::Makao::SUITS.flat_map do |suit|
  GameRoomGames::Makao::REQUEST_RANKS.map { |rank| "J#{suit}:#{rank}" }
end
assert(jack_choices.sort == expected_jack_choices.sort, "the bot cannot use a joker as a requesting jack")

# A legal packet is represented for every strategically distinct ending card,
# while its legal opening card remains first.
state = playing_makao_state(
  game, players, { "profile" => "simple" },
  current: bot,
  hands: { "Alice" => ["6S"], bot => %w[7H 7C 7D 9C] },
  top: "9H"
)
packets = game.legal_actions(makao_replay(state), bot).filter_map do |action|
  cards = JSON.parse(action["cards"].to_s) rescue []
  cards if action["action"] == "play" && cards.length == 3
end
assert(packets.include?(%w[7H 7C 7D]), "the bot lost the packet ending in diamonds")
assert(packets.include?(%w[7H 7D 7C]), "the bot lost the packet ending in clubs")
assert(game.send(:packet_orders, %w[X0 X0]).include?(%w[X0 X0]), "equal card identifiers collapse inside a packet")

# Catching is a free action and must precede even a very attractive packet.
state[:makao_windows]["Alice"] = true
state[:hands]["Alice"] = ["6S"]
replay = makao_replay(state)
best = game.legal_actions(replay, bot).max_by { |action| game.bot_action_score(replay, bot, action) }
assert(best["action"] == "catch", "the bot preferred a card packet and missed a free Makao catch")
history = []
event = { "id" => 1, "actor" => bot, "action" => "catch", "value" => "Alice" }
assert(game.send(:apply_catch, state, event, bot, repository, history), "the selected catch was rejected")
assert(state[:current_player] == bot, "catching Makao consumed the bot's ordinary turn")

fresh = game.send(:initial_state, players, game.default_options)
assert(game.send(:table_text, fresh) == "No card has been dealt yet.", "C announces an empty declared suit before the deal")

puts "Makao bot-turn, joker, packet, catch-priority and pre-deal regressions passed"

# A real foreground match with the joker profile reached J + joker packets.
# An empty choice is intentional for an ordinary jack without rank requests;
# it is not itself a joker identity. Generating Z/F1 must never raise here.
[nil, '', ':', ':5', 'A', 'XXX', 'JH:K'].each do |choice|
  assert(!game.send(:joker_choice?, choice), "invalid joker choice accepted: #{choice.inspect}")
end
%w[2C TH AD JH:5].each do |choice|
  assert(game.send(:joker_choice?, choice), "valid joker identity rejected: #{choice}")
end
GameRoomGames::Makao::RANKS.each do |rank|
  state = playing_makao_state(game, players, {'profile'=>'joker'}, current:'Alice',
    hands:{'Alice'=>["#{rank}S", 'X1', '6C'], bot=>['4D']},top:'TS')
  replay = makao_replay(state)
  before = Marshal.dump(state)
  actions = game.legal_actions(replay,'Alice')
  assert(!actions.empty?, "joker profile has no actions for #{rank}")
  game.playable_card_navigation(replay,'Alice')
  assert(Marshal.dump(state) == before, "joker navigation mutated the hand for #{rank}")
  actions.select { |a| a['action'] == 'play' }.each do |action|
    status, = game.action_for(action,replay,'Alice',context:context_for)
    assert(status == :ok, "enumerated joker packet rejected: #{action.inspect}, #{status}")
  end
end
puts 'PASS Makao: empty/nil joker choice, ordinary jack + joker, all ranks and navigation without mutation'
