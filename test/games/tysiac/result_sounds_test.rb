require_relative '../../support/tysiac_redeal_fixture'
require_relative '../../../lib/game_sounds'

game = GameRoomGames::Tysiac.new
cue = ->(action, state, history, value = '') do
  game.event_sound_cues(event: {'action'=>action, 'value'=>value}, before_replay: nil,
    after_replay: GameRoomGames::Replay.new(state: state), history: history, viewer: 'Bob', random_variant: nil)
end
[[{}, %w[Alice Bob Carol]], [{'variant'=>'teams'}, %w[Alice Bob Carol David]]].each do |options, players|
  [149, 150, 151].each do |points|
    state = game.send(:initial_state, players, game.normalize_options(options))
    state.merge!(round: 1, phase: :playing, taker: 'Alice', contract: 150)
    state[:round_points]['Alice'] = options.empty? ? points : points - 50
    state[:round_points]['Carol'] = 50 unless options.empty?
    history = []
    game.send(:complete_round, state, 21, history, surrendered: false)
    sound = points >= 150 ? 'tysiac_contract_made' : 'tysiac_contract_failed'
    assert(cue.call('play', state, history) == [sound], 'Contract cue ignored raw/team points or exact threshold')
    assert(cue.call('play', state, []) == nil, 'Repeated/rejected event replayed a result cue')
    assert(cue.call('play', state.merge(private_error: 'unverified'), history) == nil, 'Failed private audit played a contract result')
  end
end

f = TysiacRedealFixture.new
f.deal('00000000000000000000000000000001')
f.bid(100); f.bid('pass'); f.bid('pass')
before = f.replay
assert(f.move({'kind'=>'command','action'=>'surrender'}) == :ok, 'Surrender fixture was rejected')
after, event = f.replay, f.events.last
sounds = GameRoomSounds.event_cue(game: f.game, event: event, before_replay: before, after_replay: after,
  repository: f.repository, viewer: 'Bob', include_result: false)
assert(Array(sounds) == ['tysiac_surrender'], "Surrender cue was missing or mixed with contract failure: #{sounds.inspect}")
assert(cue.call('surrender', after.state, []) == nil, 'Rejected surrender played a cue')
history = [GameRoomGames::HistoryEntry.new(kind: :play)]
assert(cue.call('play', {trump: 'H'}, history, 'marriage|QH') == %w[play draw2 1000_mariage], 'Contract cues replaced trump/marriage audio')
%w[tysiac_surrender tysiac_contract_made tysiac_contract_failed].each do |name|
  assert(GameRoomSounds::ASSET_NAMES.include?(name), 'New Tysiac sound is not registered')
end
puts 'PASS Tysiac contract/surrender sounds: actual settlement, threshold, teams, private rejection, deduplication and old trump/marriage cues'
