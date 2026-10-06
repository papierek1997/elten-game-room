require_relative 'game_event_presentation'
require_relative 'presentation_replay'
require_relative 'game_background_policy'
require_relative 'game_sounds'

# UI-owned presentation state shared by visible and covered sessions. The
# worker hands over copied replays; this object never touches a form or input.
class GameRoomEventPresenter
  attr_accessor :event_presentation, :last_seen_event_id, :last_seen_activity_id,
    :turn_history_entries, :spoken_timer_announcements, :decision_presentation_started
  attr_reader :presentation_session_id

  def initialize(game:, repository:, program:, viewer:, client:, surface_state:,
    clock:, covered:, speech:, trace:, history_changed:, session_changed:)
    @game, @repository, @program, @viewer = game, repository, program, viewer
    @client, @surface_state, @clock, @covered = client, surface_state, clock, covered
    @speech, @trace = speech, trace
    @history_changed, @session_changed = history_changed, session_changed
    @turn_history_entries, @spoken_timer_announcements = {}, {}
  end

  def process_table_activity(entries, viewer:, text:)
    newest_id = entries.to_a.map(&:id).max.to_i
    if @last_seen_activity_id == nil
      @last_seen_activity_id = newest_id
      return false
    end
    fresh = entries.to_a.select { |entry| entry.id.to_i > @last_seen_activity_id.to_i }
    fresh.each do |entry|
      next if entry.kind == 'chat' && GameRoomParticipants.same?(entry.actor, viewer)
      GameRoomSounds.table_activity(@program.call, entry, viewer: viewer)
      message = text.call(entry)
      @speech.call(message) unless message.to_s.empty?
    end
    @last_seen_activity_id = [@last_seen_activity_id.to_i, newest_id].max
    !fresh.empty?
  end

  def event_presentation_busy?
    @event_presentation != nil && @event_presentation.busy?
  end

  def prepare_presentation_session(session, background: false)
    id = (session["__id"] || session["id"]).to_i
    return true if @presentation_session_id == id
    # Native IDs are random, not an ordering clock. A suspended foreground
    # replay may still refer to a match already replaced by the background UI.
    @retired_presentation_sessions ||= {}
    return false if @retired_presentation_sessions[id]
    if @presentation_session_id
      @retired_presentation_sessions[@presentation_session_id] = true
      @event_presentation&.close
      @event_presentation = nil
      @last_seen_event_id = background ? 0 : nil
      @turn_history_entries = {}
      @spoken_timer_announcements = {}
      @session_changed.call
    end
    @presentation_session_id = id
    @decision_presentation_started = false
    true
  end

  def process_new_events(replay, signal_received_at: nil, session:, background: false)
    return unless prepare_presentation_session(session, background: background)
    newest_id = replay.accepted_events.map { |event| @repository.call.event_id(event) }.max.to_i
    if @last_seen_event_id == nil
      @last_seen_event_id = newest_id
      presentation_replay.remember(session, replay)
      @history_changed.call(replay, true) unless background
      present_initial_decision(replay)
      return
    end

    new_events = replay.accepted_events.select do |event|
      @repository.call.event_id(event) > @last_seen_event_id
    end
    event_replays = event_replays_for(replay, new_events, session: session)
    # Reconnection can deliver several already completed turns together.
    # Alert only for a decision still pending in the latest state, once per
    # batch; a delayed sound sequence must not announce an obsolete turn.
    decision_key = @game.call.required_decision_key(replay, @viewer.call)
    decision_new = !@decision_presentation_started || event_replays.values.any? do |before, after|
      decision_key && @game.call.required_decision_key(after, @viewer.call) == decision_key &&
        @game.call.required_decision_key(before, @viewer.call) != decision_key
    end
    @decision_presentation_started = true
    decision_boundary = @decision_boundary = [@presentation_session_id, newest_id]
    present_decision = lambda do
      if decision_new && decision_boundary == @decision_boundary
        present_required_decision(nil, replay)
      end
    end
    if !new_events.empty? && @game.call.respond_to?(:serial_event_presentation?) && @game.call.serial_event_presentation?
      first_before = event_replays[@repository.call.event_id(new_events.first)]&.first
      @event_presentation ||= GameRoomEventPresentation.new(clock: -> { @clock.call }, initial_replay: first_before)
    end
    new_events.each do |event|
      event_id = @repository.call.event_id(event)

      before_replay, after_replay = event_replays.fetch(event_id, [nil, replay])
      turn_entry = remember_turn_transition(before_replay, after_replay, event_id)
      if @event_presentation != nil
        @event_presentation.enqueue(
          replay: after_replay, defer_replay: after_replay.finished?,
          start: -> { present_game_event(event, before_replay, after_replay, after_replay, signal_received_at) },
          finish: -> do
            present_decision.call if event_id == newest_id
            present_turn_transition(turn_entry, after_replay)
            present_game_result(after_replay, signal_received_at) if event_id == newest_id
          end
        )
      else
        present_game_event(event, before_replay, after_replay, replay, signal_received_at)
        present_turn_transition(turn_entry, after_replay)
      end
    end
    merge_turn_history!(replay)
    if newest_id > @last_seen_event_id
      present_game_result(replay, signal_received_at) if @event_presentation == nil
      @history_changed.call(replay, false) unless background
    end
    @last_seen_event_id = [@last_seen_event_id, newest_id].max
    present_decision.call if @event_presentation == nil || new_events.empty? && !event_presentation_busy?
    @event_presentation&.advance
  end

  def present_game_event(event, before_replay, after_replay, description_replay, signal_received_at)
    @client.call&.event(event, before_replay, after_replay, @viewer.call, @repository.call)
    sounds = begin
      cues = GameRoomSounds.event_cue(
        game: @game.call, event: event, before_replay: before_replay, after_replay: after_replay,
        repository: @repository.call, viewer: @viewer.call
      )
      Array(cues).map { |cue| GameRoomSounds.play(@program.call, cue) }
    rescue StandardError => error
      Log.warning("ELTEN Game Room event sound failed: #{error.class}: #{error.message}") if defined?(Log)
      []
    end
    descriptions = normalize_event_descriptions(
      @game.call.describe_event_for_display(event, @repository.call, description_replay, @viewer.call, surface_state: @surface_state.call)
    )
    descriptions = [] if @client.call&.respond_to?(:presents_game_event?) && @client.call.presents_game_event?(event)
    # The result remains in canonical history, but the common result presenter
    # owns its automatic announcement (also after serialized sound playback).
    result = @game.call.result_text(after_replay) if after_replay != nil
    descriptions = descriptions.reject { |text| GameRoomContent.utf8(text) == GameRoomContent.utf8(result) } if result != nil
    descriptions.each_with_index do |description, index|
      @trace.call("speech_queued", signal_received_at,
        details: "event_id=#{@repository.call.event_id(event)} item=#{index + 1}/#{descriptions.length}")
      @speech.call(description)
    end
    sounds
  end

  def present_turn_transition(turn_entry, replay)
    return if turn_entry == nil

    message = @game.call.turn_announcement(replay, @viewer.call)
    @speech.call(message) if !message.to_s.empty?
  end

  def present_initial_decision(replay)
    return if @decision_presentation_started
    @decision_presentation_started = true
    present_required_decision(nil, replay)
  end

  def present_required_decision(before_replay, after_replay)
    return unless @game.call.respond_to?(:required_decision_key)
    return unless GameRoomParticipants.includes?(after_replay.players, @viewer.call)
    key = @game.call.required_decision_key(after_replay, @viewer.call)
    return if key == nil || key == @game.call.required_decision_key(before_replay, @viewer.call)
    return unless GameRoomBackgroundPolicy.turn_sound?(@program.call, covered: @covered.call)
    GameRoomSounds.play(@program.call, "ding")
  end

  def present_game_result(replay, signal_received_at)
    return if @client.call&.respond_to?(:presents_game_result?) && @client.call.presents_game_result?(replay)
    result = @game.call.result_text(replay)
    return if result == nil

    @trace.call("result_speech_queued", signal_received_at)
    @speech.call(result)
  end

  def event_replays_for(replay, new_events, session:)
    presentation_replay.transitions(session, replay, new_events)
  rescue StandardError => error
    @presentation_replay = nil
    Log.warning("ELTEN Game Room could not reconstruct sound events: #{error.class}: #{error.message}; #{Array(error.backtrace).first}") if defined?(Log)
    {}
  end

  def presentation_replay
    @presentation_replay ||= GameRoomPresentationReplay.new(@game.call, @repository.call)
  end

  def remember_turn_transition(before_replay, after_replay, event_id)
    entry = @game.call.turn_transition_history_entry(
      before_replay,
      after_replay,
      event_id: event_id
    )
    @turn_history_entries[entry.event_id.to_i] = entry if entry != nil
    entry
  rescue StandardError => error
    Log.warning("ELTEN Game Room turn transition failed: #{error.class}: #{error.message}") if defined?(Log)
    nil
  end

  def merge_turn_history!(replay)
    return replay if replay == nil || @turn_history_entries.empty?

    source = replay.history.reject { |entry| entry.kind == :turn }
    pending = @turn_history_entries.dup
    pending_ids = pending.keys.sort
    pending_index = 0
    merged = []
    source.each_with_index do |entry, index|
      event_id = entry.event_id.to_i
      while pending_index < pending_ids.length && pending_ids[pending_index] < event_id
        pending_id = pending_ids[pending_index]
        merged << pending.delete(pending_id) if pending.key?(pending_id)
        pending_index += 1
      end

      merged << entry
      next_event_id = source[index + 1]&.event_id&.to_i
      if next_event_id != event_id && pending.key?(event_id)
        merged << pending.delete(event_id)
        pending_index += 1 if pending_ids[pending_index] == event_id
      end
    end
    while pending_index < pending_ids.length
      pending_id = pending_ids[pending_index]
      merged << pending[pending_id] if pending.key?(pending_id)
      pending_index += 1
    end
    replay.history = merged
    replay
  end

  def normalize_event_descriptions(description)
    Array(description).compact.map(&:to_s).reject(&:empty?)
  end

  def announce_due_timers(replay, now:)
    @game.call.timer_announcements(replay, @viewer.call, now: now).to_a.each do |announcement|
      key, message, sound = announcement.to_a
      next if key.to_s.empty? || (message.to_s.empty? && sound.to_s.empty?) || @spoken_timer_announcements[key.to_s]

      @spoken_timer_announcements[key.to_s] = true
      GameRoomSounds.play(@program.call, sound) unless sound.to_s.empty?
      @speech.call(message.to_s) unless message.to_s.empty?
    end
  rescue StandardError => error
    Log.warning("ELTEN Game Room timer announcement failed: #{error.class}: #{error.message}") if defined?(Log)
  end
end
