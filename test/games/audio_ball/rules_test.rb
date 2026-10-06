# encoding: UTF-8
require_relative "../../support/sequence_random"
def _(text); text; end

require_relative "../../../games/base"
require_relative "../../../lib/game_random"
require_relative "../../../games/audio_ball" if File.file?(File.expand_path("../../../games/audio_ball.rb", __dir__))

$audio_ball_assertions = 0
$audio_ball_tests = 0

def assert(condition, message)
  $audio_ball_assertions += 1
  raise message unless condition
end

def audio_ball_test(name)
  yield
  $audio_ball_tests += 1
  puts "PASS Audio Ball: #{name}"
end

assert(defined?(GameRoomGames::AudioBall), 'Audio Ball game definition is missing')
game = GameRoomGames::AudioBall.new

audio_ball_test('fixed roster, real-time capabilities and ordered table options') do
  assert(GameRoomGames::AudioBall::POINTS_TO_WIN == 7, 'Audio Ball set target must be seven points')
  assert(game.id == 'audio_ball' && game.name == 'Audio Ball', 'Audio Ball identity changed')
  assert(game.minimum_players == 2 && game.maximum_players == 2, 'Audio Ball is not exactly one versus one')
  assert(game.supports_bots? && !game.supports_bot_move_delay?, 'continuous bots inherited turn-based pacing')
  assert(!game.supports_saved_games?, 'unfinished real-time matches can be saved')
  definitions = game.effective_option_definitions
  assert(definitions.map(&:key) == %w[mode difficulty sets_to_win p2p_enabled p2p_participants_limit], 'game options duplicate privacy or have the wrong order')
  assert(definitions.first(3).map { |definition| definition.choices.map(&:value) } == [['classic'], [1, 2, 3, 4, 5], [1, 2, 3]], 'unsupported mode, difficulty or match length is offered')
  assert(definitions[1].choices.map(&:label) == ['Very easy', 'Easy', 'Normal', 'Hard', 'Very hard'], 'difficulty labels do not match their numeric values')
  assert(game.default_options == {'mode' => 'classic', 'difficulty' => 3, 'sets_to_win' => 1,
    'p2p_enabled' => false, 'p2p_participants_limit' => 8}, 'Audio Ball defaults changed')
  assert(game.normalize_options('mode' => 'arcade', 'difficulty' => 99, 'sets_to_win' => 0) == game.default_options, 'invalid choices did not fall back to defaults')
  assert(game.normalize_options(difficulty: '3', sets_to_win: '2')['sets_to_win'] == 2, 'choice values stopped normalizing to numbers')
  assert(game.options_error({}, player_count: 2) == nil, 'two-player roster was rejected')
  [0, 1, 3, 4].each { |count| assert(game.options_error({}, player_count: count) != nil, 'wrong player count was accepted') }
end

class AudioBallRepository
  def players_for(session); session.fetch('__players'); end
  def actor_of(event, _session); event['actor']; end
  def event_id(event); event['__id']; end
end

class AudioBallRandom < GameRoomRandom::SequenceSource
  attr_reader :calls
  def initialize(values)
    super(values)
    @calls = []
  end
  def roll(count:, sides:)
    @calls << {count: count, sides: sides}
    super
  end
end

def audio_ball_session(players: %w[Alice Bob], owner: 'Alice', options: {})
  {'__id' => 7, '__players' => players, '__insertion_user' => owner,
    'player_one' => players.first, 'options' => JSON.generate(options)}
end

def audio_ball_event(action, value, author: 'Alice', actor: author, id: 1, at: 100)
  {'__id' => id, '__insertion_user' => author, 'actor' => actor,
    'action' => action, 'value' => value, 'created_at' => at}
end

repository = AudioBallRepository.new

audio_ball_test('owner records one random first server and replay only reads that choice') do
  [1, 2].each do |roll|
    session = audio_ball_session
    empty = game.replay(session, [], repository)
    assert(empty.current_player == nil && empty.state[:first_server] == nil && empty.state[:server] == nil, 'empty replay pretended that a server had been drawn')
    assert(empty.state.values_at(:scores, :sets, :set_number, :rally, :last_point, :set_resume_at) == [[0, 0], [0, 0], 1, 0, nil, nil], 'initial match state is incomplete')
    random = AudioBallRandom.new([roll])
    context = GameRoomGames::ActionContext.new(table_owner: 'Alice', random_source: random, local_data: {})
    assert(game.automatic_action_allowed?(empty, 'Alice', table_owner: 'Alice'), 'owner cannot start the match')
    assert(!game.automatic_action_allowed?(empty, 'Bob', table_owner: 'Alice'), 'guest was granted automatic authority')
    3.times { assert(game.automatic_action_due?(empty, 'Alice', context: context), 'owner scheduler did not wake for the initial draw') }
    selection = game.automatic_action(empty, 'Alice', context: context)
    assert(selection == {'kind' => 'command', 'action' => 'audio_ball_start'}, 'start is not a normal game command')
    assert(random.calls.empty?, 'automatic predicate or selection consumed randomness')
    assert(game.action_for(selection, empty, 'Bob', context: context) == [:invalid, nil], 'guest can draw the first server')
    assert(game.action_for(selection, empty, 'Alice') == [:invalid, nil], 'draw bypassed owner context')
    status, plan = game.action_for(selection, empty, 'Alice', context: context)
    assert(status == :ok && plan.events.length == 1, 'initial draw did not become one durable event')
    command = plan.events.first
    assert(command.action == 'audio_ball_start' && command.value == (roll - 1).to_s, 'durable first-server value is not the die result')
    assert(command.value.length <= 64 && random.calls == [{count: 1, sides: 2}], 'first server did not use exactly one two-sided roll')
    event = audio_ball_event(command.action, command.value)
    replay = game.replay(session, [event], repository)
    3.times { assert(game.replay(session, [event], repository).state == replay.state, 'identical replay changed the first server') }
    assert(replay.state[:first_server] == roll - 1 && replay.state[:server] == roll - 1 && replay.state[:rally] == 0, 'start incorrectly counted as a point')
    assert(replay.accepted_events == [event], 'initial draw was not retained as an accepted event')
    assert(game.automatic_action(replay, 'Alice', context: context) == nil, 'recorded first server is being drawn again')
    assert(!game.automatic_action_due?(replay, 'Alice', context: context), 'idle match kept waking without a point')
    assert(game.action_for(selection, replay, 'Alice', context: context) == [:invalid, nil], 'second start was allowed')
    assert(random.calls.length == 1, 'read-only replay or rejected restart consumed randomness')
    duplicate = audio_ball_event('audio_ball_start', (2 - roll).to_s, id: 2)
    assert(game.replay(session, [event, duplicate], repository).state == replay.state, 'later start changed the original server')
    ['2', '-1', '01', '0:1', "1\n", '0' * 65, nil, 0].each do |value|
      invalid = game.replay(session, [audio_ball_event('audio_ball_start', value)], repository)
      assert(invalid.state[:first_server] == nil && invalid.accepted_events.empty?, 'malformed initial server was accepted')
    end
    forged = audio_ball_event('audio_ball_start', '0', author: 'Mallory', actor: 'Alice')
    assert(game.replay(session, [forged], repository).state[:first_server] == nil, 'claimed actor overrode authenticated start author')
    assert(game.replay(session, [event.merge('__insertion_user' => 'aLiCe')], repository).state[:first_server] == roll - 1, 'owner comparison became case-sensitive')
  end
end

audio_ball_test('owner-coordinated points preserve authentication, sequence, timeout and history') do
  [%w[Alice Bob], %w[Bob Carol], ['bot:7:1', 'bot:7:2']].each do |players|
    session = audio_ball_session(players: players)
    start = audio_ball_event('audio_ball_start', '1', actor: players.first)
    events = [start]
    replay = game.replay(session, events, repository)
    context = GameRoomGames::ActionContext.new(table_owner: 'Alice', local_data: {'audio_ball_point' => '0:0'})
    actor = game.automatic_actor(replay, 'Alice', table_owner: 'Alice')
    assert(actor == players.first, 'observer owner lost the standard controller route')
    assert(game.automatic_action_due?(replay, actor, context: context), 'pending point did not wake the owner scheduler')
    selection = game.automatic_action(replay, actor, context: context)
    assert(selection == {'kind' => 'command', 'action' => 'audio_ball_point', 'point' => '0:0'}, 'pending point does not use the standard game command')
    assert(game.action_for(selection.merge('point' => '0:1'), replay, actor, context: context) == [:invalid, nil], 'point did not require exact local confirmation')
    assert(game.action_for(selection, replay, 'Mallory', context: context) == [:invalid, nil], 'unrelated actor can coordinate points')
    wrong_owner = GameRoomGames::ActionContext.new(table_owner: 'Mallory', local_data: context.local_data)
    assert(game.action_for(selection, replay, actor, context: wrong_owner) == [:invalid, nil], 'untrusted context became the table owner')
    empty = game.replay(session, [], repository)
    assert(game.action_for(selection, empty, actor, context: context) == [:invalid, nil], 'point was accepted before the server draw')
    assert(game.replay(session, [audio_ball_event('audio_ball_point', '0:0')], repository).state[:rally] == 0, 'replay accepted points before the start')
    status, plan = game.action_for(selection, replay, actor, context: context)
    assert(status == :ok && plan.events.length == 1 && plan.events.first.value.length <= 64, 'point did not produce one bounded durable event')
    event = audio_ball_event(plan.events.first.action, plan.events.first.value, actor: actor, id: 2)
    events << event
    replay = game.replay(session, events, repository)
    assert(replay.state[:scores] == [1, 0] && replay.state[:rally] == 1 && replay.state[:server] == 1, 'first point changed service before two completed points')
    assert(replay.state[:last_point].values_at(:winner, :scores, :set_finished, :match_finished, :timeout) == [0, [1, 0], false, false, false], 'last point is missing its score and result data')
    assert(game.participant_scores(replay) == {players[0] => 1, players[1] => 0}, 'single-set scoreboard does not show current points')
    point_history = replay.history.find { |entry| entry.key == 'point:2' }
    assert(point_history && point_history.event_id == 2 && point_history.actor == players[0] && point_history.text.include?('scores.'), 'accepted point has no attributed score history')
    assert(!game.describe_event(event, repository, replay, players.first).empty?, 'accepted point has no public announcement')
    assert(game.automatic_action(replay, actor, context: context) == nil, 'already persisted local point kept being submitted')
    assert(game.replay(session, events + [event], repository).state == replay.state, 'duplicate point was counted twice')
    next_point = audio_ball_event('audio_ball_point', '1:1:timeout', actor: actor, id: 3)
    forged = next_point.merge('__insertion_user' => 'Mallory', 'actor' => 'Alice')
    invalid_values = ['2:1', '0:1', '-1:1', '01:1', '1:2', '1:1:late', "1:1\n", '0' * 65 + ':1', nil, 1]
    invalid_events = invalid_values.map { |value| next_point.merge('value' => value) }
    ignored = [forged, next_point.merge('action' => 'pong_point')] + invalid_events
    assert(game.replay(session, events + ignored, repository).state == replay.state, 'unauthenticated, duplicate, out-of-order or malformed point changed replay')
    assert(game.replay(session, events + ignored, repository).history == replay.history, 'rejected point leaked into history')
    invalid_values.each do |value|
      context.local_data['audio_ball_point'] = value
      assert(game.action_for(selection.merge('point' => value), replay, actor, context: context) == [:invalid, nil], 'malformed point passed local planning')
    end
    context.local_data['audio_ball_point'] = '1:1:timeout'
    selection = game.automatic_action(replay, actor, context: context)
    status, plan = game.action_for(selection, replay, actor, context: context)
    assert(status == :ok && plan.events.first.value == '1:1:timeout', 'timeout lost its durable marker')
    final = game.replay(session, events + ignored + [next_point], repository)
    assert(final.state[:scores] == [1, 1] && final.state[:rally] == 2 && final.state[:server] == 0, 'timeout did not award one point and rotate the server')
    assert(final.state[:last_point][:timeout], 'timeout result was not preserved')
    timeout_history = final.history.find { |entry| entry.key == 'timeout:3' }
    assert(timeout_history && timeout_history.actor == players[0] && timeout_history.text.include?('did not hit'), 'timeout history blames the winner or only mentions serving')
    assert(final.accepted_events == events + [next_point], 'rejected points polluted accepted events')
    assert(replay.state[:last_point][:scores] == [1, 0], 'later replay mutated an earlier point score')
  end
end

def audio_ball_score(game, session, events, repository, side, timeout: false, at: 100 + events.length * 10)
  replay = game.replay(session, events, repository)
  point = "#{replay.state[:rally]}:#{side}#{timeout ? ':timeout' : ''}"
  owner = replay.state[:owner]
  actor = game.automatic_actor(replay, owner, table_owner: owner)
  context = GameRoomGames::ActionContext.new(table_owner: owner, now: at, local_data: {'audio_ball_point' => point})
  selection = game.automatic_action(replay, actor, context: context)
  assert(selection != nil, 'owner has no automatic action for the completed point')
  status, plan = game.action_for(selection, replay, actor, context: context)
  assert(status == :ok && plan.events.length == 1 && plan.events.first.value.length <= 64, 'valid point did not pass the normal action path')
  command = plan.events.first
  events << audio_ball_event(command.action, command.value, author: owner, actor: actor, id: events.length + 1, at: at)
  game.replay(session, events, repository)
end

audio_ball_test('seven-point boundary keeps a two-point lead and unlimited deuce') do
  [[6, 0, false], [7, 0, true], [6, 6, false], [7, 6, false], [8, 6, true], [22, 21, false], [23, 21, true]].each do |own, other, finished|
    session = audio_ball_session
    events = [audio_ball_event('audio_ball_start', '0')]
    other.times { [0, 1].each { |side| audio_ball_score(game, session, events, repository, side) } }
    (own - other).times { audio_ball_score(game, session, events, repository, 0) }
    replay = game.replay(session, events, repository)
    assert(replay.state[:scores] == [own, other], 'score was reset or capped before the intended seven-point/deuce boundary')
    assert(replay.finished? == finished, "wrong seven-point boundary at #{own}:#{other}")
    assert(replay.winner == (finished ? 'Alice' : nil), 'seven-point boundary attributed the wrong winner')
  end
end

audio_ball_test('complete one-, two- and three-set victories, deuce and alternating set starters') do
  [1, 2, 3].each do |needed|
    [0, 1].each do |first_server|
      session = audio_ball_session(options: {'sets_to_win' => needed})
      events = [audio_ball_event('audio_ball_start', first_server.to_s)]
      replay = game.replay(session, events, repository)
      set_winners = Array.new(needed - 1) { [0, 1] }.flatten + [1]
      totals = [0, 0]
      set_winners.each_with_index do |set_winner, set_index|
        assert(replay.state[:server] == (first_server + set_index) % 2, 'successive sets did not alternate their first server')
        deuce = needed == 1 || set_index.odd?
        points = deuce ? Array.new(6) { [0, 1] }.flatten + [set_winner, 1 - set_winner, set_winner, set_winner] : Array.new(7, set_winner)
        points.each_with_index do |side, index|
          replay = audio_ball_score(game, session, events, repository, side, timeout: index == points.length - 1)
          assert(replay.state[:rally] == events.length - 1, 'rally counter reset at a set boundary')
          completed = index == points.length - 1
          final = set_index == set_winners.length - 1
          expected_server = if completed && !final
            (first_server + set_index + 1) % 2
          else
            (first_server + set_index + (index + 1) / 2) % 2
          end
          assert(replay.state[:server] == expected_server, 'wrong service block within a set or wrong next-set starter')
          if index < points.length - 1
            assert(replay.state[:sets] == totals && replay.state[:set_number] == set_index + 1 && !replay.finished?, 'set ended without seven points and a two-point lead')
          end
        end
        totals[set_winner] += 1
        final = set_index == set_winners.length - 1
        expected_score = deuce ? [7, 7] : [0, 0]
        expected_score[set_winner] = deuce ? 7 + 2 : 7
        assert(replay.state[:sets] == totals, 'completed set did not advance won-set totals')
        assert(replay.state[:last_point].values_at(:winner, :scores, :set_number, :set_finished, :match_finished) == [set_winner, expected_score, set_index + 1, true, final], 'set-closing point lost its pre-reset score or match status')
        assert(replay.state[:scores] == (final ? expected_score : [0, 0]), 'nonfinal set failed to reset or final set score was erased')
        assert(replay.state[:set_number] == (final ? set_index + 1 : set_index + 2), 'set number did not advance only for nonfinal sets')
        assert(replay.state[:set_resume_at] == (final ? nil : events.last['created_at'] + 5), 'inter-set pause is not five seconds from the server event')
        set_history = replay.history.find { |entry| entry.key == "set:#{events.last['__id']}" }
        assert(set_history && set_history.actor == replay.players[set_winner] && set_history.kind == :set && set_history.text.include?("set #{set_index + 1}"), 'set victory has no attributed history entry')
        scores = needed == 1 ? expected_score : totals
        assert(game.participant_scores(replay) == {'Alice' => scores[0], 'Bob' => scores[1]}, 'match scoreboard does not show sets for multi-set matches')
      end
      assert(replay.finished? && replay.winner == 'Bob' && !replay.draw, 'match did not end at the selected number of won sets')
      assert(game.bot_reward(replay, 'Bob') == 1.0 && game.bot_reward(replay, 'Alice') == -1.0, 'match result does not use the normal winner contract')
      assert(replay.history.count { |entry| entry.kind == :result } == 1 && replay.history.last.actor == 'Bob', 'match result was missing or repeated')
      assert(game.result_text(replay) == 'Bob won the game.', 'normal result announcement is unavailable')
      after_end = audio_ball_event('audio_ball_point', "#{replay.state[:rally]}:0", id: events.length + 1)
      assert(game.replay(session, events + [after_end], repository).state == replay.state, 'post-match point changed the final score')
      context = GameRoomGames::ActionContext.new(table_owner: 'Alice', local_data: {'audio_ball_point' => after_end['value']})
      selection = {'kind' => 'command', 'action' => 'audio_ball_point', 'point' => after_end['value']}
      assert(game.action_for(selection, replay, 'Alice', context: context) == [:finished, nil], 'finished match still accepted a planned action')
      assert(game.automatic_action(replay, 'Alice', context: context) == nil && !game.automatic_action_due?(replay, 'Alice', context: context), 'finished match kept scheduling points')
      assert(game.replay(session, events, repository).to_h == replay.to_h, 'complete match replay is not deterministic')
    end
  end
end

audio_ball_test('five-second set break is enforced by planning and server-timestamp replay') do
  session = audio_ball_session(options: {'sets_to_win' => 2})
  events = [audio_ball_event('audio_ball_start', '0')]
  7.times { audio_ball_score(game, session, events, repository, 0) }
  replay = game.replay(session, events, repository)
  deadline = replay.state[:set_resume_at]
  point = '7:1'
  selection = {'kind' => 'command', 'action' => 'audio_ball_point', 'point' => point}
  context = GameRoomGames::ActionContext.new(table_owner: 'Alice', now: deadline - 1, local_data: {'audio_ball_point' => point})
  assert(game.automatic_action(replay, 'Alice', context: context) == nil, 'pending point bypassed the set break')
  assert(!game.automatic_action_due?(replay, 'Alice', context: context), 'scheduler woke during the set break')
  assert(game.action_for(selection, replay, 'Alice', context: context) == [:invalid, nil], 'direct planning bypassed the set break')
  early = audio_ball_event('audio_ball_point', point, id: events.length + 1, at: deadline - 1)
  assert(game.replay(session, events + [early], repository).state == replay.state, 'forged early point bypassed the durable set break')
  context.now = deadline
  assert(game.automatic_action_due?(replay, 'Alice', context: context), 'set break never released the pending point')
  assert(game.action_for(selection, replay, 'Alice', context: context).first == :ok, 'point at the set-break deadline was rejected')
  after = game.replay(session, events + [early.merge('created_at' => deadline)], repository)
  assert(after.state.values_at(:scores, :sets, :set_number, :rally, :set_resume_at) == [[0, 1], [1, 0], 2, 8, nil], 'first point of the next set did not clear the old break')
  assert(replay.state[:last_point][:scores] == [7, 0], 'next set erased the prior closing point snapshot')
  context.now = nil
  assert(game.action_for(selection, replay, 'Alice', context: context).first == :ok, 'missing simulation clock permanently blocked planning')
  no_timestamps = events.map { |event| event.reject { |key, _| key == 'created_at' } }
  headless = game.replay(session, no_timestamps, repository)
  assert(headless.state[:set_resume_at] == nil, 'missing server timestamp invented an epoch deadline')
  assert(game.replay(session, no_timestamps + [early.reject { |key, _| key == 'created_at' }], repository).state[:scores] == [0, 1], 'headless replay stalled at a set boundary')
end

require_relative "../../support/ui"
require_relative "../../../lib/game_surfaces"

audio_ball_test('surface contract and nonconflicting participant shortcuts') do
  session = audio_ball_session(players: ['Alice', 'bot:7:1'])
  replay = game.replay(session, [audio_ball_event('audio_ball_start', '0')], repository)
  spec = game.surface_spec(replay, 'aLiCe')
  assert(spec.is_a?(GameSurfaces::AudioBallSpec), 'Audio Ball returned a different surface type')
  assert(spec.to_h == {game_id: 'audio_ball', header: 'Audio Ball playfield', players: ['Alice', 'Computer 1'],
    viewer: 0, scores: [0, 0], sets: [0, 0], set_number: 1, finished: false}, 'surface omitted match state or exposed raw bot IDs')
  assert(game.surface_spec(replay, 'Watcher').viewer == nil && game.surface_spec(replay, 'bot:7:1').viewer == 1, 'surface gave observer a player seat')
  assert(game.shortcut_features == [], 'inherited bare-letter shortcuts conflict with shot controls')
  participant_keys = game.game_shortcuts(replay, 'Alice').map { |shortcut| [shortcut.key, shortcut.modifiers, shortcut.action_name] }
  assert(participant_keys == [['s', [:shift], 'scores'], ['t', [], 'server'], ['w', [:control], 'hurry']], 'scores, status or hurry shortcut conflicts with shot controls')
  observer_keys = game.game_shortcuts(replay, 'Watcher').map(&:action_name)
  assert(observer_keys == %w[scores server], 'observer received the hurry shortcut')
  events = [audio_ball_event('audio_ball_start', '0')]
  7.times { replay = audio_ball_score(game, session, events, repository, 1) }
  assert(game.surface_spec(replay, 'Alice').finished && game.surface_spec(replay, 'Alice').scores == [0, 7], 'finished surface discarded the final score')
  assert(game.game_shortcuts(replay, 'Alice').map(&:action_name) == %w[scores server], 'finished match still offers hurry')
  binary_game = Class.new(GameRoomGames::AudioBall) do
    def _(text); super(text.b); end
  end.new
  binary_session = audio_ball_session(players: ['Michał'.b, 'Bob'])
  binary_replay = binary_game.replay(binary_session, [], repository)
  binary_spec = binary_game.surface_spec(binary_replay, 'Bob')
  strings = [binary_game.name, binary_spec.header] + binary_spec.players + binary_replay.history.map(&:text)
  assert(strings.all? { |text| text.encoding == Encoding::UTF_8 && text.valid_encoding? }, 'packaged binary text reached Audio Ball controls without UTF-8 normalization')
end

audio_ball_test('authored rules explain fixed scoring, sound, timing and every active control') do
  book = game.rule_book(options: game.default_options)
  assert(book.documents.map(&:id) == [:rules, :controls, :current_options], 'Audio Ball rules bypass the standard three-document help')
  rules = book.documents.first.text
  ['one against one', 'bot', 'Classic', '25 steps', 'on the right', 'on the left', 'two steps',
    'press the matching defence key once', 'then release it', 'last active defence', 'most recently pressed key still held', 'Every new ball needs a new press',
    'even if the shot type is the same', 'Preparing', 'ten seconds', 'as long as you like', 'random',
    'every two completed points', 'Players take turns starting each new set',
    'the player who starts the first also starts the third', 'the opponent starts the second and fourth',
    '7 points', 'lead by at least two', '1, 2 or 3', 'five-second',
    'set number', 'who is serving'].each do |text|
    assert(rules.include?(text), "Audio Ball rules do not explain #{text}")
  end
  assert(!rules.match?(/Axel Pong|0 to 21|5\.7-second/), 'player rules contain another game or implementation details')
  assert(rules.include?('At every level, each later hit in the rally increases the current speed by 5%.'), 'rules omit the shared acceleration')
  [['Very easy', '4'], ['Easy', '2.2'], ['Normal', '1.5'], ['Hard', '0.9'], ['Very hard', '0.6']].each do |name, seconds|
    paragraph = game.rule_sections.flat_map(&:paragraphs).find { |text| text.start_with?(name) }
    assert(paragraph && paragraph.include?("#{seconds} seconds"), "rules contain the wrong #{name} speed")
  end
  controls = book.documents[1].text
  ['Up arrow:', 'W:', 'Left arrow:', 'D:', 'Down arrow:', 'S:', 'Right arrow:', 'A:', 'Shift+S:', 'Ctrl+W:', 'Ctrl+P:', 'T:'].each do |text|
    assert(controls.lines.any? { |line| line.start_with?(text) }, "Audio Ball help omits #{text}")
  end
  assert(!controls.match?(/(?:\A|\n)S:.*scores/), 'help steals the S shot key for scores')
  authored_path = File.expand_path("../../../tools/data/rulebooks/audio_ball.json", __dir__)
  assert(File.file?(authored_path), 'Audio Ball has no authored rulebook')
  authored = JSON.parse(File.read(authored_path, encoding: 'UTF-8'))
  assert(authored['source'] == 'games/audio_ball.rb', 'rulebook points to another source')
  sections = game.rule_sections
  assert(sections.map { |section| section.id.to_s } == authored['sections'].map { |section| section['id'] }, 'authored and runtime rule sections differ')
  authored['sections'].zip(sections).each do |document, section|
    assert(document['title']['en'] == section.title && document['paragraphs'].map { |pair| pair['en'] } == section.paragraphs, 'authored English rules differ from runtime text')
    ([document['title']] + document['paragraphs']).each do |pair|
      assert(%w[en pl].all? { |language| pair[language].is_a?(String) && !pair[language].strip.empty? && pair[language].valid_encoding? }, 'authored rule text is incomplete')
    end
  end
end

class FormTimer
  def initialize(*_args, **_options); end
end unless defined?(FormTimer)

audio_ball_test('client factory uses the real Audio Ball client without opening a connection') do
  program = Object.new
  program.define_singleton_method(:create_sound_from_asset) { |_name, **_options| nil }
  client = game.build_client(program)
  assert(client && client.class.name == 'GameRoomAudioBall::Client', 'Audio Ball did not build its own real-time client')
  assert(client.instance_variable_get(:@game).equal?(game), 'client is not using the same durable game definition')
end

require_relative "../../../lib/game_repository"

module Session
  def self.name; @audio_ball_name || 'Alice'; end
  def self.name=(value); @audio_ball_name = value; end
end

class AudioBallTransport
  attr_reader :calls
  def initialize; @calls = []; end
  def live_store?; true; end
  def append_game_action(**arguments)
    @calls << arguments
    arguments[:events].each_with_index.map do |command, index|
      {'__id' => @calls.length * 10 + index, '__insertion_user' => Session.name,
        '__controller' => arguments[:controller], 'actor' => arguments[:actor],
        'sequence' => arguments[:sequence] + index, 'action' => command.action,
        'value' => command.value, 'created_at' => 100 + @calls.length * 10}
    end
  end
end

audio_ball_test('real repository preserves observer-owner authorship for the random start and a point') do
  [%w[Alice Bob], %w[Bob Carol], ['bot:7:1', 'Bob'], ['bot:7:1', 'bot:7:2']].each do |players|
    transport = AudioBallTransport.new
    actual_repository = GameRepository.new(Object.new, transport: transport, server_tables: {})
    session = audio_ball_session(players: players).merge('table_id' => 7)
    events = []
    random = AudioBallRandom.new([2])
    context = GameRoomGames::ActionContext.new(table_owner: 'Alice', random_source: random, local_data: {})
    2.times do |step|
      replay = game.replay(session, events, actual_repository)
      actor = game.automatic_actor(replay, 'Alice', table_owner: 'Alice')
      context.local_data['audio_ball_point'] = '0:1:timeout' if step == 1
      selection = game.automatic_action(replay, actor, context: context)
      status, plan = game.action_for(selection, replay, actor, context: context)
      assert(status == :ok, 'observer-owner could not prepare the start or confirmed point')
      events += actual_repository.append_events(session: session,
        sequence: actual_repository.next_sequence(session, replay.accepted_events), events: plan.events,
        actor: actor, controller: actor != 'Alice')
      call = transport.calls.last
      assert(call[:actor] == players.first && call[:controller] == (players.first != 'Alice'), 'durable event bypassed the standard owner controller route')
    end
    final = game.replay(session, events, actual_repository)
    assert(final.state[:first_server] == 1 && final.state[:scores] == [0, 1] && final.state[:rally] == 1, 'authenticated controller events were rejected on replay')
    assert(events.map { |event| event['sequence'] } == [0, 1] && random.calls.length == 1, 'start lost its durable sequence or drew twice')
    assert(actual_repository.actor_of(events.first, session) == players.first, 'repository did not resolve the delegated actor')
    assert(events.all? { |event| event['__insertion_user'] == 'Alice' }, 'owner author was replaced with a delegated participant')
    forged = events.map { |event| event.merge('__insertion_user' => 'Mallory') }
    assert(game.replay(session, forged, actual_repository).accepted_events.empty?, 'claimed owner controller accepted an untrusted author')
    Session.name = 'Mallory'
    begin
      actual_repository.append_events(session: session, sequence: 2,
        events: [GameRoomGames::EventCommand.new(action: 'audio_ball_point', value: '1:1')], actor: players.first, controller: true)
      assert(false, 'real repository accepted a controller write from a guest')
    rescue ArgumentError
      assert(transport.calls.length == 2, 'unauthorized controller reached the transport')
    ensure
      Session.name = 'Alice'
    end
  end
end

audio_ball_test('invalid rosters, owner fallback and malformed options cannot corrupt a replay') do
  start = audio_ball_event('audio_ball_start', '0')
  point = audio_ball_event('audio_ball_point', '0:0', id: 2)
  [[], ['Alice'], %w[Alice Bob Carol], %w[Alice alice], ['Alice', '']].each do |players|
    replay = game.replay(audio_ball_session(players: players), [start, point], repository)
    context = GameRoomGames::ActionContext.new(table_owner: 'Alice', random_source: AudioBallRandom.new([1]))
    assert(replay.accepted_events.empty? && replay.state[:first_server] == nil, 'invalid roster replay accepted a start or point')
    assert(game.automatic_action(replay, 'Alice', context: context) == nil, 'invalid roster scheduled a start')
    assert(game.action_for({'kind' => 'command', 'action' => 'audio_ball_start'}, replay, 'Alice', context: context) == [:invalid, nil], 'invalid roster could plan a start')
  end
  fallback = audio_ball_session.merge('__insertion_user' => '', 'options' => '{broken')
  replay = game.replay(fallback, [start], repository)
  assert(replay.state[:owner] == 'Alice' && replay.state[:options] == game.default_options && replay.state[:server] == 0, 'legacy owner or malformed-options fallback broke replay')
  fallback['player_one'] = ''
  assert(game.replay(fallback, [start], repository).state[:owner] == 'Alice', 'missing owner did not fall back to the first participant')
  actor_only = start.reject { |key, _| key == '__insertion_user' }
  assert(game.replay(fallback, [actor_only], repository).state[:first_server] == 0, 'legacy authenticated actor fallback stopped working')
end

puts "Audio Ball: #{$audio_ball_tests} tests, #{$audio_ball_assertions} assertions passed"
