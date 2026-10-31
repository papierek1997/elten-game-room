require_relative '../../support/card_hand_cursor'
require_relative '../../support/tysiac_four_player'

def find_key(game, replay, viewer, shift: false)
  game.game_shortcuts(replay, viewer).find { |key| key.key == 'r' && key.modifiers.to_a == (shift ? [:shift] : []) }
end

fixture = TwoPlayerTysiacFixture.new
game = fixture.game
assert(find_key(game, fixture.replay, 'Alice').message == 'There is no contract yet.', 'R invents a contract before bidding')
fixture.deal
fixture.move({'kind'=>'command','action'=>'bid','bid'=>100})
assert(find_key(game, fixture.replay, 'Observer').message == 'Bob: 100', 'R does not read the standing bid to an observer')
fixture.move({'kind'=>'command','action'=>'bid','bid'=>'pass'})
fixture.choose
replay = fixture.replay
before = Marshal.dump(replay.state)
assert(find_key(game, replay, 'Alice').message == 'Bob: 100', 'R includes the auction instead of just the contract')
assert(Marshal.dump(replay.state) == before, 'Reading R changed the game')
surrender = find_key(game, replay, 'Bob', shift: true)
assert(surrender && surrender.kind == :action && surrender.action_kind == 'command' && surrender.action_name == 'surrender', 'Shift+R is not the existing surrender command')
assert(find_key(game, replay, 'Alice', shift: true).nil? && find_key(game, replay, 'Observer', shift: true).nil?, 'Another player can surrender the bidder’s deal')
selection = {'kind'=>surrender.action_kind, 'action'=>surrender.action_name}.merge(surrender.payload)
status, plan = game.action_for(selection, replay, 'Bob')
assert(status == :ok && plan.events.map(&:action) == ['surrender'], 'Shift+R bypasses or fails normal validation')
fixture.move(selection)
assert(fixture.replay.state[:phase] == :round_complete && fixture.replay.state[:scores] == {'Alice'=>60,'Bob'=>0}, 'Shortcut surrender changed scoring')
assert(find_key(game, fixture.replay, 'Bob', shift: true).nil?, 'Surrender remains available after ending the deal')

fixture = TwoPlayerTysiacFixture.new
fixture.auction
fixture.choose
fixture.discard
assert(find_key(fixture.game, fixture.replay, 'Bob', shift: true).nil?, 'Surrender is available after the first discard')
status, = fixture.game.action_for(selection, fixture.replay, 'Bob')
assert(status == :cannot_surrender, 'A stale Shift+R shortcut can surrender too late')

%w[four_players teams].each do |variant|
  f = FourPlayerTysiacFixture.new(variant: variant)
  f.next_deal
  f.finish_auction
  bidder = f.replay.state[:taker]
  assert(find_key(f.game, f.replay, 'Observer').message == "#{bidder}: 100", "#{variant}: R reads the wrong bidder")
  assert(find_key(f.game, f.replay, bidder, shift: true), "#{variant}: bidder cannot surrender")
  f.players.reject { |p| p == bidder }.each { |p| assert(find_key(f.game, f.replay, p, shift: true).nil?, "#{variant}: non-bidder surrender") }
end

# A received heart must join the displayed hearts, not the end of the hand.
# Preserve received order in replay and honour an explicit manual sort choice.
game = GameRoomGames::Tysiac.new
state = game.send(:initial_state, %w[Alice Bob Carol], game.default_options)
state.update(round:1, phase: :playing, current_player:'Alice', taker:'Bob', contract:100)
state[:hands]['Alice'] = %w[9H KH AH JS]
view = -> { GameRoomGames::Replay.new(players:state[:players], state:state, current_player:'Alice', accepted_events:[], history:[]) }
surface = GameSurfaces.build(game.surface_spec(view.call, 'Alice'))
ids = -> { surface.instance_variable_get(:@cards).fetch('hand').map(&:id) }
assert(ids.call == %w[9H KH AH JS], 'Initial suit order changed')
state[:hands]['Alice'] << 'QH'
surface.update_spec(game.surface_spec(view.call, 'Alice'))
assert(ids.call == %w[9H QH KH AH JS], 'New heart appended instead of joining its suit')
assert(surface.fields.first.index == 1 && surface.take_cursor_announcement(0) == game.send(:card_label, 'QH'), 'Last received card/cue lost')
restored = GameSurfaces.build(game.surface_spec(view.call, 'Alice'), state:surface.state)
assert(restored.fields.first.options == surface.fields.first.options, 'Sorted received cards changed after rebuilding')
surface.handle_command('sort_cards', 'mode'=>'colour', 'toggle'=>true)
assert(ids.call == %w[9H QH KH AH JS], 'First manual suit sort unexpectedly reversed the default')
surface.handle_command('sort_cards', 'mode'=>'colour', 'toggle'=>true)
assert(ids.call == %w[JS AH KH QH 9H], 'Second manual suit sort no longer reverses order')
surface.handle_command('sort_cards', 'mode'=>'none')
state[:hands]['Alice'] << 'JH'
surface.update_spec(game.surface_spec(view.call, 'Alice'))
assert(ids.call == state[:hands]['Alice'], 'Default suit order overrode explicit acquisition order')
assert(state[:hands]['Alice'] == %w[9H KH AH JS QH JH], 'View sorting changed the replay hand')
puts 'PASS Thousand: concise R, validated Shift+R, two/four/team players, received-card suit order and manual override'
