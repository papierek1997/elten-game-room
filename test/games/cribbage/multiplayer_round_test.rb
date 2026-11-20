require_relative '../../support/private_card_games'
require_relative '../../../games/cribbage_support/cribbage_table'

game = GameRoomGames::CribbageTable.new
roster = %w[Alice Bob Charlie Dana Erin Frank]
assert(game.validation_error({'team_size'=>2}, player_count: 3), 'Odd roster accepted for pairs')
assert(game.validation_error({'team_size'=>3}, player_count: 4), 'Four players accepted for triples')

[[3, 0], [4, 0], [5, 0], [6, 0], [4, 2], [6, 2], [6, 3]].each do |count, team_size|
  users = roster.first(count)
  options = game.default_options.merge('team_size'=>team_size)
  if team_size.positive?
    seats = users.each_index.map { |index| index / team_size }
    options = game.with_team_assignment(options, players: users, seats: seats)
  end
  h, runners = PrivateCardGamesTest.create(game, users: users, options: options)
  begin
    PrivateCardGamesTest.assert_private(h)
    initial = h.replay(users.first).state
    order = initial[:seats].rotate(initial[:dealer] + 1)
    dealer = order.last
    hand_size = count == 6 ? 5 : 4
    expected_discards = order.to_h { |seat| [seat, count >= 5 && seat == dealer ? 0 : 1] }
    assert(initial[:hands].transform_values(&:size) == expected_discards.transform_values { |n| n + hand_size },
      "Wrong initial deal for #{count}/#{team_size}")
    if team_size.positive?
      units = order.map { |seat| initial[:unit_for].fetch(seat) }
      assert(units.uniq.size == count / team_size && units.each_cons(2).none? { |a, b| a == b },
        "Teams must alternate seats for #{count}/#{team_size}")
    end

    names_counting = []
    100.times do
      replay = h.replay(users.first)
      phase = replay.state[:phase]
      break if phase == :round_complete
      if [:private_draw, :private_show].include?(phase)
        assert(replay.state[:crib_extra].nil?, 'The extra crib card leaked during pegging') if
          replay.state[:private_pending_draw]&.fetch(:purpose) == 'cribbage_starter'
        PrivateCardGamesTest.tick(h, runners)
        next
      end
      actor = replay.current_player
      assert(actor, "Missing actor at #{count}/#{team_size}: #{phase}")
      mine = h.replay(actor)
      action = game.legal_actions(mine, actor).max_by { |move| game.bot_action_score(mine, actor, move) }
      assert(action, "No legal action at #{count}/#{team_size}: #{phase}")
      if phase == :playing
        assert(mine.state[:crib_extra].nil?, 'The extra crib card leaked during pegging')
      elsif phase == :manual_count
        names_counting << actor
        assert(game.surface_spec(mine, actor).zones.first.cards.size == hand_size + 1, 'Wrong counting cards')
      end
      PrivateCardGamesTest.submit(h, runners, actor, action)
    end
    assert(names_counting == order + [dealer], "Wrong counting order at #{count}/#{team_size}")
    scores = users.map do |user|
      state = h.replay(user).state
      assert(state[:phase] == :round_complete, "Round did not finish at #{count}/#{team_size}")
      assert(state[:played].values.all? { |cards| cards.size == hand_size }, 'Incomplete pegging')
      assert(state[:crib].transform_values(&:size) == expected_discards, 'Wrong discard sizes')
      assert(!state[:crib_extra].nil? == (count == 3), 'Wrong extra crib card')
      round_cues = h.replay(user).history.select { |entry| entry.field == :cribbage_count_start }
      assert(round_cues.size == 1 && round_cues.first.kind == :count, 'Counting must open with one cue')
      state[:scores]
    end
    assert(scores.uniq.one? && scores.first.size == (team_size.zero? ? count : count / team_size),
      'Different clients must see the same player or team scores')
    puts "PASS private Cribbage: #{count} players, team size #{team_size}"
  ensure
    runners.each_value(&:close)
  end
end
