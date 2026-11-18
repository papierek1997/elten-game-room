require_relative "../support/ui"
require_relative "../support/log"
class Program
  def self.server_app(**_options); end
end
require_relative "../../__app"
require_relative "../support/session_runner"
require_relative '../support/catalog_options'

$stdout.sync = true
tested = []
EltenGameRoom::GAME_REGISTRY.ids.each do |id|
  game = EltenGameRoom::GAME_REGISTRY.build(id)
  next unless game.supports_bots? && game.session_runner?
  # Realtime games need their UI physics client to produce points. They are
  # covered together with the runner in realtime_background_progress_test.
  next if game.background_client?
  options = GameRoomTest::CatalogOptions.for_players(game, bots: true).merge('bot_delay' => 0)
  count = ([game.minimum_players, 2].max..game.maximum_players).find do |size|
    !game.validation_error(options, player_count: size)
  end
  assert(count, "no valid default player count for #{id}")
  h = NativeRoomHarness.new(game: game, users: ['Alice'], bots: count - 1, options: options)
  h.start
  r = runner_for(h)
  r.instance_variable_get(:@context_template).random_source = GameRoomRandom::SeededSource.new(137)
  tick = 0.0
  r.instance_variable_get(:@turn).instance_variable_set(:@clock, -> { tick })
  12.times do
    tick += 2
    step(h, r)
    current = h.replay('Alice')
    break if current.finished?
    action = game.legal_actions(current, 'Alice', context: r.send(:context)).first
    if action
      h.as('Alice') do
        before = h.events('Alice')
        status, = r.submit(session: h.session, replay: current, selection: action, actor: 'Alice')
        if status == :round_pause
          assert(r.send(:round_pause_active?) && h.events('Alice') == before,
            "#{id}: a round pause wrote an action or rejected input outside its boundary")
        else
          assert(status == :ok, "#{id}: its legal human action was rejected: #{status}")
        end
      end
    end
  end
  events = h.events('Alice')
  assert(!events.empty?, "#{id}: runner did not advance")
  assert(h.replay('Alice').accepted_events.size == events.size, "#{id}: runner wrote rejected events")
  tested << [id, events.size, events.count { |event| event['actor'].to_s.start_with?('bot:') }]
  r.close
  puts "#{id}: #{events.size} accepted events, #{tested.last.last} bot events"
end
puts "Session runner game contracts (game/events/bot events): #{tested.inspect}"
assert(tested.size >= 20, 'insufficient game coverage')
