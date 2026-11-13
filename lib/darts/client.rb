# encoding: UTF-8
require_relative 'engine'
require_relative 'audio'
require_relative 'mouse'
require_relative '../realtime/progress'

require_relative '../game_room_localization'

module GameRoomDarts
  using GameRoomLocalization::Translations

  class Client
    FLIGHT_PAUSE = 1.0
    MAX_PRESENTATIONS = 32

    def initialize(program, game, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, mouse: nil, audio: nil,
      progress_factory: nil, **_services)
      @program, @game, @clock = program, game, clock
      @engine = Engine.new(clock: clock)
      @mouse = mouse || Mouse.new
      @audio = audio || Audio.new(program)
      @progress_factory = progress_factory || ->(**options, &block) { GameRoomRealtime::Progress.new(**options, &block) }
      @presentations = []
    end

    def _(source); GameRoomContent.utf8(super(source)); end

    def bind_screen(session_id:, table_id:, owner:, viewer:, members:)
      @session_id, @table_id, @viewer = session_id, table_id, viewer.to_s
    end

    def start
      return false if @closed
      @audio.load
      @progress ||= @progress_factory.call(program: @program, clock: @clock,
        key: [:darts, @table_id, @session_id, @viewer]) { |background| frame(background: background) }
      true
    end

    def background_progress?; true; end
    def refresh_due?; false; end
    def action(_selection, _replay, _viewer); false; end
    def error(_status); end
    def event(event, before, after, viewer, repository)
      match = GameRoomGames::Darts::THROW_PATTERN.match(event['value'].to_s)
      return unless event['action'].to_s == 'darts_throw' && match

      x, y = match[2].to_i, match[3].to_i
      now = @clock.call.to_f
      local = @local_throw && @local_throw[:value] == event['value'].to_s
      impact_at = if local
        [@local_throw[:impact_at], now].max
      else
        now + @audio.throw_dart.to_f + FLIGHT_PAUSE
      end
      terminal = terminal_result(before, after, viewer)
      descriptions = Array(@game.describe_event(event, repository, after, viewer)).compact
      result_text = @game.result_text(after) if terminal
      schedule_presentation({kind: :impact, due: impact_at, points: Scoring.points(x, y), x: x, y: y,
        descriptions: descriptions, result: terminal, result_text: result_text})
      @owned_result_index = after.state[:throw_index].to_i if terminal
      @local_throw = nil if local
    end
    def presents_game_event?(event); event['action'].to_s == 'darts_throw'; end
    def presents_game_result?(replay)
      replay.finished? && @owned_result_index == replay.state[:throw_index].to_i
    end
    def after_events(replay, viewer, context:); before_wait(replay, viewer); end

    def automatic_error(_status)
      @pending = nil
      @aim_identity = nil
      @local_throw = nil
    end

    def context_data
      @pending ? {'darts_throw' => @pending} : {}
    end

    def before_wait(replay, viewer)
      @viewer ||= viewer.to_s
      @replay = replay
      if @pending && pending_index(@pending) < replay.state[:throw_index].to_i
        @pending = nil
      end
      prepare_aim
    end

    def attach_view(form, surface)
      detach_view
      return unless surface.is_a?(GameSurfaces::DartsSurface)
      @form, @surface = form, surface
      @surface.on_darts_command = method(:command)
      @progress.attach(form)
    end

    def detach_view
      @progress&.detach
      @surface.on_darts_command = nil if @surface
      @surface&.clear_input
      @mouse.suspend
      @form = @surface = nil
    end

    def tick
      @progress ? @progress.update : frame
    end

    def frame(background: false)
      return if @closed
      now = @clock.call.to_f
      presentation_was_pending = !@presentations.empty?
      process_presentations(now)
      prepare_aim if presentation_was_pending && @presentations.empty?
      return unless active_aim?
      @engine.step(now)
      if @engine.ready?(now) && !@ready_announced
        @ready_announced = true
        @audio.ready
      end

      selected = !background && @form && @surface && @surface.input_active?(@form)
      commands = selected ? @surface.input(@form) : []
      mouse_commands, clicked = if @replay.state[:options]['mouse_input']
        @mouse.sample(active: selected)
      else
        @mouse.suspend
      end
      (commands + mouse_commands).each do |command|
        if command == :throw
          finish_throw(now, automatic: false)
        else
          moved = move(command, now)
          announce_training_position if moved && training?
        end
      end
      finish_throw(now, automatic: false) if clicked
      finish_throw(now, automatic: true) if @pending == nil && @engine.timed_out?(now)
      present_audio
    end

    def close
      return if @closed
      @closed = true
      @progress&.close
      detach_view
      @presentations.clear
      @audio.close
    end

    private

    def prepare_aim
      active = @replay && !@replay.finished? && @replay.state[:phase] != :opening &&
        @replay.current_player.to_s.casecmp?(@viewer) && !GameRoomParticipants.bot?(@replay.current_player) &&
        @pending == nil && @presentations.empty?
      unless active
        @aim_identity = nil
        @mouse.suspend
        @audio.silence
        return
      end

      difficulty = active_difficulty(@replay.state)
      identity = [@replay.state[:throw_index], @replay.current_player.to_s.downcase, difficulty]
      if @aim_identity != identity && @pending == nil
        @aim_identity = identity
        @ready_announced = false
        @engine.reset(seed: @replay.state[:seed], throw_index: @replay.state[:throw_index], difficulty: difficulty,
          time_limit: @replay.state[:options]['time_limit'], timeout_result: @replay.state[:options]['timeout_result'])
      end
      present_audio
    end

    def active_aim?
      @replay && @aim_identity && @pending == nil && !@replay.finished?
    end

    def move(command, now)
      dx, dy = case command
      when :left then [-1, 0]
      when :right then [1, 0]
      when :up then [0, 1]
      when :down then [0, -1]
      else return false
      end
      @engine.nudge(dx, dy, now)
    end

    def finish_throw(now, automatic:)
      return false unless @pending == nil
      result = @engine.finish(now, automatic: automatic)
      return false unless result
      @pending = [result[:index], result[:x], result[:y], result[:time_ms], result[:automatic] ? 'a' : 'm'].join(':')
      @mouse.suspend
      @audio.silence
      @local_throw = {value: @pending, impact_at: now.to_f + @audio.throw_dart.to_f + FLIGHT_PAUSE}
      true
    end

    def schedule_presentation(item)
      @presentations.shift while @presentations.length >= MAX_PRESENTATIONS
      @presentations << item
    end

    def process_presentations(now)
      due, @presentations = @presentations.partition { |item| item[:due] <= now }
      due.sort_by { |item| item[:due] }.each do |item|
        if item[:kind] == :impact
          tail = @audio.impact(item[:points], x: item[:x], y: item[:y]).to_f
          schedule_presentation(item.merge(kind: :announcement, due: now + tail))
        else
          @audio.result(won: item[:result] == :win) if [:win, :loss].include?(item[:result])
          (item[:descriptions].to_a + [item[:result_text]].compact).each do |text|
            speak(GameRoomContent.utf8(text.to_s), stop: false, break_sequence: false) unless text.to_s.empty?
          end
        end
      end
    end

    def terminal_result(before, after, viewer)
      return nil unless before && after && !before.finished? && after.finished?
      return :observer unless GameRoomParticipants.includes?(after.players, viewer)

      GameRoomParticipants.same?(after.winner, viewer) ? :win : :loss
    end

    def present_audio
      return @audio.silence unless active_aim?
      @audio.update(*@engine.position, active: true)
    end

    def training?
      @replay.state[:options]['mode'] == 'training'
    end

    def announce_training_position
      x, y = @engine.position.map(&:round)
      speak(@game.training_position_text(x, y), stop: false, break_sequence: false)
    end

    def command(name)
      announce_training_position if name.to_s == 'position' && training? && active_aim?
    end

    def active_difficulty(state)
      return state[:options]['difficulty'] unless state[:options]['progressive']
      rounds = state[:options]['rounds'].to_i
      progress = (state[:round].to_i - 1).to_f / [rounds, 1].max
      return 'easy' if progress < 1.0 / 3
      return 'normal' if progress < 2.0 / 3
      'hard'
    end

    def pending_index(value)
      value.to_s.split(':', 2).first.to_i
    end
  end
end
