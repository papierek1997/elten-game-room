require_relative '../participant_decision_events'
require_relative 'scoring'

module BouillabaissePlanning
  module Information
    module_function

    def observation(game, replay, actor)
      state = replay.state
      actor = state[:seats].find { |player| player.casecmp?(actor.to_s) } || actor
      deck = state[:round_deck].to_a
      points = deck.to_h { |card| [card, game.penalty_value(card, state[:round], state[:penalties])] }
      taken = state[:taken].to_h
      trick_points = Scoring.trick_points(state[:round])
      played = taken.values.flatten + state[:trick].to_a.map(&:last)
      plays = public_plays(replay, state[:seats])
      plays = [] if plays.map(&:last).sort != played.sort
      {
        'hand' => game.send(:hand_for, state, actor).dup,
        'trick' => state[:trick].to_a.map(&:dup), 'round' => state[:round],
        'penalties' => state[:penalties].to_h.dup, 'seats' => state[:seats].dup, 'actor' => actor,
        'deck' => deck.dup, 'card_points' => points, 'plays' => plays, 'played_cards' => played,
        'counts' => state[:hands].transform_values(&:size), 'scores' => state[:scores].dup,
        'captured_points' => state[:seats].to_h do |player|
          [player, taken.fetch(player, []).sum { |card| points.fetch(card) } +
            state[:tricks].to_h.fetch(player, 0) * trick_points]
        end,
        'all_or_nothing' => state[:options].fetch('all_or_nothing', true)
      }
    end

    def public_plays(replay, seats)
      names = seats.to_h { |player| [player.downcase, player] }
      plays = []
      GameRoomParticipantDecisionEvents.for(replay).to_a.reverse_each do |event|
        break if event['action'] == 'deal'
        next unless event['action'] == 'play'

        player = names[event.fetch('__replay_actor', event['actor']).to_s.downcase]
        # Drop void deductions if a projection lacks an attributable move;
        # shifting trick boundaries would invent false information.
        return [] unless player

        plays << [player, event['value'].to_s]
      end
      plays.reverse
    end

    def void_suits(observation)
      voids = observation.fetch('seats').to_h { |player| [player, []] }
      observation.fetch('plays').each_slice(voids.size) do |trick|
        led = trick.first.last[1]
        trick.each { |player, card| voids.fetch(player) << led if card[1] != led && !voids.fetch(player).include?(led) }
      end
      voids
    end
  end
end
