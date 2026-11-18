require_relative "../games/base"
require_relative "game_snapshot"

# Presentation owns its copies: clients, turn-history merging and incremental
# reducers must never mutate the canonical model or the next cached prefix.
class GameRoomPresentationReplay
  def initialize(game, repository, raw_input: nil)
    @game, @repository, @raw_input = game, repository, raw_input
  end

  def bind_source(session, replay, raw)
    bind_input(replay, GameRoomSnapshot.copy(session), owned_events(raw), raw.length)
    replay
  end

  def remember(session, replay)
    session = replay.presentation_session || session
    if !replay.presentation_events && (raw = @raw_input&.call(session))
      bind_input(replay, GameRoomSnapshot.copy(session), owned_events(raw), raw.length)
    end
    key = session_key(session)
    @session_key, @previous = key, key && copy(replay)
  end

  def transitions(session, replay, new_events)
    return {} if new_events.empty?
    events = replay.accepted_events
    first_index = events.index(new_events.first)
    raise ArgumentError, "Presentation events must be a suffix of accepted events" unless first_index && events[first_index..] == new_events
    session = replay.presentation_session || session
    raw = replay.presentation_events || @raw_input&.call(session)
    if replay.presentation_events && replay.presentation_event_count && replay.presentation_event_count < raw.length
      raw = GameRoomSnapshot::Log.from_sealed(raw.take(replay.presentation_event_count), bytes: raw.retained_bytes)
    end
    if raw
      raw = owned_events(raw)
      session = GameRoomSnapshot.copy(session)
      bind_input(replay, session, raw, raw.length)
    end
    return authenticated_transitions(session, replay, new_events, raw) if raw && raw != events
    prefix = events.take(first_index)
    key = session_key(session)
    before = if @previous && @session_key == key && @previous.accepted_events == prefix
      copy(@previous)
    else
      nil
    end
    before ||= @game.replay(session, prefix, @repository)
    bind_input(before, session, raw, first_index) if raw
    result = {}
    new_events.each_with_index do |event, index|
      prefix << event
      # The executor has already validated the final state. Reuse a copy of
      # that state, but still reconstruct EVERY intermediate transition.
      after = index == new_events.length - 1 ? copy(replay) : incremental(before, session, event)
      after ||= @game.replay(session, prefix, @repository)
      bind_input(after, session, raw, prefix.length) if raw
      result[@repository.event_id(event)] = [before, after]
      before = after
    end
    remember(session, replay)
    result
  end

  private

  def authenticated_transitions(session, replay, new_events, raw)
    result = {}
    new_events.each_with_index do |event, index|
      position = raw.index { |row| @repository.event_id(row) == @repository.event_id(event) && row == event }
      raise ArgumentError, 'Missing authenticated presentation event' unless position
      before = @game.replay(session, raw.take(position), @repository)
      after = index == new_events.length - 1 ? copy(replay) : @game.replay(session, raw.take(position + 1), @repository)
      bind_input(before, session, raw, position)
      bind_input(after, session, raw, index == new_events.length - 1 ? raw.length : position + 1)
      expected = replay.accepted_events.take_while { |row| @repository.event_id(row) <= @repository.event_id(event) }
      raise ArgumentError, 'Changed authenticated presentation prefix' unless after.accepted_events == expected
      result[@repository.event_id(event)] = [before, after]
    end
    remember(session, replay)
    result
  end

  def incremental(before, session, event)
    return nil if @game.method(:incremental_replay).owner == GameRoomGames::Base
    # Historical actors/values belong to their event-time seats. Only full
    # replay applies that mapping and preserves the original history names.
    # Later moves already use the current roster and keep the fast path.
    last_change = session.fetch('__seat_changes', []).last
    return nil if last_change && @repository.event_id(event) <= last_change.fetch('id')
    isolated = copy(before)
    @game.incremental_replay(isolated, session, [event], @repository) if isolated
  rescue StandardError => error
    # The fallback is deliberate, but an implementation error must be visible.
    Log.warning("ELTEN Game Room incremental presentation failed: #{error.class}: #{error.message}; #{Array(error.backtrace).first}") if defined?(Log)
    nil
  end

  def owned_events(raw)
    return raw if raw.is_a?(GameRoomSnapshot::Log) && raw.frozen?
    GameRoomSnapshot::Log.from_owned(GameRoomSnapshot.copy(raw))
  end

  def bind_input(replay, session, events, count)
    replay.presentation_session = session
    replay.presentation_events = events
    replay.presentation_event_count = count
  end

  def copy(value)
    GameRoomSnapshot.copy(value)
  rescue TypeError
    # A future game can still use full reconstruction if its presentation
    # contains an object that cannot be copied. Never share a mutable model.
    nil
  end

  def session_key(session)
    # The write-CAS token changes with every action. The exact accepted-event
    # prefix already guards that history; keep all semantic session metadata.
    Marshal.dump(session.reject { |key, _value| key == '__game_revision' })
  rescue TypeError
    nil
  end
end
