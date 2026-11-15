require_relative "../games/base"
require_relative "game_snapshot"

# Presentation owns its copies: clients, turn-history merging and incremental
# reducers must never mutate the canonical model or the next cached prefix.
class GameRoomPresentationReplay
  def initialize(game, repository)
    @game, @repository = game, repository
  end

  def remember(session, replay)
    key = session_key(session)
    @session_key, @previous = key, key && copy(replay)
  end

  def transitions(session, replay, new_events)
    return {} if new_events.empty?
    events = replay.accepted_events
    first_index = events.index(new_events.first)
    raise ArgumentError, "Presentation events must be a suffix of accepted events" unless first_index && events[first_index..] == new_events
    prefix = events.take(first_index)
    key = session_key(session)
    before = if @previous && @session_key == key && @previous.accepted_events == prefix
      copy(@previous)
    else
      nil
    end
    before ||= @game.replay(session, prefix, @repository)
    result = {}
    new_events.each_with_index do |event, index|
      prefix << event
      # The executor has already validated the final state. Reuse a copy of
      # that state, but still reconstruct EVERY intermediate transition.
      after = index == new_events.length - 1 ? copy(replay) : incremental(before, session, event)
      after ||= @game.replay(session, prefix, @repository)
      result[@repository.event_id(event)] = [before, after]
      before = after
    end
    remember(session, replay)
    result
  end

  private

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
