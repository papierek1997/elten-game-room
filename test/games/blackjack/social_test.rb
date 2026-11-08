require_relative "../../../games/blackjack"
require_relative "../../support/private_simulation"
game = GameRoomGames::Blackjack.new
env = GameRoomTest::PrivateSimulation.new_game(game:game,players:%w[Alice Bob Carol],options:{'variant'=>'social','round_limit'=>3,'starting_chips'=>100,'stake'=>10},seed:53)
dealers = []
400.times do
  break if env.finished?
  state = env.replay.state
  raise 'House hand in social game' unless state[:dealer].empty?
  if state[:phase] == :awaiting_deal
    dealers << state[:dealing_player]
    raise 'Social dealer is automatic for a human' if game.automatic_action(env.replay,env.active_actor,context:env.context)
  end
  actions = env.legal_actions
  action = actions.find { |a| %w[check call stand deal].include?(a['action']) } || actions.first
  raise "Missing social action #{state[:phase]}" unless action && env.step(action)==:ok
  state = env.replay.state
  pending = state[:auction] && %i[betting awaiting_deal playing dealer].include?(state[:phase]) ? state[:auction][:contributions].values.sum : 0
  raise 'Social chips not conserved' unless state[:chips].values.sum + pending == 600
end
raise 'Social game did not finish' unless env.finished?
raise 'Dealing seat did not rotate' unless dealers == %w[Alice Bob Carol]
raise 'Private cards or events changed on replay' unless env.replay == game.replay(env.session,env.events,env.repository)
puts 'Social blackjack: three rotating human dealers, no house hand, ante/raises, chip conservation and replay passed'

repo = Struct.new(:players) do
  def players_for(_session); players; end
  def actor_of(event,_session); event['actor']; end
  def event_id(event); event['id']; end
end.new(%w[Alice Bob Carol])
session={'options'=>JSON.generate(game.new_game_options('variant'=>'social','round_limit'=>1,'starting_chips'=>100,'stake'=>10))}
events=[{'id'=>1,'actor'=>'Alice','action'=>'ante','value'=>''},
  {'id'=>2,'actor'=>'Alice','action'=>'bet','value'=>'fold|0'},
  {'id'=>3,'actor'=>'Bob','action'=>'bet','value'=>'fold|0'}]
replay=game.replay(session,events,repo)
raise 'Uncontested social pot required a deal' unless replay.finished? && replay.state[:round]==1 && replay.state[:hands].empty?
raise 'Uncontested social pot wrong' unless replay.state[:chips]=={'Alice'=>180,'Bob'=>180,'Carol'=>240}

state=game.replay(session,events.first(1),repo).state
state[:dealing_player]='Alice'
state[:eliminated]=['Bob']
game.send(:prepare_auction,state)
raise 'Eliminated dealing seat not skipped' unless state[:dealing_player]=='Carol'
game.send(:prepare_auction,state)
raise 'Dealing rotation repeated a surviving seat' unless state[:dealing_player]=='Alice'
puts 'Social blackjack: uncontested pot without dealing and rotation after elimination passed'
