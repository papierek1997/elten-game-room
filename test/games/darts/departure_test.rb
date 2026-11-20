require_relative '../../support/session_runner'
require_relative '../../../games/darts'

def inspect_replay(h, reader)
  snapshot = h.repositories.fetch(reader).snapshot_for(h.session)
  replay = h.game.replay(snapshot.session, snapshot.events, h.repositories.fetch(reader))
  {owner: snapshot.session['__table_owner'], players: replay.players, phase: replay.state[:phase],
   current: replay.current_player, throw_index: replay.state[:throw_index], scores: replay.state[:scores],
   events: snapshot.events.map { |e| e.slice('__id', 'actor', '__insertion_user', '__authority_user', 'action', 'value') },
   accepted: replay.accepted_events.map { |e| e['__id'] }}
end

def acknowledge_and_step(h, runner, reader, ticks, count: 1)
  count.times do
    ticks[0] += 2
    h.as(reader) do
      snapshot = h.repositories.fetch(reader).snapshot_for(h.session)
      replay = h.game.replay(snapshot.session, snapshot.events, h.repositories.fetch(reader))
      runner.publish_view(session: snapshot.session, replay: replay, busy: false, context: runner.send(:context))
    end
    step(h, runner, reader)
  end
end

def scenario(departed:, throws:, start: true, transfer_only: false)
  game = GameRoomGames::Darts.new
  h = NativeRoomHarness.new(game: game, users: %w[Alice Bob], options: game.default_options.merge('bot_delay'=>0))
  h.start
  runners = h.users.to_h { |reader| [reader, runner_for(h, reader)] }
  ticks = [0.0]
  runners.each_value do |runner|
    runner.instance_variable_get(:@context_template).random_source = GameRoomRandom::SeededSource.new(137)
    runner.instance_variable_get(:@turn).instance_variable_set(:@clock, -> { ticks[0] })
  end
  acknowledge_and_step(h, runners['Alice'], 'Alice', ticks, count: 2) if start
  throws.times do
    replay = h.replay('Alice')
    actor = replay.current_player
    value = "#{replay.state[:throw_index]}:0:0:500:m"
    context = GameRoomGames::ActionContext.new(random_source: GameRoomRandom::SeededSource.new(137),
      local_data: {'darts_throw'=>value}, table_owner: 'Alice')
    h.submit(actor, {'kind'=>'darts', 'action'=>'throw', 'value'=>value}, context: context)
  end
  before = inspect_replay(h, 'Alice')
  reader = departed == 'Alice' ? 'Bob' : 'Alice'
  h.as(departed) do
    if transfer_only
      h.transports.fetch(departed).transfer_room_owner(h.table, reader)
    else
      lobby = LobbyRepository.new(ProgramDouble.new(h.broker.endpoint(departed)), transport: h.transports.fetch(departed), server_tables: Object.new)
      raise 'Departure failed' unless lobby.leave_table(h.table, departed) == :left
    end
  end
  acknowledge_and_step(h, runners.fetch(reader), reader, ticks, count: 12)
  after = inspect_replay(h, reader)
  {departed: departed, start: start, throws: throws, transfer_only: transfer_only, before: before, after: after}
ensure
  runners&.each_value(&:close)
end

results = [
  scenario(departed: 'Bob', throws: 3),
  scenario(departed: 'Alice', throws: 1),
  scenario(departed: 'Alice', throws: 3),
  scenario(departed: 'Alice', throws: 1, transfer_only: true),
  scenario(departed: 'Bob', throws: 0, start: false),
  scenario(departed: 'Alice', throws: 0, start: false)
]
results.each do |result|
  before, after = result.values_at(:before, :after)
  assert(after[:phase] == :playing, "Darts returned to opening after departure: #{result.slice(:departed, :throws, :start, :transfer_only)}")
  old_ids = before[:events].map { |event| event['__id'] }
  assert((old_ids - after[:accepted]).empty?, 'Handover discarded an earlier start or throw')
  assert(after[:throw_index] >= before[:throw_index], 'Handover reset the throw index')
  if result[:departed] == 'Alice' && !result[:transfer_only]
    bot = after[:players].first
    assert(GameRoomParticipants.bot?(bot), 'Departed host was not replaced by a named bot')
    assert(after[:scores][bot] >= before[:scores]['Alice'], 'Replacement lost the departed host score')
    if result[:throws] < 3
      assert(after[:events].any? { |event| event['actor'] == bot && event['action'] == 'darts_throw' },
        'Replacement never completed the departed host turn')
    end
  end
end
puts 'PASS Darts: guest/host departure, active/completed turn, pre-start handover and immutable prior scores/events'
