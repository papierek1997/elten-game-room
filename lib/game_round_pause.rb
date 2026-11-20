require_relative 'game_session_clock'

# Scheduling only: accepted histories and the games' scoring rules stay intact.
# The existing session executor checks this clock before making any next-round
# plan, including a native private deal. No request or second timer is needed.
class GameRoomRoundPause
  SECONDS = 5

  def initialize(repository)
    @repository = repository
  end

  def active?(game:, replay:, session:, now:)
    return false unless replay && !replay.finished? && game.round_pause_seconds(replay).positive?
    return false if session['__round_pause_released'] == true
    key = [session['created_at'], session['__server_started_at'], session['__clock_offset']]
    unless @game.equal?(game) && @replay.equal?(replay) && @clock_key == key
      @game, @replay, @clock_key = game, replay, key
      @deadline = deadline(game, replay, session)
    end
    @deadline != nil && now.to_f < @deadline
  end

  private

  def deadline(game, replay, session)
    state = replay.state
    supplied = game.round_pause_deadline(replay)
    return supplied if supplied && supplied.positive?
    event = replay.accepted_events.last
    return nil unless event
    event_id = @repository.event_id(event)
    # Only the event which actually settles the round starts a break. A bet,
    # commitment or private-pool preparation in the next round must not start
    # another break, even when the model has already reset its round fields.
    kinds = game.round_pause_end_kinds
    settled = replay.history.reverse_each.any? do |entry|
      break false unless entry.event_id == event_id
      kinds.include?(entry.kind)
    end
    settled ||= state[:phase] == :round_complete || state[:phase] == :hand_complete
    return nil unless settled
    return nil unless GameRoomSessionClock.valid_event_time?(event['created_at']) ||
      GameRoomSessionClock.valid_event_time?(event['__game_time'])
    completed_at = GameRoomSessionClock.from_server(session, event['created_at'], event: event)
    completed_at + game.round_pause_seconds(replay) if completed_at
  end
end
