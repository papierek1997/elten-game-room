# encoding: UTF-8
def _(text); text; end
def n_(singular, plural, count); count == 1 ? singular : plural; end

require_relative '../../../games/darts'
require_relative '../../../lib/darts/rankings/result'

def assert(value, message)
  raise message unless value
end

class DartsRankingRepository
  def players_for(session); session.fetch('__players'); end
  def actor_of(event, _session); event.fetch('actor'); end
  def event_id(event); event.fetch('__id'); end
end

def ranking_throw(index, round, x, y, time, id)
  {'__id'=>id, 'created_at'=>1_800_000_000 + id, '__insertion_user'=>'Alice', 'actor'=>'Alice',
    'action'=>'darts_throw', 'value'=>[index, x, y, time, 'm'].join(':')}
end

game = GameRoomGames::Darts.new
options = game.default_options.merge('rounds'=>3)
session = {'__players'=>['Alice'], '__table_owner'=>'Alice', '__insertion_user'=>'Alice',
  '__statistics'=>{'id'=>'ranked-match-1'}, 'options'=>JSON.generate(options)}
events = [{'__id'=>1, 'created_at'=>1_800_000_001, '__insertion_user'=>'Alice', 'actor'=>'Alice',
  'action'=>'darts_start', 'value'=>'a' * 32}]
3.times { |index| events << ranking_throw(index, 1, 0, 0, (index + 1) * 1000, index + 2) }
3.times { |offset| events << ranking_throw(offset + 3, 2, 1000, 0, 1000, offset + 5) }
3.times { |offset| events << ranking_throw(offset + 6, 3, 1000, 0, 1000, offset + 8) }
replay = game.replay(session, events, DartsRankingRepository.new)
assert(replay.finished?, 'ranking fixture did not finish')

row = GameRoomDartsRankings::Result.from_replay(session: session, replay: replay, viewer: 'alice')
assert(row && row['difficulty'] == 'normal' && row['rounds'] == 3 && row['throw_count'] == 9,
  'finished human game did not produce the expected ranking scope')
assert(row.values_at('total_score', 'total_time_ms', 'best_round_score', 'best_round_time_ms') == [306, 12_000, 300, 6000],
  "ranking projection changed score or time totals: #{row.inspect}")
assert(row['day_key'] == GameRoomDartsRankings::Result.day(row['played_at']),
  'ranking projection did not retain the future daily-challenge day key')

progressive_session = session.merge('options'=>JSON.generate(options.merge('progressive'=>true)))
progressive = game.replay(progressive_session, events, DartsRankingRepository.new)
assert(GameRoomDartsRankings::Result.from_replay(session: progressive_session, replay: progressive, viewer: 'Alice')['difficulty'] == 'progressive',
  'progressive Darts was mixed with a fixed difficulty')
legendary_session = session.merge('options'=>JSON.generate(options.merge('difficulty'=>'legendary')))
legendary = game.replay(legendary_session, events, DartsRankingRepository.new)
legendary_row = GameRoomDartsRankings::Result.from_replay(session: legendary_session, replay: legendary, viewer: 'Alice')
assert(legendary_row['difficulty'] == 'legendary',
  'legendary Darts was rejected or mixed with another ranking scope')
training_session = session.merge('options'=>JSON.generate(options.merge('mode'=>'training')))
training = game.replay(training_session, events, DartsRankingRepository.new)
assert(GameRoomDartsRankings::Result.from_replay(session: training_session, replay: training, viewer: 'Alice') == nil,
  'sound training produced a public ranking result')
bot_session = session.merge('__players'=>['bot:1:1'])
bot_events = events.map { |event| event.merge('actor'=>'bot:1:1') }
bot_replay = game.replay(bot_session, bot_events, DartsRankingRepository.new)
assert(GameRoomDartsRankings::Result.from_replay(session: bot_session, replay: bot_replay, viewer: 'bot:1:1') == nil,
  'a computer player produced a public ranking result')

puts 'PASS Darts ranking result: fixed/progressive scope, triples, averages, day key and non-ranked training/bots'

inherited = replay.dup
inherited.accepted_events = replay.accepted_events.map.with_index do |event, index|
  index == 1 ? event.merge('actor'=>'bot:1:1') : event
end
assert(GameRoomDartsRankings::Result.from_replay(session:session, replay:inherited, viewer:'Alice').nil?,
  'A returning human published an inherited bot throw as their own record')
inherited.accepted_events += [events.last.merge('__id'=>99)]
assert(GameRoomDartsRankings::Result.from_replay(session:session, replay:inherited, viewer:'Alice').nil?,
  'An extra tie-break throw concealed an inherited bot throw')

[
  row.merge('result_key'=>Integer('1' * 64)),
  row.merge('total_score'=>901),
  row.merge('best_round_score'=>100),
  row.merge('total_time_ms'=>9 * 600_000 + 1),
  row.merge('rounds'=>1, 'throw_count'=>3, 'total_score'=>30_000)
].each do |invalid|
  begin
    GameRoomDartsRankings::Result.parse(invalid)
    raise "An impossible Darts ranking result was accepted: #{invalid.inspect}"
  rescue GameRoomDartsRankings::InvalidResult
  end
end
