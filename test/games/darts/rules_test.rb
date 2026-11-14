# encoding: UTF-8
def _(text); text; end
def n_(singular, plural, count); count == 1 ? singular : plural; end

require_relative '../../../games/darts'
require_relative '../../support/sequence_random'

def assert(value, message)
  raise message unless value
end

class DartsRepository
  def players_for(session); session.fetch('__players'); end
  def actor_of(event, _session); event.fetch('actor'); end
  def event_id(event); event.fetch('__id'); end
end

def darts_session(game, players: %w[Alice Bob], options: {})
  {'__players' => players, '__table_owner' => 'Alice', '__insertion_user' => 'Alice',
    'options' => JSON.generate(game.default_options.merge(options))}
end

def darts_event(action, value, actor:, id:, author: actor)
  {'__id' => id, '__insertion_user' => author, 'actor' => actor, 'action' => action, 'value' => value}
end

def throw_value(index, x, y, time = 1_000, automatic = false)
  [index, x, y, time, automatic ? 'a' : 'm'].join(':')
end

game = GameRoomGames::Darts.new
repo = DartsRepository.new

assert(game.id == 'darts' && game.minimum_players == 1 && game.maximum_players == 8, 'Darts identity or roster limits changed')
assert(game.supports_bots? && game.background_client? && game.audio_game?, 'Darts lacks its declared runtime capabilities')
assert(game.default_options == {'mode'=>'game', 'difficulty'=>'normal', 'rounds'=>3, 'progressive'=>false,
  'time_limit'=>10, 'timeout_result'=>'auto', 'mouse_input'=>false, 'bot_delay'=>1}, 'Darts defaults changed')
assert(game.options_error(game.default_options.merge('mode'=>'training'), player_count: 2), 'multiplayer training was accepted')
assert(game.options_error(game.default_options.merge('mode'=>'training'), player_count: 1) == nil, 'solo training was rejected')
assert(game.notification_variant(game.default_options.merge('rounds'=>1)).include?('1 round'),
  'one-round table notification uses a plural English label')
assert(game.notification_variant(game.default_options.merge('rounds'=>3)).include?('3 rounds'),
  'multi-round table notification uses a singular English label')
assert(game.training_position_text(1_000, 0) == 'right' &&
  !game.training_position_text(1_000, 0).include?('point'),
  'training cursor speech still exposes a score instead of only its sector')

session = darts_session(game, options: {'rounds'=>1})
start = darts_event('darts_start', 'a' * 32, actor: 'Alice', id: 1)
opening = game.replay(session, [], repo)
assert(opening.state[:phase] == :opening && opening.current_player == nil, 'game pretended to start without a durable seed')
started = game.replay(session, [start], repo)
assert(started.state[:phase] == :playing && started.current_player == 'Alice' && started.state[:seed] == 'a' * 32,
  'durable seed did not start the match')
assert(game.throw_prompt_text(started) == 'Round 1 throw 1', 'Darts does not expose the concise round and throw prompt')
assert(game.surface_spec(started, 'Alice').header == 'Round 1 throw 1', 'active Darts playfield lost its repeatable stage label')

events = [start]
3.times do |index|
  events << darts_event('darts_throw', throw_value(index, 0, 0), actor: 'Alice', id: events.length + 1)
end
after_alice = game.replay(session, events, repo)
assert(after_alice.current_player == 'Bob' && after_alice.state.values_at(:round, :dart, :throw_index) == [1, 1, 3],
  'a normal turn did not contain exactly three darts')
3.times do |offset|
  events << darts_event('darts_throw', throw_value(3 + offset, 0, 0), actor: 'Bob', id: events.length + 1)
end
tied = game.replay(session, events, repo)
assert(tied.state[:phase] == :tiebreak && tied.current_player == 'Alice' && tied.state[:scores] == {'Alice'=>300, 'Bob'=>300},
  'equal match totals did not enter a sudden-death tie-break')

events << darts_event('darts_throw', throw_value(6, 800, 0), actor: 'Alice', id: events.length + 1)
one_tiebreak_dart = game.replay(session, events, repo)
assert(one_tiebreak_dart.current_player == 'Bob' && one_tiebreak_dart.state[:tiebreak_index] == 1,
  'first tied player received more than one tie-break dart')
assert(one_tiebreak_dart.state[:scores] == {'Alice'=>300, 'Bob'=>300}, 'tie-break dart polluted the ranked match total')
events << darts_event('darts_throw', throw_value(7, 1_000, 1_000), actor: 'Bob', id: events.length + 1)
finished = game.replay(session, events, repo)
assert(finished.winner == 'Alice' && finished.finished?, 'one-dart sudden death did not resolve the tie')
assert(game.surface_spec(finished, 'Alice') == nil, 'finished Darts retained an actionless playfield button')
assert(finished.state[:throws]['Alice'].last[:tiebreak] && finished.state[:throws]['Bob'].last[:tiebreak],
  'tie-break darts cannot be separated from ordinary ranking throws')

malformed = [
  darts_event('darts_throw', throw_value(0, 0, 0), actor: 'Bob', id: 2),
  darts_event('darts_throw', throw_value(1, 1_001, 0), actor: 'Alice', id: 3),
  darts_event('darts_throw', '0:0:0:1000:x', actor: 'Alice', id: 4)
]
assert(game.replay(session, [start] + malformed, repo).accepted_events == [start], 'wrong actor or malformed throw changed replay')

context = GameRoomGames::ActionContext.new(table_owner: 'Alice', local_data: {'darts_throw'=>throw_value(0, 100, -100)})
status, plan = game.action_for({'kind'=>'darts', 'action'=>'throw', 'value'=>throw_value(0, 100, -100)}, started, 'Alice', context: context)
assert(status == :ok && plan.events.first.value == throw_value(0, 100, -100), 'confirmed local throw did not produce one durable event')
assert(game.action_for({'kind'=>'darts', 'action'=>'throw', 'value'=>throw_value(0, 101, -100)}, started, 'Alice', context: context) == [:invalid, nil],
  'a different coordinate bypassed local confirmation')

bot_session = darts_session(game, players: ['bot:1:1'], options: {'rounds'=>1})
bot_started = game.replay(bot_session, [start.merge('actor'=>'bot:1:1')], repo)
random = GameRoomRandom::SequenceSource.new([500, 500, 500])
bot_context = GameRoomGames::ActionContext.new(table_owner: 'Alice', random_source: random)
actions = game.legal_actions(bot_started, 'bot:1:1', context: bot_context)
status, plan = game.action_for(actions.first, bot_started, 'bot:1:1', context: bot_context)
assert(status == :ok && plan.events.first.value.bytesize <= 64, 'bot did not use the ordinary bounded action path')

assert(GameRoomDarts::Scoring.points(0, 0) == 100, 'centre does not score 100')
radial_scores = [100, 300, 600, 900, 1_000].map { |radius| GameRoomDarts::Scoring.points(radius, 0) }
assert(radial_scores.each_cons(2).all? { |closer, farther| closer > farther },
  'radial score does not fall continuously with distance')
assert(radial_scores.uniq.length == radial_scores.length && radial_scores.last == 1,
  'inside-board scoring still collapses hits into broad 25-point zones')
assert((0..1_000).step(10).map { |radius| GameRoomDarts::Scoring.points(radius, 0) }.uniq.length > 50,
  'Darts exposes too few distinct distance scores')
assert(GameRoomDarts::Scoring.points(1_000, 1_000).zero?, 'outside square corner did not miss the circular board')
one_point_replay = game.replay(session, [start,
  darts_event('darts_throw', throw_value(0, 1_000, 0), actor: 'Alice', id: 2)], repo)
assert(one_point_replay.history.last.text.include?('1 point.'), 'a one-point throw uses a plural English announcement')
assert(game.result_sound_cue(before_replay: nil, after_replay: finished, viewer: 'Alice', default_cue: 'win_party') == nil,
  'the shared presenter can reveal the result before the delayed impact')

source = File.read(File.expand_path('../../../lib/darts/client.rb', __dir__), encoding: 'UTF-8')
assert(!source.match?(/speech_stop|NVDA|screenreader.*(?:off|disable)/i), 'ordinary Darts aiming changes global screen-reader speech')
assert(source.include?('announce_training_position'), 'training has no explicit spoken-position path')

puts 'PASS Darts rules: ordinary triples, one-dart tie-breaks, validation, bots, scoring and speech boundary'
