require_relative '../../support/cat_head_tail'
require_relative '../../../games/kosciane'
require_relative '../../../games/balut'
require_relative '../../../lib/game_sounds'

players = %w[Alice Bob Carol]
[GameRoomGames::Balut.new, GameRoomGames::Kosciane.new].each do |game|
  options = game.id == 'kosciane' ? game.default_options.merge('columns' => 1) : game.default_options
  session = {'options' => JSON.generate(options)}
  repository = CatHeadTailRepository.new(players)
  events = []
  previous = nil
  200.times do
    replay = game.replay(session, events, repository)
    assert(replay.accepted_events == events, 'Shared-win fixture must use an entirely accepted match')
    break if replay.finished?
    previous = replay
    actor = replay.current_player
    if game.id == 'balut'
      category = game.available_scoring_categories(replay.state, actor).first
      dice = actor == 'Carol' ? [1] * 5 : [6] * 5
      1.times { events << cht_event(events.length + 1, actor, 'roll', dice.join(',')) }
    else
      category = replay.state[:match_model].sheet(actor).find { |_key, row| row.empty? }.first
      dice = if category.is_a?(Integer)
        [category] * 5
      elsif [:two_pairs, :full_house].include?(category)
        [5, 5, 6, 6, 6]
      elsif [:small_straight, :large_straight].include?(category)
        [2, 3, 4, 5, 6]
      else
        [6] * 5
      end
      (actor == 'Carol' ? 3 : 1).times { events << cht_event(events.length + 1, actor, 'roll', dice.join(',')) }
      category = "cross:#{category}" if actor == 'Carol'
    end
    events << cht_event(events.length + 1, actor, 'score', category)
  end
  finished = game.replay(session, events, repository)
  assert(finished.finished? && finished.accepted_events == events, 'Shared-win match did not finish')
  assert(game.score_sheet_winners(finished) == %w[Alice Bob], 'Lower scorer incorrectly shares the win')
  assert(game.result_text(finished) == 'Winners: Alice, Bob', 'Partial tie hides its actual winners')
  %w[Alice Bob].each { |viewer| assert(GameRoomSounds.result_cue(game, previous, finished, viewer) == 'win_party', 'Joint winner lost feedback') }
  assert(GameRoomSounds.result_cue(game, previous, finished, 'Carol') == 'lose_party', 'Lower scorer hears draw feedback')
  assert(GameRoomSounds.result_cue(game, previous, finished, 'Observer').nil?, 'Observer receives a participant result')
  assert(GameRoomSounds.result_cue(game, nil, finished, 'Alice').nil?, 'Cold reconstruction repeats result audio')
end
puts 'PASS accepted three-player partial ties, winning names, rewards, both winners/loser/spectator cues and silent reconstruction'
