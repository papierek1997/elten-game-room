require_relative '../../support/french_tarot'

def play_tarot_variant(players, bid, options = {}, seed: 2)
  env = GameRoomTest::PrivateSimulation.new_game(game: GameRoomGames::FrenchTarotTable.new,
    players: %w[Alice Bob Carol Dan Ed Fran].first(players), seed: seed,
    options: {'round_limit' => 1, 'tarot_player_counts' => true}.merge(options))
  seen = []
  700.times do
    break if env.finished?
    state = env.replay.state
    phase = state[:phase]
    seen << phase
    if phase == :tarot_call
      shortcuts = env.game.custom_game_shortcuts(env.replay, env.active_actor)
      calls = shortcuts.select { |entry| entry.action_name == "tarot_call" }
      raise 'Partner call must use Shift+B' unless calls.size == 1 &&
        calls.first.key == "b" && calls.first.modifiers == [:shift]
    end
    choices = env.legal_actions
    move = if phase == :bidding
      name = state[:bid_count].zero? ? bid : 'pass'
      choices.find { |entry| entry['choice'] == name }
    else
      handful = choices.find { |entry| entry['action'] == 'tarot_handful' }
      if handful
        surface = env.game.surface_spec(env.replay, env.active_actor)
        command = surface.zones.find { |zone| zone.id == 'hand' }.commands.first
        raise 'Missing handful command in hand' unless command&.id == 'tarot_handful_0'
        {'kind' => 'command', 'action' => command.id}.merge(command.payload)
      else
        choices.first
      end
    end
    raise "no move for #{players}: #{phase}" unless move
    raise "move refused: #{phase}" unless env.step(move) == :ok
  end
  state = env.replay.state
  raise "did not finish: #{players} #{bid} #{state[:phase]}" unless env.finished?
  raise 'non-zero score total' unless state[:scores].values.sum.zero?
  raise 'incorrect hand length' unless state[:tarot_tricks].size == {3=>24,4=>18,5=>15,6=>12}.fetch(players)
  [state, seen]
end

[3, 5, 6].each do |players|
  state, phases = play_tarot_variant(players, players == 5 ? 'pousse' : 'garde_sans', {'tarot_push' => true})
  raise 'wrong call count' unless state[:called_cards].size == [players - 4, 0].max
  raise 'missing call phase' if players >= 5 && !phases.include?(:tarot_call)
end
state, phases = play_tarot_variant(6, 'garde', {'tarot_partners' => false})
raise 'calling was not disabled' if phases.include?(:tarot_call)
state, = play_tarot_variant(4, 'pass', {'tarot_misere' => true})
raise 'misère not played' unless state[:tarot_misere] && state[:taker].nil?
found = (1..20).any? do |seed|
  state, = play_tarot_variant(6, 'garde', {'tarot_handful' => true, 'tarot_partners' => false}, seed: seed)
  state[:tarot_handful]
end
raise 'handful not accepted in any seeded round' unless found
puts 'PASS French Tarot production replay: 3/5/6 seats, calls, Push, Misère and handful'
