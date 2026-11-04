require_relative '../../support/new_games_fixture'

game = GameRoomGames::Monopoly.new
state = game.send(:initial_state, %w[Alice Bob], game.default_options)
state[:cash]['Alice'] = 10_000
state[:board].select { |square| square[:price] }.each { |square| state[:owners][square[:index]] = 'Alice' }
state[:jail]['Alice'] = state[:jail_cards]['Alice'] = 1
replay = GameRoomGames::Replay.new(board:state[:board], players:state[:players], current_player:'Alice',
  state:state, accepted_events:[], history:[])
actions = game.legal_actions(replay, 'Alice', include_trade_offers:false)
assert(actions.any? { |action| action['action'] == 'build' } && actions.any? { |action| action['action'] == 'roll' }, 'Validation fixture lacks management and dice actions')
game.define_singleton_method(:trade_actions) { |*_arguments| raise 'Ordinary validation needlessly enumerated all trade offers' }
actions.each do |selection|
  status, plan = game.action_for(selection, replay, 'Alice', context:context_for)
  assert(status == :ok && plan.events.size == 1, "Management/dice validation changed: #{selection.inspect}")
end

# User-created exchanges retain their direct validation, not a narrowed list
# of automatically generated offers (including multi-property/cash packets).
state[:houses].clear
state[:owners][6] = state[:owners][8] = 'Bob'
status, plan = game.action_for({'action'=>'trade_offer', 'target'=>1,
  'give_properties'=>[1, 3], 'receive_properties'=>[6, 8], 'give_cash'=>20, 'receive_cash'=>0},
  replay, 'Alice', context:context_for)
assert(status == :ok && plan.events.first.action == 'trade_offer', 'Direct multi-property offer validation changed')
puts 'PASS Monopoly validation work: dice/property/jail commands do not enumerate trade candidates; direct multi-property trades retained'
