require_relative '../../lib/game_room_localization'

module GameRoomGames
  using GameRoomLocalization::Translations
  class Monopoly
    module Auction
      private

      def apply_auction(state, event, actor, repository, history, timed_out: false)
        return false if state[:phase] != :auction || !same_user?(state[:current_player], actor)
        player = player_key(state, actor)
        if event["action"] == "auction_bid"
          amount_text, timestamp_text = event["value"].to_s.split("|", 2)
          amount = Integer(amount_text, 10)
          return false if amount <= state[:auction_bid] || amount > state[:cash][player]
          state[:auction_bid] = amount
          state[:auction_leader] = player
          text = _("%{player} bids %{amount}.") % { player: participant_name(player), amount: amount }
        else
          timestamp_text = timed_out ? event["value"].to_s.split("|", 4).last : event["value"].to_s
          state[:auction_passed][player] = true
          text = (timed_out ? _("%{player} ran out of auction time and passes.") : _("%{player} passes in the auction.")) % { player: participant_name(player) }
        end
        history << HistoryEntry.new(key: "auction_action:#{repository.event_id(event)}", text: text, event_id: repository.event_id(event), actor: actor, kind: :game)
        candidates = active_players(state).reject { |candidate| state[:auction_passed][candidate] }
        if candidates.length <= 1 && state[:auction_leader] != nil
          winner = state[:auction_leader]
          state[:cash][winner] -= state[:auction_bid]
          state[:owners][state[:auction_square]] = winner
          history << HistoryEntry.new(key: "auction:#{repository.event_id(event)}", text: _("%{player} won the auction for %{property} at %{amount}.") % { player: participant_name(winner), property: property_name_and_group(state[:board][state[:auction_square]]), amount: state[:auction_bid] }, event_id: repository.event_id(event), actor: actor, kind: :game)
          state[:current_player] = player_key(state, state[:auction_origin]) || state[:auction_origin]
          state[:phase] = :turn_complete
        elsif candidates.empty?
          history << HistoryEntry.new(key: "auction:#{repository.event_id(event)}", text: _("Auction ended without a sale: %{property}.") % { property: property_name_and_group(state[:board][state[:auction_square]]) }, event_id: repository.event_id(event), actor: actor, kind: :game)
          state[:current_player] = player_key(state, state[:auction_origin]) || state[:auction_origin]
          state[:phase] = :turn_complete
        else
          state[:current_player] = next_auction_player(state, player)
        end
        set_auction_deadline(state, timestamp_text.to_i, repository.event_id(event))
        true
      rescue ArgumentError
        false
      end

      def auction_action_time(context, state)
        (context&.now || GameRoomSessionClock.for_state(state)).to_i
      end

      def set_auction_deadline(state, timestamp, event_id)
        duration = state[:options]["auction_decision_time"].to_i
        state[:auction_turn] = event_id
        state[:auction_deadline] = state[:phase] == :auction && duration > 0 && timestamp > 0 ? timestamp + duration : 0
      end

      def apply_auction_timeout(state, event, actor, repository, history)
        return false if !same_user?(actor, state[:players].first) || state[:phase] != :auction || state[:auction_deadline].to_i <= 0
        turn, index, deadline, timestamp = event["value"].to_s.split("|", 4).map { |value| Integer(value, 10) }
        return false if turn != state[:auction_turn].to_i || index != player_index(state[:players], state[:current_player]) || deadline != state[:auction_deadline] || timestamp == nil || timestamp < deadline
        apply_auction(state, event, state[:current_player], repository, history, timed_out: true)
      rescue ArgumentError, TypeError
        false
      end

      def next_auction_player(state, actor)
        candidate = next_active_player(state, actor)
        state[:players].length.times do
          return candidate if !state[:auction_passed][candidate]
          candidate = next_active_player(state, candidate)
        end
        candidate
      end

      def auction_increment(state)
        [money(state, 10), (state[:auction_bid] * 0.1).ceil].max
      end
    end

    include Auction
  end
end
