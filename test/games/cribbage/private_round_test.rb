require_relative "../../support/private_card_games"
require_relative "../../../games/cribbage_support/cribbage_table"

game = GameRoomGames::CribbageTable.new
h, runners = PrivateCardGamesTest.create(game, users: %w[Alice Bob])
begin
  PrivateCardGamesTest.assert_private(h)
  count_stages = []
  underclaim = nil
  checked_transfer = false
  40.times do
    replay = h.replay(h.users.first)
    break if replay.state[:phase] == :round_complete
    if %i[private_draw private_show].include?(replay.state[:phase])
      actor = h.users.find do |viewer|
        mine = h.replay(viewer)
        mine.state[:phase] == replay.state[:phase] && game.automatic_action(mine, viewer)
      end
      assert(actor, "Missing automatic actor in #{replay.state[:phase]}")
      h.as(actor) { step(h, runners.fetch(actor), actor) }
      next
    end
    actor = replay.current_player
    assert(actor, "Missing actor in #{replay.state[:phase]}")
    mine = h.replay(actor)
    actions = game.legal_actions(mine, actor)
    action = actions.max_by { |candidate| game.bot_action_score(mine, actor, candidate) }
    assert(action, "Missing action for #{actor}: #{h.users.map { |viewer| current = h.replay(viewer); [viewer, current.state[:phase], current.current_player, current.state[:sequence], current.state[:starter]] }.inspect}")
    if mine.state[:phase] == :manual_count
      count_stages << actor
      prompt = game.shortcut_feature_data(:table_cards, mine, actor).fetch(:message)
      assert(prompt.split(", ").size == 4, "Expected four counting cards without the starter")
      keys = game.game_shortcuts(mine, actor).to_h { |shortcut| [shortcut.key, shortcut] }
      assert(keys.fetch("d").message.include?("Karta startowa"), "Missing starter shortcut")
      assert(keys.fetch("v").message.include?("liczy crib"), "Missing crib dealer shortcut")
      wrong = action.merge("points" => action.fetch("points") + 1)
      assert(game.action_for(wrong, mine, actor).first == :ok, "Overcount rejected")
      assert(game.surface_spec(mine, actor).zones.first.cards.size == 5, "Missing cards")
      if action.fetch("points").positive? && !underclaim
        underclaim = [actor, mine.state[:scores].dup]
        action = wrong
      end
    end
    PrivateCardGamesTest.submit(h, runners, actor, action)
    if underclaim && !checked_transfer
      _, before = underclaim
      opponent = (h.users - [actor]).first
      after = h.replay(actor).state[:scores]
      assert(after.fetch(actor) - before.fetch(actor) == action.fetch("points") - 1, "Wrong credited score")
      assert(after.fetch(opponent) - before.fetch(opponent) == 1, "Missed point was not transferred")
      checked_transfer = true
    end
  end
  assert(count_stages.size == 3 && count_stages[0] != count_stages[1] && count_stages[1] == count_stages[2], 'Wrong counting order')
  scores = h.users.map do |viewer|
    replay = h.replay(viewer)
    assert(replay.state[:phase] == :round_complete, "Unexpected final phase #{replay.state[:phase]}, crib #{replay.state[:crib]}, public #{replay.state[:private_public]}, last #{replay.accepted_events.last&.fetch("action")}")
    assert(replay.state[:played].values.all? { |cards| cards.size == 4 }, "Incomplete pegging")
    replay.state[:scores]
  end
  assert(scores.uniq.one? && scores.first.values.sum.positive?, "Wrong final score")
  puts "PASS Cribbage private discard, pegging and crib count"
ensure
  runners.each_value(&:close)
end
