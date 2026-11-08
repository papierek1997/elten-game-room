require_relative "../../support/session_runner"
require_relative "../../../games/dice_poker"
require_relative "../../../games/liars_dice"

# The normal executor owns private writes and acknowledgements, even with a spectator host.
[false,true].each do |spectator_host|
  game = GameRoomGames::LiarsDice.new
  users = spectator_host ? %w[Host Alice Bob] : %w[Alice Bob]
  players = %w[Alice Bob]
  h = NativeRoomHarness.new(game: game, users: users, options: game.normalize_options('starting_dice'=>1))
  h.as(users.first) do
    session = h.repositories.fetch(users.first).start_session(table: h.table, game: game.id, players: players, options: JSON.generate(game.normalize_options('starting_dice'=>1)))
    h.instance_variable_set(:@session, session)
  end
  runners = users.to_h { |user| [user, runner_for(h,user)] }
  begin
    if spectator_host
      step(h, runners['Host'], 'Host')
      assert(h.events('Host').empty?, 'Spectator host generated a human secret')
    end
    players.each { |user| step(h, runners[user], user) }
    assert(h.events('Alice').map { |e| e['action'] } == %w[commit commit], 'Client secret commits missing')
    step(h, runners[users.first], users.first)
    replay = h.replay('Alice')
    assert(replay.state[:phase] == :bidding && replay.state[:reveals].empty?, 'Native round leaked cups or failed to seed')
    assert(h.events('Alice').last['__server_random'], 'Native private dice lack server entropy')
    guest_context = runners['Bob'].send(:context)
    assert(guest_context.hidden_submissions.reveal(session_id: guest_context.session_id,
      round_id: GameRoomLiarsDiceSecrets.round_id(replay.state), user: 'Alice').nil?, 'Guest vault contains another human secret')
    [ ['Alice', {'kind'=>'command','action'=>'bid','round'=>1,'bid_index'=>0,'quantity'=>2,'face'=>6}],
      ['Bob', {'kind'=>'command','action'=>'challenge','round'=>1,'bid_index'=>1}] ].each do |user,input|
      current = h.replay(user)
      h.as(user) { assert(runners[user].submit(session: h.session, replay: current, selection: input, actor: user).first == :ok, 'Native human action rejected') }
    end
    if spectator_host
      step(h, runners['Host'], 'Host')
      assert(h.events('Host').count { |e| e['action'] == 'reveal' } == 0, 'Spectator host disclosed a human cup')
    end
    players.each { |user| step(h, runners[user], user) }
    assert(h.replay('Alice').finished?, 'Native private reveals did not finish the game')
    assert(h.events('Alice').map { |e| e['action'] } == %w[commit commit deal bid challenge reveal reveal], 'Private writes or ACKs duplicated')
    assert(h.replay('Alice').accepted_events.size == 7, 'Executor wrote rejected private events')
    h.assert_converged("liar native spectator=#{spectator_host}")
  ensure
    runners.each_value(&:close)
  end
end

game = GameRoomGames::DicePoker.new
h = NativeRoomHarness.new(game: game, users: %w[Alice Bob], options: game.normalize_options('round_limit'=>1))
h.start
runners = h.users.to_h { |user| [user,runner_for(h,user)] }
begin
  h.users.each do |user|
    [ {'kind'=>'dice','action'=>'roll'}, {'kind'=>'dice','action'=>'score','category'=>'stand'} ].each do |input|
      h.as(user) { assert(runners[user].submit(session: h.session, replay: h.replay(user), selection: input, actor: user).first == :ok, 'Native poker input rejected') }
    end
  end
  assert(h.replay('Alice').finished? && h.replay('Alice').accepted_events.size == 4, 'Native poker did not finish')
  assert(h.events('Alice').select { |e| e['action'] == 'roll' }.all? { |e| e['__server_random'] }, 'Poker uses local public rolls')
  h.assert_converged('dice poker native')
ensure
  runners.each_value(&:close)
end
puts 'Dice game active executors: native poker, separate human secrets, spectator host, server entropy, reveal ACKs and converged results passed'

game = GameRoomGames::LiarsDice.new
h = NativeRoomHarness.new(game:game,users:['Alice'],bots:1,options:game.normalize_options('starting_dice'=>1,'bot_delay'=>0))
h.start
runner = runner_for(h)
begin
  80.times do
    step(h,runner)
    current = h.replay('Alice')
    break if current.finished?
    if current.state[:phase] == :bidding && current.current_player == 'Alice'
      actions = game.legal_actions(current,'Alice',context:runner.send(:context))
      input = actions.find { |action| action['action'] == 'challenge' } || actions.first
      h.as('Alice') { assert(runner.submit(session:h.session,replay:current,selection:input,actor:'Alice').first == :ok,'Human input with native bot failed') }
    end
  end
  events = h.events('Alice')
  assert(h.replay('Alice').finished? && h.replay('Alice').accepted_events.size == events.size,'Native bot match unfinished or rejected')
  bot_actions = events.select { |event| GameRoomParticipants.bot?(event['actor']) }.map { |event| event['action'] }
  assert(bot_actions.include?('commit') && bot_actions.include?('reveal') && (bot_actions & %w[bid challenge exact]).any?,'Bot bypassed active executor for private actions')
ensure
  runner.close
end
puts "Liar's dice active executor: bot commit, private decision, reveal and terminal result passed"
