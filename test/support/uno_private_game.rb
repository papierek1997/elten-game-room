require_relative 'private_card_games'
require_relative '../../games/uno'

def check_private_uno_game(options = {}, users: %w[Alice Bob Carol])
game = GameRoomGames::Uno.new
h, runners = PrivateCardGamesTest.create(game, users:users, options:{'score_limit'=>50,
  'zero_seven'=>true, 'interceptions'=>true, 'super_interceptions'=>true, 'straights'=>true, 'buzzers'=>true,
  'bluff_challenge'=>true}.merge(options), random_values:Array.new(16,8), clock:ClockEventContract::ManualTime.new)
80.times do
  break unless game.send(:private_waiting?, h.replay('Alice').state)
  PrivateCardGamesTest.tick(h,runners)
end
assert(h.replay('Alice').state[:phase] == :playing, 'opening failed')
PrivateCardGamesTest.assert_private(h)
counts = Hash.new(0)
returned = false
180.times do |index|
  PrivateCardGamesTest.tick(h,runners)
  first = h.replay('Alice')
  warn "UNO #{index}: #{first.accepted_events.size} events, #{first.state[:phase]}, side #{first.state[:side]}" if ENV['UNO_PRIVATE_PROGRESS']
  break if first.finished? || first.state[:round] >= 2
  next if first.state[:phase] == :round_complete
  choices = h.users.filter_map do |user|
    mine = h.replay(user)
    actions = game.legal_actions(mine,user)
    next if actions.empty?
    selection = actions.max_by do |a|
      score = game.bot_action_score(mine,user,a)
      score += 10_000 if options['deck'] == 'flip' && a['card'] && game.send(:card_type,a['card']) == 'L' &&
        mine.history.none? { |entry| entry.key.start_with?('flip:') }
      score
    end
    [user, selection, mine]
  end
  assert(!choices.empty?, "no actions #{first.state[:phase]}, #{first.state[:private_error]}")
  actor, choice, mine = choices[index % choices.size]
  counts[choice['action']] += 1
  PrivateCardGamesTest.submit(h,runners,actor,choice)
  80.times do
    PrivateCardGamesTest.tick(h,runners)
    break unless game.send(:private_waiting?,h.replay(actor).state)
  end
  PrivateCardGamesTest.assert_private(h)
  if !returned && index >= 5
    before = h.replay(actor).state[:hands][actor].dup
    owner = h.view('Alice')
    owner.transfer_ownership(owner.participants.find { |p| p.user == users.last })
    runners[actor].close
    h.view(actor).leave
    h.add_client(actor)
    assert(h.join(actor), 'return failed')
    runners[actor] = runner_for(h,actor)
    assert(h.replay(actor).state[:hands][actor] == before, 'return changed hand')
    returned = true
  end
end
final = h.replay('Alice')
assert(final.accepted_events.size == h.events('Alice').size, 'valid command rejected')
assert(final.finished? || final.state[:round] >= 2, "no round completed: #{counts.inspect}, #{final.state[:phase]}")
assert(returned && counts['play'] > 5 && counts['draw'] > 0, 'coverage missing')
runners.each_value(&:close)
history_counts = final.history.group_by { |entry| entry.key.split(':').first }.transform_values(&:size)
assert(history_counts.fetch('flip',0) > 0, 'Flip fixture never changed sides') if options['deck'] == 'flip'
puts "PASS private UNO #{options.inspect} #{counts.inspect}; #{final.accepted_events.size} events, host/return, scoring; #{history_counts.inspect}"
end
