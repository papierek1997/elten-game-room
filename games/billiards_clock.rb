require_relative '../lib/game_session_clock'

module GameRoomGames
  class Billiards
    def timed_billiards?(state)
      state[:options]['discipline'] == 'english' && state[:options]['english_limit'] == 'time'
    end

    def automatic_action(replay, actor, context: nil)
      state = replay.state
      return nil if replay.finished? || !timed_billiards?(state) || !same_user?(actor, replay.players.first)
      return nil unless state[:phase] == :playing
      action = state[:english_started_at].nil? ? 'clock_start' : (billiards_time_due?(state, context&.now) ? 'time' : nil)
      {'kind'=>'billiards', 'action'=>action, 'revision'=>state[:revision]} if action
    end

    def automatic_action_due?(replay, actor, context: nil)
      !automatic_action(replay, actor, context: context).nil?
    end

    def billiards_time_due?(state, now)
      started = state[:english_started_at]
      started && now && now >= started + state[:options]['time_limit_minutes'] * 60
    end

    def clock_action_for(selection, replay, actor, context)
      state, action = replay.state, selection['action']
      return [:invalid, nil] unless selection['kind'] == 'billiards' && timed_billiards?(state) && same_user?(actor, replay.players.first) &&
        valid_action?(action, selection.reject { |k, _| %w[kind action source].include?(k.to_s) }, state, replay.players.length)
      return [:invalid, nil] if action == 'time' && !billiards_time_due?(state, context&.now)
      value = JSON.generate([1, state[:revision]])
      return [:invalid, nil] if value.bytesize > 64
      [:ok, event_plan(action, value)]
    end

    # A native accepted shot begins at this boundary. Its entire simulation
    # settles before the existing executor can write the expiry transition.
    def timed_event_allowed?(state, action, time)
      return true unless timed_billiards?(state)
      return false unless time.is_a?(Integer) && time > 0
      return true if state[:phase] == :rack_end && action == 'choice'
      return state[:english_started_at].nil? if action == 'clock_start'
      return !!billiards_time_due?(state, time) if action == 'time'
      !!state[:english_started_at] && !billiards_time_due?(state, time)
    end

    def apply_clock_event(state, action, time)
      if action == 'clock_start'
        state[:english_started_at] = time
      else
        B::EnglishBilliards.expire(state, elapsed_ms: (time - state[:english_started_at]) * 1000)
      end
    end
  end
end
