require_relative '../../support/private_card_games'
require_relative '../../../games/poker'
require_relative '../../support/elten_array_shuffle'

game=GameRoomGames::Poker.new
%w[draw holdem].each do |variant|
  h,runners=PrivateCardGamesTest.create(game,users:%w[Alice Bob Carol Dave],options:{'deck'=>'nine','variant'=>variant})
  exchanges=0
  begin
    100.times do
      replay=h.replay('Alice')
      break if [:hand_complete,:finished].include?(replay.state[:phase])
      if replay.state[:phase].to_s.start_with?('private_') || game.send(:private_waiting?,replay.state)
        PrivateCardGamesTest.tick(h,runners)
        next
      end
      actor=replay.current_player
      mine=h.replay(actor)
      assert(mine.state[:hands][actor].all? { |card| %w[9 T J Q K A].include?(card[0]) },'Private short deck contains a low card')
      actions=game.legal_actions(mine,actor)
      if mine.state[:phase]==:exchange
        cards=mine.state[:hands][actor].first(3)
        action={'kind'=>'card_packet','action'=>'exchange','cards'=>JSON.generate(cards)}
        exchanges+=1
      else
        action=actions.find { |a| %w[check call].include?(a['action']) }
      end
      assert(action,'Missing short-deck native action')
      PrivateCardGamesTest.submit(h,runners,actor,action)
      PrivateCardGamesTest.tick(h,runners)
    end
    replay=h.replay('Alice')
    assert([:hand_complete,:finished].include?(replay.state[:phase]),'Native short-deck hand stalled')
    all=replay.state[:hands].values.flatten+replay.state[:community]
    assert(all.all? { |card| %w[9 T J Q K A].include?(card[0]) },'Short-deck showdown contains low cards')
    assert_equal(4,exchanges,'Four three-card exchanges did not complete') if variant=='draw'
    assert(replay.state[:recycle]>0,'Short deck did not exercise discard recycling') if variant=='draw'
    assert_equal(h.events('Alice').size,replay.accepted_events.size,'Native short deck rejected an accepted write')
  ensure
    runners.each_value(&:close)
  end
end
puts 'Native short-deck Poker: private deals, both variants, four exchanges, recycling, showdown, server entropy and ELTEN shuffle API passed.'
