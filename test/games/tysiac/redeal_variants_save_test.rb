require_relative '../../support/tysiac_redeal_fixture'
require_relative '../../../lib/saved_games'

[[{'variant'=>'two_players'}, %w[Alice Bob], 9, 9],
 [{'variant'=>'two_players','talon_size'=>2}, %w[Alice Bob], 10, 10],
 [{'variant'=>'four_players'}, %w[Alice Bob Carol David], 0, 7],
 [{'variant'=>'teams'}, %w[Alice Bob Carol David], 5, 5]].each do |options, players, offset, length|
  seed = TysiacRedealFixture.seed_for { |deck| (%w[9H 9D 9C 9S] - deck.slice(offset, length)).empty? }
  f = TysiacRedealFixture.new(options, players: players)
  f.deal(seed)
  assert(f.state[:current_player] == 'Bob', 'Wrong opening bidder')
  assert(f.request('four_nines') == :ok, "Four-nines redeal failed in #{options}")
  original = f.replay
  storage = Object.new
  data = {}
  storage.define_singleton_method(:read_json) { |_, default:| data }
  storage.define_singleton_method(:update_json) { |_, default:, &operation| operation.call(data) }
  saves = SavedGames.new(storage, owner: 'Alice')
  row = saves.put(game: f.game, table: {'owner'=>'Alice','name'=>'Redeal save'},
    snapshot: Struct.new(:session,:events).new(f.session.merge('__players'=>players), f.events), repository: f.repository, now: 1_800_000_000)
  restored = saves.restored_data(row, game: f.game, table_id: 200, now: 1_800_010_000)
  repository = SavedGames::ReplayRepository.new
  session = f.session.merge('__players'=>restored[:players])
  replay = f.game.replay(session, restored[:events], repository)
  assert(replay.state == original.state && replay.state[:phase] == :redeal, 'Saved cancelled deal changed on restoration')
  action = f.game.automatic_action(replay, players.first, context: f.context)
  status, plan = f.game.action_for(action, replay, players.first, context: f.context)
  assert(status == :ok, 'Cannot deal again after restoring a cancelled deal')
  events = restored[:events].dup
  plan.events.each { |command| events << {'id'=>events.length+1,'actor'=>players.first,'action'=>command.action,'value'=>command.value} }
  next_replay = f.game.replay(session, events, repository)
  assert(next_replay.state[:round] == 1 && next_replay.state[:dealer_index] == 0 && next_replay.accepted_events.size == events.size,
    'Restored redeal changed the dealer/round or failed validation')
end
puts 'PASS Tysiac redeals in two-player/two-card-talon/resting-dealer/teams, actual save/restore and resumed same-dealer deal'
