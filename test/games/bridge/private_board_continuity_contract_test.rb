require_relative '../../support/private_card_games'
require_relative '../../../games/bridge'

# Independent review of a second real board, not four passed-out auctions.
# The trick oracle below does not call the model's winner/legal-card helpers.
module BridgeBoardContinuity
  module_function

  def auction(h, runners, bid: '1N')
    4.times do |index|
      actor = h.replay('Alice').current_player
      PrivateCardGamesTest.submit(h, runners, actor,
        {'kind'=>'command', 'action'=>'call', 'call'=>index.zero? ? bid : 'P'})
    end
  end

  def play_board(h, runners, cheat: false)
    played, winners, trick, cheated = [], [0, 0], [], false
    52.times do
      current = h.replay('Alice')
      actor = current.current_player
      assert(actor, "board stalled: #{current.state[:phase]}")
      mine = h.replay(actor)
      seat = mine.state[:seat_to_play]
      hand_owner = mine.state[:seats].fetch(seat)
      hand = mine.state[:hands].fetch(hand_owner)
      following = trick.empty? ? hand : hand.select { |card| card[-1] == trick.first.last[-1] }
      eligible = following.empty? ? hand : following
      bad = cheat && !cheated && hand_owner == actor && hand.find { |card| !eligible.include?(card) }
      card = bad || eligible.min
      assert(card && !GameRoomPrivateCardLedger.hidden?(card), 'active hand not authenticated')
      if bad
        receipt = GameRoomPrivateCardLedger.locate(mine.state, actor, card)
        command = GameRoomPrivateCards.command('play', card, **receipt.merge(operation:'reveal'))
        h.instance_variable_set(:@session, h.repositories[actor].snapshot_for(h.session).session)
        h.write(actor, [command])
        cheated = true
      else
        selection = {'kind'=>'card', 'action'=>'select', 'zone'=>hand_owner == actor ? 'hand' : 'dummy', 'card'=>card}
        PrivateCardGamesTest.submit(h, runners, actor, selection)
      end
      played << card
      trick << [seat, card]
      if trick.size == 4
        suit = trick.first.last[-1]
        winner = trick.select { |_, value| value[-1] == suit }.max_by { |_, value| '23456789TJQKA'.index(value[0]) }.first
        winners[winner % 2] += 1
        trick = []
      end
      4.times do
        break unless h.replay('Alice').state[:phase] == :private_show
        PrivateCardGamesTest.tick(h, runners)
      end
    end
    assert(played.uniq.size == 52, 'a native card was played twice or a card was omitted')
    assert(h.replay('Alice').state[:tricks_won] == winners, 'normal trick result differs from independent oracle')
    assert(!cheat || cheated, 'second-board fixture did not include a real revoke')
  end
end

%w[rubber imp mp].each do |variant|
  game = GameRoomGames::Bridge.new
  options = {'team_seats'=>[0, 0, 1, 1], 'honors'=>false}
  options.merge!('variant'=>'duplicate', 'boards'=>4, 'scoring'=>variant) unless variant == 'rubber'
  h, runners = PrivateCardGamesTest.create(game, users:%w[Alice Bob Carol Dave], options:options,
    clock: ClockEventContract::ManualTime.new)
  begin
    assert(h.replay('Alice').state[:seats] == %w[Alice Carol Bob Dave], 'explicit partnership was not honored')
    original = h.users.to_h { |user| [user, h.replay(user).state[:hands][user].dup] }
    BridgeBoardContinuity.auction(h, runners, bid:'7N')
    BridgeBoardContinuity.play_board(h, runners)
    first = h.replay('Alice')
    assert(first.state[:phase] == :round_complete && first.state[:deals].size == 1, 'first actual board did not score')
    assert(first.state[:scores].values.any?(&:positive?), 'fixture has no existing score to protect')
    prior = Marshal.load(Marshal.dump(first.state.slice(:scores, :rubber, :deals)))
    score_history = first.history.select { |entry| [:score, :result].include?(entry.kind) }.map(&:to_h)
    assert(first.state[:initial_hands].map(&:sort) == first.state[:seats].map { |user| original[user].sort }, 'first audited card ownership differs')

    h.add_client('Watcher')
    assert(h.join('Watcher'), 'observer could not join')
    h.as('Watcher') { h.transports['Watcher'].set_observer(h.table, true, actor:'Watcher') }
    h.view('Alice').transfer_ownership(h.view('Alice').participants.find { |person| person.user == 'Watcher' })
    runners['Watcher'] = runner_for(h, 'Watcher')
    16.times { PrivateCardGamesTest.tick(h, runners) }
    second = h.replay('Alice')
    assert(second.state[:round] == 2 && second.state[:phase] == :bidding, 'new spectator host did not deal second board')
    assert(second.state[:initial_hands].all?(&:empty?) && !second.state[:dummy_visible], 'first board private projection leaked into second')
    PrivateCardGamesTest.assert_private(h)
    assert(h.view('Watcher').pools.size <= 1, 'completed native pool was not retired')

    own = h.replay('Carol').state[:hands]['Carol'].dup
    draws = h.core.entries.count { |entry| entry.dig('pool', 'operation') == 'take' }
    runners['Carol'].close
    h.view('Carol').leave
    h.add_client('Carol')
    assert(h.join('Carol'), 'returning owner could not join')
    runners['Carol'] = runner_for(h, 'Carol')
    PrivateCardGamesTest.tick(h, runners)
    assert(h.replay('Carol').state[:hands]['Carol'] == own, 'return lost current private cards')
    assert(h.core.entries.count { |entry| entry.dig('pool', 'operation') == 'take' } == draws, 'return redrew a hand')
    BridgeBoardContinuity.auction(h, runners)
    BridgeBoardContinuity.play_board(h, runners, cheat:true)
    h.users.each do |user|
      replay = h.replay(user)
      assert(replay.state[:private_error] == :invalid_round, 'second-board revoke did not fail closed')
      assert(replay.state.slice(:scores, :rubber, :deals) == prior, 'failed second board damaged previous points/rubber/deals')
      assert(replay.history.select { |entry| [:score, :result].include?(entry.kind) }.map(&:to_h) == score_history,
        'failed second board published a score or changed old score history')
      assert(!replay.finished?, 'failed board created a tournament result')
    end
    puts "PASS Bridge independent #{variant}: actual scored board, explicit partnerships, spectator host, cold return, second-board revoke preserves prior result"
  ensure
    runners.each_value(&:close)
  end
end
