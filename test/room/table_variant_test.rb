require_relative "../support/table_watch_runtime"
registry = EltenGameRoom::GAME_REGISTRY
empty = %w[balut mexican_train war scientific_war battleship ludo reversi yahtzee biblios chess four_in_a_row tic_tac_toe]
registry.ids.each do |id|
  game = registry.build(id)
  # Reader defaults may retain historical modes that new tables no longer offer.
  options = game.table_creation_options.merge("__secret" => "secret", "thinking_time" => 123, "bot_delay" => 5, "full_p2p" => true)
  payload = GameRoomTableVariant.payload(game, JSON.generate(options))
  message = GameRoomTableVariant.text(game, payload)
  assert(message.encoding == Encoding::UTF_8 && message.valid_encoding?, "invalid variant encoding: #{id}")
  assert((payload["options"].keys & %w[__secret thinking_time bot_delay full_p2p]).empty?, "private/unwanted option: #{id}")
  if empty.include?(id)
    assert(message.empty?, "unwanted description: #{id}: #{message}")
  else
    assert(!message.empty?, "missing agreed variant: #{id}")
  end
  assert(GameRoomTableVariant.text(game, nil) == "" && GameRoomTableVariant.text(game, {"format" => 1, "options" => {}}) == "", "absent options became defaults")
  puts "#{id}: #{message}"
end
read = ->(id, options) { GameRoomTableVariant.text(registry.build(id), GameRoomTableVariant.payload(registry.build(id), options)) }
assert(read.call('billiards', {'discipline'=>'nine'}) == 'Pool: 9-ball', 'Billiards discipline summary missing')
assert(read.call('french_tarot', {'round_limit'=>1, 'score_limit'=>0}) == '1 deal', 'Tarot deal limit missing')
assert(read.call('french_tarot', {'round_limit'=>0, 'score_limit'=>200}) == '200 points', 'Tarot score limit missing')
assert(read.call('backgammon', {'variant'=>'hyper', 'score_limit'=>7, 'doubling_cube'=>true}) == 'Hypergammon, 7 points, Doubling cube', 'Backgammon target or cube missing')
assert(read.call('billiards', {'discipline'=>'friendly', 'layout'=>'diamond'}).include?('Social billiards'), 'Social billiards summary missing')
%w[billiards cash_auction].each do |id|
  assert(read.call(id, {}).empty?, "#{id}: absent notification options became defaults")
  options = registry.build(id).table_creation_options.merge('__private'=>'secret', 'bot_delay'=>5)
  keys = GameRoomTableVariant.payload(registry.build(id), options).fetch('options').keys
  expected = id == 'billiards' ? %w[discipline layout] : %w[content_language_id content_set_id]
  assert(keys.sort == expected.sort, "#{id}: unexpected notification metadata")
end
assert(read.call('kosciane', {'columns'=>1})=='1 score column', 'Dice General singular column summary missing')
assert(read.call('kosciane', {'columns'=>6})=='6 score columns', 'Dice General selected column count missing')
[nil,0,7,'3',true].each { |value| assert(read.call('kosciane', {'columns'=>value}).empty?, 'Malformed column count printed') }
assert(read.call("spades", {"quicksand" => true, "team_size" => 2, "score_limit" => 500}) == "Quicksand, 500 points", "Spades missing score or including team")
assert(read.call("audio_ball", {"difficulty" => 3, "sets_to_win" => 3}) == "Normal, first to 3 sets", "Audio Ball lost difficulty or winning-set count")
assert(read.call("categories", {"answer_language" => "pl", "target_score" => 100}) == "Polish, 100 points", "Categories missing language or score")
assert(read.call("uno", {"score_limit" => 500}) == "500 points", "UNO points missing or missing options guessed")
[nil, 0, -1, '100', true].each do |value|
  assert(read.call('uno', {'score_limit' => value}).empty?, 'Invalid points printed')
end
assert(!read.call("poker", registry.build("poker").default_options).match?(/limit|chips|blind/i), "Poker extras")
assert(read.call("uno", {"deck" => "flip", "interceptions" => true}).include?("with interceptions"), "UNO interception missing")
assert(read.call("uno", {}).empty?, "UNO absent data guessed")
assert(read.call("domino", {"tile_set" => "2d6", "teams" => true}) == "2 × Double 6, Team play", "Domino description too detailed")
assert(read.call("axel_pong", {"team_size" => 2, "arcade" => true, "difficulty" => 3}) == "Doubles, Arcade, Hard", "Pong variant incomplete")
assert(read.call("krowa", {"variant" => "daily", "length" => 4}) == read.call("krowa", {"variant" => "daily"}), "Daily leaked meaningless length")
assert(read.call('bouillabaisse', {'all_or_nothing' => true}) == 'All or nothing', 'Bouillabaisse enabled variant missing')
assert(read.call('bouillabaisse', {'all_or_nothing' => false}) == 'Without all or nothing', 'Bouillabaisse disabled variant missing')
assert(read.call('bouillabaisse', {}).empty?, 'Missing Bouillabaisse settings became defaults')
scopa_options = registry.build('scopa').default_options
assert(read.call('scopa', scopa_options) == 'Classic, 11 points', 'Classic Scopa or its target missing')
8.times do |mask|
  options = scopa_options.merge('score_limit' => 21)
  names = []
  %w[escoba scopone muerto].each_with_index do |key, index|
    options[key] = (mask & (1 << index)) != 0
    names << %w[Escoba Scopone Muerto][index] if options[key]
  end
  names << 'Classic' if names.empty?
  assert(read.call('scopa', options) == [*names, '21 points'].join(', '), "Scopa variants #{mask} or target missing")
end
assert(read.call('scopa', {'score_limit' => 21}) == '21 points', 'Missing Scopa flags became Classic')
assert(read.call('scopa', {'escoba' => false}).empty?, 'Partial Scopa flags became a known variant')
assert(read.call('scopa', {'escoba' => true}) == 'Escoba', 'A known partial variant was hidden')
assert(!read.call('scopa', scopa_options).include?('win by two'), 'Scopa short description contains extra settings')
%w[bouillabaisse scopa].each do |id|
  game = registry.build(id)
  source = game.default_options.merge('bot_delay' => 3, 'thinking_time' => 123, '__private' => 'secret')
  keys = GameRoomTableVariant.payload(game, source).fetch('options').keys
  expected_keys = id == 'bouillabaisse' ? %w[all_or_nothing] : %w[escoba scopone muerto score_limit]
  assert(keys.sort == expected_keys.sort, "#{id}: unexpected short-description metadata")
end
[nil, 1, [], "broken", {"format" => 9}, {"format" => 1, "options" => []}].each do |payload|
  assert(GameRoomTableVariant.text(registry.build("uno"), payload).empty?, "malformed metadata not ignored")
end
puts "PASS recipient-side short variants: all games, exact exclusions, missing/malformed options, no internal payload"
