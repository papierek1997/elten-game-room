require_relative 'game_session_clock'
require_relative 'game_room_localization'

# Read-only, on-demand projection of the existing logical game clock. No timer,
# replay reduction, file access, network request or new persisted state.
module GameRoomDuration
  using GameRoomLocalization::Translations
  module_function

  def text(scope, game:, replay:, session:, repository:, now:)
    return _('Duration is unavailable.') unless session && replay

    first, last = scope == 'round' ? game.round_timing_event_ids(replay, repository: repository) : [nil, nil]
    started = first ? event_time(first, replay, session, repository) : session['created_at']
    ended = if last
      event_time(last, replay, session, repository)
    elsif replay.finished?
      event_time(repository.event_id(replay.accepted_events.last), replay, session, repository) unless replay.accepted_events.empty?
    else
      now
    end
    return _('Duration is unavailable.') unless valid?(started) && valid?(ended)

    duration = format_seconds([ended.to_i - started.to_i, 0].max)
    (scope == 'round' ? _('Round duration: %{duration}.') : _('Game duration: %{duration}.')) % {duration: duration}
  end

  def event_time(id, replay, session, repository)
    event = replay.accepted_events.reverse_each.find { |item| repository.event_id(item) == id }
    return unless event
    return event['__game_time'] if GameRoomSessionClock.valid_event_time?(event['__game_time'])
    timestamp = event['created_at']
    GameRoomSessionClock.from_server(session, timestamp, event: event) if GameRoomSessionClock.valid_event_time?(timestamp)
  end

  def valid?(value)
    value.is_a?(Numeric) && value.finite? && value.positive?
  end

  def format_seconds(seconds)
    hours, rest = seconds.divmod(3600)
    minutes, seconds = rest.divmod(60)
    parts = []
    parts << (n_('%{count} hour', '%{count} hours', hours) % {count: hours}) if hours.positive?
    parts << (n_('%{count} minute', '%{count} minutes', minutes) % {count: minutes}) if minutes.positive?
    parts << (n_('%{seconds} second', '%{seconds} seconds', seconds) % {seconds: seconds}) if seconds.positive? || parts.empty?
    parts.join(', ')
  end
end
