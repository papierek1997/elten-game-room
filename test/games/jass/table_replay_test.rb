require_relative "../../support/cat_head_tail"
require_relative "../../../games/jass_support/jass_table"
game = GameRoomGames::JassTable.new
players = %w[A B C D]
repo = CatHeadTailRepository.new(players)
session = {}
events = [cht_event(1, "A", "deal", "1|0|00000000000000000000000000000000")]
replay = game.replay(session, events, repo)
raise unless replay.accepted_events.size == 1
events << cht_event(2, replay.current_player, "choose_trump", "hearts")
36.times do
  replay = game.replay(session, events, repo)
  actor = replay.current_player
  choice = game.legal_actions(replay, actor).first
  raise "No playable card" unless choice
  status, plan = game.action_for(choice, replay, actor)
  raise unless status == :ok
  command = plan.events.first
  events << cht_event(events.size + 1, actor, command.action, command.value)
end
replay = game.replay(session, events, repo)
raise unless replay.accepted_events == events && replay.state[:scores].values.sum == 157
raise unless replay.state[:phase] == :round_complete
puts "PASS Jass: complete public-fixture replay"
