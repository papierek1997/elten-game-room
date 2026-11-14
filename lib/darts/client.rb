# encoding: UTF-8
require_relative 'engine'
require_relative 'audio'
require_relative 'mouse'
require_relative '../realtime/channel'
require_relative '../realtime/protocol'
require_relative '../realtime/progress'
require_relative '../realtime/table_control'

require_relative '../game_room_localization'

module GameRoomDarts
  using GameRoomLocalization::Translations

  class Client
    include GameRoomRealtime::TableControl

    FLIGHT_PAUSE = 0.5
    MAX_PRESENTATIONS = 32
    CURSOR_SEND_INTERVAL = 0.05
    CURSOR_TIMEOUT = 0.3

    class PresentationHandle
      def initialize; @finished = false; end
      def finished?; @finished; end
      def finish!; @finished = true; end
    end

    def initialize(program, game, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, mouse: nil, audio: nil,
      progress_factory: nil, channel_factory: nil, **_services)
      @program, @game, @clock = program, game, clock
      @engine = Engine.new(clock: clock)
      @mouse = mouse || Mouse.new
      @audio = audio || Audio.new(program)
      @progress_factory = progress_factory || ->(**options, &block) { GameRoomRealtime::Progress.new(**options, &block) }
      @channel_factory = channel_factory || ->(**options) { GameRoomRealtime::Channel.new(**options) }
      @presentations = []
      reset_cursor_network
    end

    def _(source); GameRoomContent.utf8(super(source)); end

    def bind_screen(session_id:, table_id:, owner:, viewer:, members:)
      @session_id, @table_id = session_id, table_id
      @owner, @viewer, @members_provider = owner.to_s, viewer.to_s, members
      @match = Digest::SHA256.hexdigest("GameRoom:darts:#{table_id}:#{session_id}")[0, 24]
      @base_match = @match
      @channel = @channel_factory.call(program: @program, match: @match, owner: @owner,
        viewer: @viewer, clock: @clock, members: members)
    end

    def start
      return false if @closed
      register_ping_channel if @channel
      @audio.load
      @progress ||= @progress_factory.call(program: @program, clock: @clock,
        key: [:darts, @table_id, @session_id, @viewer]) { |background| frame(background: background) }
      true
    end

    def host?; @owner.to_s.casecmp?(@viewer.to_s); end
    def background_progress?; true; end
    def refresh_due?; false; end
    def action(_selection, _replay, _viewer); false; end
    def error(_status); end
    def event(event, before, after, viewer, repository)
      match = GameRoomGames::Darts::THROW_PATTERN.match(event['value'].to_s)
      return unless event['action'].to_s == 'darts_throw' && match

      clear_remote_cursor
      x, y = match[2].to_i, match[3].to_i
      points = Scoring.points(x, y)
      now = @clock.call.to_f
      local = @local_throw && @local_throw[:value] == event['value'].to_s
      impact_at = if local
        [@local_throw[:impact_at], now].max
      else
        now + @audio.throw_dart.to_f + FLIGHT_PAUSE
      end
      terminal = terminal_result(before, after, viewer)
      descriptions = Array(@game.describe_event(event, repository, after, viewer)).compact
      if training_replay?(after)
        descriptions.unshift(points.positive? ? p_('Darts training', 'Hit') : p_('Darts training', 'Miss'))
      end
      prompt = next_throw_prompt(after, viewer)
      descriptions << prompt if prompt
      result_text = @game.result_text(after) if terminal
      handle = PresentationHandle.new
      schedule_presentation({kind: :impact, due: impact_at, points: points, x: x, y: y, handle: handle,
        descriptions: descriptions, result: terminal, result_text: result_text})
      @owned_result_index = after.state[:throw_index].to_i if terminal
      @local_throw = nil if local
      handle
    end
    def presents_game_event?(event); event['action'].to_s == 'darts_throw'; end
    def presents_game_result?(replay)
      replay.finished? && @owned_result_index == replay.state[:throw_index].to_i
    end
    def presentation_pending?; !@presentations.empty?; end
    def after_events(replay, viewer, context:); before_wait(replay, viewer); end

    def automatic_error(_status)
      @pending = nil
      @aim_identity = nil
      @awaiting_start_identity = nil
      @local_throw = nil
      clear_remote_cursor
    end

    def context_data
      @pending ? {'darts_throw' => @pending} : {}
    end

    def before_wait(replay, viewer)
      @viewer ||= viewer.to_s
      previous_identity = replay_cursor_identity(@replay)
      @replay = replay
      clear_remote_cursor if previous_identity != replay_cursor_identity(replay)
      if @pending && pending_index(@pending) < replay.state[:throw_index].to_i
        @pending = nil
      end
      synchronize_aim_state
      shutdown_cursor_network if replay.finished?
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
      synchronize_aim_state if presentation_was_pending && @presentations.empty?
      receive_cursor_network(now)

      selected = !background && !@settings_open && @form && @surface && @surface.input_active?(@form)
      commands = selected ? @surface.input(@form) : []
      mouse_commands, clicked = if @replay && @replay.state[:options]['mouse_input']
        @mouse.sample(active: selected)
      else
        @mouse.suspend
      end
      if awaiting_start?
        start_aim(now) if commands.include?(:throw) || clicked
        finish_cursor_frame(now)
        return
      end
      unless active_aim?
        finish_cursor_frame(now)
        return
      end

      @engine.step(now)
      present_board_edge
      present_training_sector
      if @engine.ready?(now) && !@ready_announced
        @ready_announced = true
        @audio.ready
        speak_training(p_('Darts training', 'Time starts'))
      end
      warning = @engine.deadline_warning(now)
      if warning && warning != @deadline_warning
        @deadline_warning = warning
        @audio.deadline_warning(warning)
        speak_training(warning.to_s)
      end
      (commands + mouse_commands).each do |command|
        if command == :throw
          finish_throw(now, automatic: false)
        else
          moved = move(command, now)
          if moved
            present_board_edge
            present_training_sector
          end
        end
      end
      finish_throw(now, automatic: false) if clicked
      finish_throw(now, automatic: true) if @pending == nil && @engine.timed_out?(now)
      finish_cursor_frame(now)
    end

    def close
      return if @closed
      @closed = true
      shutdown_cursor_network
      @progress&.close
      detach_view
      @presentations.map { |item| item[:handle] }.compact.uniq.each(&:finish!)
      @presentations.clear
      @audio.close
    end

    def show_settings
      return if @settings_open || @closed
      opened_here = true
      @settings_open = true
      @surface&.clear_input
      @mouse.suspend
      @audio.silence
      @program.send(:show_darts_settings, tick: -> { frame(background: true) }, clock: @clock)
    ensure
      if opened_here
        @settings_open = false
        @surface&.clear_input
        @mouse.suspend
        @audio.refresh_preferences if @audio.respond_to?(:refresh_preferences)
      end
    end

    private

    def synchronize_aim_state
      active = @replay && !@replay.finished? && @replay.state[:phase] != :opening &&
        @replay.current_player.to_s.casecmp?(@viewer) && !GameRoomParticipants.bot?(@replay.current_player) &&
        @pending == nil && !session_paused?
      unless active
        @aim_identity = nil
        @awaiting_start_identity = nil
        @outside_board = nil
        @training_sector = nil
        @mouse.suspend
        @audio.silence
        return
      end

      difficulty = active_difficulty(@replay.state)
      identity = [@replay.state[:throw_index], @replay.current_player.to_s.downcase, difficulty]
      if @aim_identity != identity && @awaiting_start_identity != identity
        @aim_identity = nil
        @awaiting_start_identity = identity
        @ready_announced = false
        @mouse.suspend
        @audio.silence
      end
      present_audio
    end

    def awaiting_start?
      @awaiting_start_identity != nil && @pending == nil && !@replay.finished?
    end

    def start_aim(now)
      return false unless awaiting_start? && @presentations.empty?

      difficulty = active_difficulty(@replay.state)
      identity = [@replay.state[:throw_index], @replay.current_player.to_s.downcase, difficulty]
      return false unless identity == @awaiting_start_identity

      @engine.reset(seed: @replay.state[:seed], throw_index: @replay.state[:throw_index], difficulty: difficulty,
        time_limit: @replay.state[:options]['time_limit'], timeout_result: @replay.state[:options]['timeout_result'])
      @aim_identity, @awaiting_start_identity = identity, nil
      @ready_announced = false
      @deadline_warning = nil
      @outside_board = !Scoring.on_board?(*@engine.position)
      @training_sector = Scoring.sector(*@engine.position) if training?
      present_audio
      true
    end

    def active_aim?
      @replay && @aim_identity && @pending == nil && !@replay.finished? && !session_paused?
    end

    def move(command, now)
      dx, dy = case command
      when :left then [-1, 0]
      when :right then [1, 0]
      when :up then [0, 1]
      when :down then [0, -1]
      else return false
      end
      moved = @engine.nudge(dx, dy, now)
      if moved && @engine.last_nudge_blocked
        @audio.limit
        speak_training(p_('Darts training', 'Playfield boundary'))
      end
      moved
    end

    def finish_throw(now, automatic:)
      return false unless @pending == nil
      result = @engine.finish(now, automatic: automatic)
      return false unless result
      @pending = [result[:index], result[:x], result[:y], result[:time_ms], result[:automatic] ? 'a' : 'm'].join(':')
      clear_remote_cursor
      @mouse.suspend
      @audio.silence
      flight = @audio.throw_dart.to_f
      speak_training(automatic ? p_('Darts training', 'Automatic throw') : p_('Darts training', 'Throw'))
      @local_throw = {value: @pending, impact_at: now.to_f + flight + FLIGHT_PAUSE}
      true
    end

    def schedule_presentation(item)
      while @presentations.length >= MAX_PRESENTATIONS
        discarded = @presentations.shift
        discarded[:handle]&.finish!
      end
      @presentations << item
    end

    def process_presentations(now)
      due, @presentations = @presentations.partition { |item| item[:due] <= now }
      due.sort_by { |item| item[:due] }.each do |item|
        if item[:kind] == :impact
          lead = @audio.impact(item[:points], x: item[:x], y: item[:y]).to_f
          if lead.positive?
            schedule_presentation(item.merge(kind: :quality, due: now + lead))
          else
            tail = @audio.quality(item[:points]).to_f
            schedule_presentation(item.merge(kind: :announcement, due: now + tail))
          end
        elsif item[:kind] == :quality
          tail = @audio.quality(item[:points]).to_f
          schedule_presentation(item.merge(kind: :announcement, due: now + tail))
        elsif item[:kind] == :announcement
          result_tail = if [:win, :loss].include?(item[:result])
            @audio.result(won: item[:result] == :win).to_f
          else
            0.0
          end
          (item[:descriptions].to_a + [item[:result_text]].compact).each do |text|
            speak(GameRoomContent.utf8(text.to_s), stop: false, break_sequence: false) unless text.to_s.empty?
          end
          if result_tail.positive?
            schedule_presentation(kind: :completion, due: now + result_tail, handle: item[:handle])
          else
            item[:handle]&.finish!
          end
        elsif item[:kind] == :completion
          item[:handle]&.finish!
        end
      end
    end

    def terminal_result(before, after, viewer)
      return nil unless before && after && !before.finished? && after.finished?
      return :observer unless GameRoomParticipants.includes?(after.players, viewer)

      GameRoomParticipants.same?(after.winner, viewer) ? :win : :loss
    end

    def next_throw_prompt(replay, viewer)
      return nil if replay.finished? || replay.current_player == nil
      return nil unless GameRoomParticipants.same?(replay.current_player, viewer)
      return nil if GameRoomParticipants.bot?(replay.current_player)

      @game.throw_prompt_text(replay)
    end

    def present_audio
      return @audio.silence if @settings_open || session_paused?
      return @audio.update(*@engine.position, active: true) if active_aim?

      cursor = fresh_remote_cursor(@clock.call.to_f)
      if cursor && !cursor[:player].to_s.casecmp?(@viewer.to_s)
        @audio.update(cursor[:x], cursor[:y], active: true)
      else
        @audio.silence
      end
    end

    def receive_cursor_network(now)
      return unless @channel && @replay && !@network_closed

      @channel.tick
      synchronize_cursor_epoch
      return unless @cursor_epoch

      @channel.take_packets.each do |sender, packet|
        receive_cursor_packet(sender, packet, now)
      end
    end

    def finish_cursor_frame(now)
      publish_cursor(now)
      present_audio
    end

    def synchronize_cursor_epoch
      return unless @channel.epoch && @channel.epoch != @cursor_epoch

      @cursor_epoch = @channel.epoch
      @cursor_sequence = 0
      @cursor_next_send = 0.0
      @cursor_last_signature = nil
      clear_remote_cursor
    end

    def receive_cursor_packet(sender, packet, now)
      kind = host? ? 'input' : 'state'
      return unless cursor_packet_valid?(packet, kind)

      body = packet['d']
      return unless current_cursor_body?(body)
      if host?
        return unless sender.to_s.casecmp?(@replay.current_player.to_s)
      else
        return unless sender.to_s.casecmp?(@owner.to_s)
        return unless body['p'].is_a?(String) && body['p'].casecmp?(@replay.current_player.to_s)
      end

      if body['active']
        return unless Scoring.bounded_coordinate?(body['x']) && Scoring.bounded_coordinate?(body['y'])
        @remote_cursor = {player: @replay.current_player.to_s, index: body['i'], x: body['x'], y: body['y'], received_at: now}
      else
        clear_remote_cursor
      end
    end

    def cursor_packet_valid?(packet, kind)
      packet.is_a?(Hash) && packet['m'] == @match && packet['e'] == @cursor_epoch &&
        packet['v'] == GameRoomRealtime::Protocol::VERSION && packet['k'] == kind && packet['d'].is_a?(Hash) &&
        [packet['n'], packet['a']].all? do |number|
          number.is_a?(Integer) && number.between?(0, GameRoomRealtime::Protocol::MAX_SEQUENCE)
        end
    end

    def current_cursor_body?(body)
      return false unless body['i'].is_a?(Integer) && body['i'] == @replay.state[:throw_index].to_i
      return false unless [true, false].include?(body['active'])
      return false if @replay.finished? || @replay.state[:phase] == :opening
      !GameRoomParticipants.bot?(@replay.current_player)
    end

    def publish_cursor(now)
      return unless @channel && @cursor_epoch && @replay && !@network_closed

      body = host? ? host_cursor_body(now) : guest_cursor_body
      signature = [body['i'], body['p'], body['active'], body['x'], body['y']]
      transition = @cursor_last_signature == nil || signature.first(3) != @cursor_last_signature.first(3)
      return unless transition || (body['active'] && now >= @cursor_next_send)

      kind = host? ? 'state' : 'input'
      packet = GameRoomRealtime::Protocol.encode(match: @match, epoch: @cursor_epoch,
        sequence: @cursor_sequence, kind: kind, body: body)
      return unless @channel.send(packet)

      @cursor_sequence += 1
      @cursor_last_signature = signature
      @cursor_next_send = now + CURSOR_SEND_INTERVAL
    end

    def host_cursor_body(now)
      body = local_cursor_body
      return body if body['active']

      cursor = fresh_remote_cursor(now)
      return inactive_cursor_body unless cursor

      {'i' => cursor[:index], 'p' => cursor[:player], 'active' => true, 'x' => cursor[:x], 'y' => cursor[:y]}
    end

    def guest_cursor_body
      body = local_cursor_body
      body.delete('p')
      body
    end

    def local_cursor_body
      body = inactive_cursor_body
      return body unless active_aim? && @replay.current_player.to_s.casecmp?(@viewer.to_s)

      x, y = @engine.position.map(&:round)
      body.merge('active' => true, 'x' => x, 'y' => y)
    end

    def inactive_cursor_body
      {'i' => @replay.state[:throw_index].to_i, 'p' => @replay.current_player.to_s, 'active' => false}
    end

    def fresh_remote_cursor(now)
      cursor = @remote_cursor
      return unless cursor && now >= cursor[:received_at] && now - cursor[:received_at] <= CURSOR_TIMEOUT
      return unless replay_cursor_identity(@replay) == [cursor[:index], cursor[:player].downcase]
      cursor
    end

    def replay_cursor_identity(replay)
      return unless replay && !replay.finished? && replay.current_player
      [replay.state[:throw_index].to_i, replay.current_player.to_s.downcase]
    end

    def clear_remote_cursor
      @remote_cursor = nil
    end

    def reset_cursor_network
      @cursor_epoch = nil
      @cursor_sequence = 0
      @cursor_next_send = 0.0
      @cursor_last_signature = nil
      @remote_cursor = nil
      @network_closed = false
    end

    def shutdown_cursor_network
      return if @network_closed
      @network_closed = true
      clear_remote_cursor
      unregister_ping_channel if @channel
      @channel&.close
    end

    def reset_table_control
      reset_cursor_network
      @aim_identity = @awaiting_start_identity = nil
      @mouse.suspend
      @audio.silence
      synchronize_aim_state if @replay
    end

    def session_pause_changed(paused, _elapsed)
      @aim_identity = @awaiting_start_identity = nil
      @mouse.suspend
      clear_remote_cursor
      @audio.silence
      synchronize_aim_state if @replay && !paused
    end

    def present_board_edge
      outside = !Scoring.on_board?(*@engine.position)
      if outside && @outside_board == false
        @audio.edge
        speak_training(p_('Darts training', 'Target boundary'))
      end
      @outside_board = outside
    end

    def training?
      training_replay?(@replay)
    end

    def training_replay?(replay)
      options = replay&.state&.[](:options)
      options.is_a?(Hash) && options['mode'] == 'training'
    end

    def speak_training(text)
      speak(text, stop: false, break_sequence: false) if training?
    end

    def present_training_sector
      return unless training?

      x, y = @engine.position.map(&:round)
      sector = Scoring.sector(x, y)
      return if sector == @training_sector

      @training_sector = sector
      speak(@game.training_position_text(x, y), stop: false, break_sequence: false)
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
