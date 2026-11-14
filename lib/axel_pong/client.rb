require_relative 'client_state'
require_relative 'snapshot_effects'
require_relative 'engine'
require_relative 'bot'
require_relative 'audio'
require_relative 'mouse'
require_relative '../realtime/event_channel'
require_relative '../realtime/timer'
require_relative '../realtime/progress'
require_relative '../realtime/task_ui'
require_relative '../game_room_ping'
require_relative 'peer_play'
require_relative '../realtime/table_control'

require_relative "../game_room_localization"

module GameRoomPong
  using GameRoomLocalization::Translations
  class Client
    include PeerPlay
    include GameRoomRealtime::TableControl
    include GameRoomRealtime::ProgressClient
    SEND_INTERVAL = 0.04
    MAX_PHYSICS_STEPS = 4
    HANDSHAKE_TIMEOUT = 10.0
    STREAM_TIMEOUT = 4.0
    SINGLE_SERVE_DELAY = 2.7

    def _(source); GameRoomContent.utf8(super(source)); end

    def initialize(program, game, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, channel_factory: nil, audio: nil, mouse: nil, transport: nil)
      @program, @game, @clock = program, game, clock
      @activity_transport = transport
      @channel_factory = channel_factory || ->(**args) { GameRoomRealtime::EventChannel.new(**args) }
      @audio = audio || Audio.new(program, clock: clock)
      @mouse = mouse || MouseControl.new
      connection_state.peers = {}
      connection_state.sequence = 0
      connection_state.next_send = 0.0
      connection_state.last_reconnect = -30.0
      rally_state.paused = true
      @closed = false
    end

    def bind_screen(session_id:, table_id:, owner:, viewer:, members:, match_scope: nil, first_server: nil, single_point: false)
      unless match_scope.nil? || (match_scope.is_a?(String) && !match_scope.empty?)
        raise ArgumentError, 'Invalid Pong match scope'
      end
      unless first_server.nil? || (first_server.is_a?(Integer) && first_server.between?(0, 1))
        raise ArgumentError, 'Invalid Pong first server'
      end
      raise ArgumentError, 'Invalid Pong single-point mode' unless single_point == true || single_point == false
      @activity_table, @activity_session = table_id, session_id
      @owner, @viewer = owner.to_s, viewer.to_s
      @configured_first_server = first_server
      @single_point = single_point
      connection_state.connection_started_at = @clock.call
      # A nested point needs its own channel, not a fictional LiveSession ID.
      # Keep the legacy identity byte-for-byte when no scope is requested.
      match_key = "GameRoom:axel_pong:#{table_id}:#{session_id}"
      match_key = match_key.b + "\0scope\0".b + match_scope.b unless match_scope.nil?
      @match = Digest::SHA256.hexdigest(match_key)[0, 24]
      @base_match, @members_provider = @match, members
      @channel = @channel_factory.call(program: @program, match: @match, owner: @owner,
        viewer: @viewer, clock: @clock, members: members)
    end

    def start
      unless @program.respond_to?(:communication)
        alert(_('This ELTEN version does not provide Communications.'))
        return false
      end
      # Register the endpoint while loading the recordings. Session metadata
      # is selected by before_wait before any subsequent setup tick.
      register_ping_channel
      @channel.tick
      @audio.load
      start_progress
      true
    end

    def host?; @owner.casecmp?(@viewer); end
    def refresh_due?; false; end
    def context_data; { 'pong_point' => point_state.pending_point }; end
    def action(_selection, _replay, _viewer); false; end
    def error(_status); end
    def automatic_error(_status); end

    # Only the enclosing game's accepted result can finish this projection.
    # Keep Progress alive for the goal recordings, but close input and relay.
    def finish_single_point(winner:)
      return false unless @single_point && !@closed && @replay && !@replay.finished?
      return false unless winner.is_a?(Integer) && winner.between?(0, 1)
      preview = point_state.goal_preview
      unless preview && preview[:rally] == @replay.state[:rally] && preview[:winner] == winner
        @audio.goal(viewer: @side || observer_side, winner: winner)
      end
      @replay = @replay.dup
      @replay.winner = @players[winner]
      point_state.pending_point = point_state.goal_preview = nil
      rally_state.paused = true
      detach_view
      unregister_ping_channel
      @channel.close
      true
    end

    def presentation_pending?
      @audio.respond_to?(:announcement_pending?) && @audio.announcement_pending?
    end

    def event(event, before, after, viewer, _repository)
      return unless event['action'] == 'pong_point' && before && after
      rally = after.state[:rally]
      return unless rally == before.state[:rally] + 1
      return if rally <= presentation_state.announced_rally.to_i
      presentation_state.announced_rally = rally
      # Catch-up can contain many old points. Present the current score only.
      return if @replay && rally < @replay.state[:rally]
      side = after.players.index { |player| player.to_s.casecmp?(viewer.to_s) }
      assignment = @game.team_assignment(after.state[:options], players: after.players)
      perspective = side || observer_side(after.players)
      team = assignment ? assignment.seats[perspective] : perspective
      winner = [0, 1].find { |i| after.state[:scores][i] > before.state[:scores][i] }
      preview = point_state.goal_preview if point_state.goal_preview && point_state.goal_preview[:rally] == before.state[:rally] && point_state.goal_preview[:winner] == winner
      labels = @game.score_labels(after.state[:options], after.players)
      order = team == 1 ? [1, 0] : [0, 1]
      score_text = order.map { |i| "#{labels[i]}: #{after.state[:scores][i]}" }.join('; ') + '.'
      @audio.point(after.state[:scores], viewer: team, winner: winner, finished: after.finished?,
        goal_at: preview && preview[:at], score_text: score_text, result_text: @game.result_text(after))
      if preview
        score_at = [@clock.call, preview[:at] + 3.0].max
        rally_state.ready_at, rally_state.serve_announce_at = score_at + SINGLE_SERVE_DELAY, score_at + 2.0
        @ready_deadline_created_at = @clock.call
        if defined?(Log) && Log.respond_to?(:debug)
          Log.debug("Game Room Pong point_confirmed rally=#{before.state[:rally]} durable_confirmation_ms=#{((@clock.call - preview[:at]) * 1000).round}")
        end
      end
      point_state.goal_preview = nil
    end
    def presents_game_event?(event)
      event['action'] == 'pong_point' && @audio.respond_to?(:presents_point) && @audio.presents_point
    end
    def presents_game_result?(replay)
      replay.state[:rally] == presentation_state.announced_rally && @audio.respond_to?(:presents_point) && @audio.presents_point
    end
    def after_events(replay, viewer, context:); before_wait(replay, viewer); end

    def before_wait(replay, viewer)
      @channel.configure_p2p(replay.state[:options])
      changed = @replay == nil || @replay.state[:rally] != replay.state[:rally]
      @replay = replay
      @players = replay.players
      @initial_players ||= @players.dup
      @audio.prepare_players(@players.length) if @audio.respond_to?(:prepare_players)
      @side = @players.index { |p| p.to_s.casecmp?(viewer.to_s) }
      @side = nil if bot_seat?(viewer)
      assignment = @game.team_assignment(replay.state[:options], players: @players)
      @teams = assignment ? assignment.seats : [0, 1]
      rally_state.rotation = Rotation.new(teams: @teams, rally: replay.state[:rally], first_server: first_server)
      observer_side(@players) if @side == nil
      @required = @players.reject { |p| bot_seat?(p) || p.to_s.casecmp?(@viewer) }
      @channel.required_members = (@required + [@owner]).uniq if @channel.respond_to?(:required_members=)
      # The engine path is shared. A distinct mixed-match dialect rejects old
      # clients which would still send remote key presses instead of actions.
      mixed = @players.any? { |p| bot_seat?(p) }
      dialect = rally_state.rotation.doubles? ? 'pong-doubles-' : 'pong-'
      dialect += mixed ? 'mixed-peer-1' : 'peer-2'
      # Earlier clients normalize the unknown level to Normal. Never let
      # them exchange actions with a client simulating Inferno's faster ball.
      dialect += '-inferno-1' if replay.state[:options]['difficulty'] == 7
      # Older clients normalize either new choice to 11 and would disconnect
      # mid-match. Keep them out of these modes at the existing handshake.
      dialect += '-targets-2' if %w[custom unlimited].include?(replay.state[:options]['target'])
      @channel.enable_events(dialect, routing: :peers)
      reset_rally if changed
      if replay.finished?
        @mouse.suspend
        @audio.suspend
        unregister_ping_channel
        @channel.close
      end
    end

    def attach_view(form, surface)
      return if @form.equal?(form) && @surface.equal?(surface) && @timer && @replay && !@replay.finished?
      detach_view
      return unless surface.respond_to?(:present) && @replay && !@replay.finished?
      @form, @surface = form, surface
      @surface.on_pong_command = method(:local_command) if @surface.respond_to?(:on_pong_command=)
      @surface.on_input_reset = -> { @mouse.suspend } if @surface.respond_to?(:on_input_reset=)
      @progress.attach(@form)
      @timer = @progress.timer
      present
    end

    def detach_view
      @progress&.detach
      @mouse.suspend
      @surface.on_pong_command = nil if @surface.respond_to?(:on_pong_command=)
      @surface.on_input_reset = nil if @surface.respond_to?(:on_input_reset=)
      @form.delete_timer(@timer) if @form && @timer
      @timer = @surface = @form = nil
      @audio.suspend
    end

    def tick
      return if @closed
      @audio.tick
      return if !@replay || @replay.finished?
      @channel.tick
    end

    def network_task_ui(**options)
      GameRoomRealtime::TaskUI.new(**options, clock: @clock, tick: -> {
        # Only an actually updated game form drives its own timer. A chat
        # control passed on its own does not. Never take game input from a
        # network/progress window or the chat-only update path.
        if GameRoomRealtime::TaskUI.updates_form?(options[:ui], @form)
          # The owned form's existing timer advances the client once.
        elsif !@replay || @replay.finished?
          tick
        else
          begin
            @network_wait = true
            progress_frame
          ensure
            @network_wait = false
          end
        end
      })
    end

    def close
      return if @closed
      @closed = true
      unregister_ping_channel
      @progress&.close
      detach_view
      @channel&.close
      @audio.close
    end

    def show_settings
      return if @settings_open
      opened_here = true
      @settings_open = true
      @mouse.suspend
      @program.send(:show_pong_settings, tick: -> { progress_frame }, clock: @clock)
    ensure
      if opened_here
        @mouse.suspend
        @settings_open = false
      end
    end

    private

    # Keep the original service identity while replacing the channel. The
    # following replay rebuilds Pong's rally with its existing physics profile.
    def reset_table_control
      @service_match ||= @match
      connection_state.connection_started_at = @clock.call
      connection_state.epoch = nil
      connection_state.peers, @connection_peers, rally_state.deferred_events = {}, {}, []
      connection_state.sequence = connection_state.event_sequence = 0
      point_state.pending_point = point_state.goal_preview = @replay = nil
      rally_state.paused = true
      @surface.clear_input if @surface&.respond_to?(:clear_input)
    end

    def observer_side(players = @players)
      side = players.to_a.index { |player| player.to_s.casecmp?(@observed_player.to_s) }
      @observed_player = players.to_a.first unless side
      side || 0
    end

    def audio_side
      @side || observer_side
    end

    def handshake_deadline
      [@epoch_since, connection_state.connection_started_at].compact.max + HANDSHAKE_TIMEOUT
    end

    def awaiting_point?
      point_state.pending_point || (point_state.goal_preview && point_state.goal_preview[:rally] == @replay.state[:rally])
    end

    def preview_goal(winner)
      return if point_state.goal_preview && point_state.goal_preview[:rally] == @replay.state[:rally]
      point_state.goal_preview = { rally: @replay.state[:rally], winner: winner, at: @clock.call }
      @audio.goal(viewer: rally_state.rotation ? rally_state.rotation.team(audio_side) : audio_side, winner: winner)
    end

    def local_command(command)
      case command
      when 'echo'
        mode = @audio.cycle_echo
        speak({'off' => _('Side-wall cues: off.'), 'noise' => _('Side-wall cues: noise.'),
          'tone' => _('Side-wall cues: tones.')}[mode])
      when 'perspective_first', 'perspective_second', 'perspective_third', 'perspective_fourth'
        return true unless @side == nil && @surface && @form && !@replay.finished?
        return true unless @surface.fields.include?(@form.fields[@form.index.to_i])
        seat = %w[perspective_first perspective_second perspective_third perspective_fourth].index(command)
        return true unless @players[seat]
        @observed_player = @players[seat]
        present
        if @single_point && rally_state.snapshot
          speak(single_point_spectator_announcement)
        else
          speak(_('Perspective: %{player}.') % { player: @game.participant_name(@observed_player) })
        end
      when 'crowd'
        if @audio.toggle_crowd
          speak(@audio.crowd ? _('Crowd on.') : _('Crowd off.'))
        end
      when 'hurry'
        unless respond_to?(:request_hurry) && request_hurry
          speak(_('You can hurry your opponent only while waiting for their serve.'))
        end
      end
      true
    end

    def sample_pointer_input(raw, healthy)
      now = @clock.call
      active = healthy && !@background_input && !@settings_open && !@network_wait && @side != nil && @surface && @form &&
        @surface.respond_to?(:input_active?) && @surface.input_active?(@form)
      # Discard accumulated pointer motion after a late frame. A continuous
      # active keyboard hold keeps its repeat phase, not the missed steps.
      # Real focus/health/rally changes still reset it through suspend/sync.
      if @mouse_sample_at && (now < @mouse_sample_at || now - @mouse_sample_at > Engine::STEP * MAX_PHYSICS_STEPS + 0.000001)
        continuous = active && @mouse.active? && now >= @mouse_sample_at
        @mouse.suspend(reset_keyboard: !continuous)
      end
      @mouse_sample_at = now
      @mouse.sample(active: active)
      # Keep independent counters: a recreated keyboard field may restart at
      # zero, while mouse clicks must neither vanish nor become extra presses.
      key_count = raw['press']
      keys = if key_count
        key_count >= @pointer_key_count.to_i ? key_count - @pointer_key_count.to_i : key_count
      else
        raw['hit'] && !@pointer_key_held ? 1 : 0
      end
      # A network/chat-only frame supplies neutral input without a keyboard
      # counter. It must not erase the last observed physical press count.
      @pointer_key_count = key_count unless key_count.nil?
      @pointer_key_held = raw['hit']
      clicks = @mouse.clicks - @pointer_click_count.to_i
      @pointer_click_count = @mouse.clicks
      @pointer_press = @pointer_press.to_i + keys + [clicks, 0].max
      # ShootBall uses a DOWN edge; the separate goal-line rescue also checks
      # a held left button, exactly like the original held-key rescue.
      raw.merge('press' => @pointer_press, 'hit' => raw['hit'] == true || @mouse.held?)
    end

    def pointer_input(input, at)
      return input unless @side != nil && rally_state.snapshot
      position = rally_state.engine ? rally_state.engine.paddles[@side] : rally_state.snapshot['p'][@side]
      @mouse.step(input, position: position, now_ms: (at * 1000).to_i)
    end

    def each_physics_frame(now)
      elapsed = rally_state.physics_updated_at && now - rally_state.physics_updated_at
      # ELTEN's callbacks do not fall exactly on the original 16 ms grid.
      # Keep the fractional remainder instead of scheduling "now + 16 ms",
      # which turned normal 10/20 ms UI callbacks into 20% slower gameplay.
      # A real suspension is different: discard that time, never replay a
      # whole missed rally or carry a catch-up debt into later callbacks.
      if !rally_state.physics_at || (elapsed && (elapsed < 0 || elapsed > Engine::STEP * MAX_PHYSICS_STEPS + 0.000001))
        rally_state.physics_at = now
      end
      rally_state.physics_updated_at = now
      MAX_PHYSICS_STEPS.times do
        break if now + 0.000001 < rally_state.physics_at
        frame_at = rally_state.physics_at
        rally_state.physics_at += Engine::STEP
        yield frame_at
      end
    end

    def first_server
      return @configured_first_server unless @configured_first_server.nil?
      initial = @initial_players || @players
      human = initial.index { |p| !GameRoomParticipants.bot?(p) }
      return human || 0 if @teams.length == 2 && initial.any? { |p| GameRoomParticipants.bot?(p) }
      # One shared once-per-match choice, like original time parity, but not
      # separately sampled from each computer's potentially incorrect clock.
      (@service_match || @match)[-1].to_i(16) % 2
    end

    def playable_input(raw, active:, moving: active)
      focused = @surface && @form &&
        (!@surface.respond_to?(:input_active?) || @surface.input_active?(@form))
      active = active == true && !@background_input && !@settings_open && !@network_wait && focused
      held = raw['hit'] == true
      increment = if raw.key?('press')
        value = raw['press'] >= @raw_press.to_i ? raw['press'] - @raw_press.to_i : raw['press']
        @raw_press = raw['press']
        value
      else
        held && !@was_hit ? 1 : 0
      end
      @was_hit = held
      # Always consume the raw counter, including the pause and the frame
      # announcing readiness. Only new presses made during play are retained.
      # A held key must be released after the pause, not served by key repeat.
      @hit_blocked = true if !active && held
      @hit_blocked = false unless held
      @total_press = @total_press.to_i + increment if active && !@hit_blocked
      input = { 'move' => active ? raw['move'] : 0, 'hit' => active && !@hit_blocked && held,
        'press' => [@total_press.to_i - @press_base.to_i, 0].max }
      input['aim'] = moving ? raw['aim'] : 0 if raw.key?('aim')
      @raw_directions ||= {}
      @direction_totals ||= {}
      movement_active = moving && !@background_input && !@settings_open && (!@surface || !@surface.respond_to?(:input_active?) || @surface.input_active?(@form))
      KeyboardMovement::COUNTERS.each do |key|
        next unless raw.key?(key)
        count, previous = raw[key], @raw_directions[key].to_i
        delta = count >= previous ? count - previous : count
        @raw_directions[key] = count
        @direction_totals[key] = @direction_totals[key].to_i + (movement_active ? delta : 0)
        input[key] = @direction_totals[key] - (@direction_base || {})[key].to_i
      end
      input
    end

    def reset_rally_feedback
      @mouse.reset_rally
      point_state.pending_point = nil
      @press_base = @total_press.to_i
      @direction_base = (@direction_totals || {}).dup
      @audio.reset
      rally_state.physics_at = rally_state.physics_updated_at = nil
      connection_state.next_send = 0.0
      initial = @replay.state[:rally].zero?
      @initial_rally = initial
      @initial_ready_since = nil
      @host_ready_at = 0.0
      @ready_deadline_created_at = @clock.call
      rally_state.ready_at = initial ? Float::INFINITY : @clock.call + (3.0 + SINGLE_SERVE_DELAY)
      rally_state.serve_announce_at = initial ? Float::INFINITY : @clock.call + 5.0
      if point_state.goal_preview && point_state.goal_preview[:rally] == @replay.state[:rally] - 1
        score_at = [@clock.call, point_state.goal_preview[:at] + 3.0].max
        rally_state.ready_at, rally_state.serve_announce_at = score_at + SINGLE_SERVE_DELAY, score_at + 2.0
      end
      @server_announced = false
      rally_state.paused = true
    end

    def valid_state?(body)
      data = body['state']
      return false unless [true, false].include?(body['paused']) && data.is_a?(Hash)
      return false if body.key?('ready_in') && !finite?(body['ready_in'], 0, 10)
      return false if body.key?('waiting') && ![true, false].include?(body['waiting'])
      return false if body.key?('serve_wait') && ![true, false].include?(body['serve_wait'])
      return false unless data['tick'].is_a?(Integer) && data['tick'].between?(0, 2**40)
      return false unless @players.each_index.include?(data['server']) && [nil, 0, 1].include?(data['goal'])
      if rally_state.rotation.doubles?
        return false unless data['teams'] == @teams && @players.each_index.include?(data['receiver'])
        rotation = Rotation.new(teams: @teams, rally: body['r'], first_server: first_server)
        return false unless data['server'] == rotation.server && data['receiver'] == rotation.receiver
      elsif data['teams'] != nil
        return false
      end
      return false unless [true, false].include?(data['invisible'])
      return false unless data['p'].is_a?(Array) && data['p'].length == @players.length && data['p'].all? { |n| finite?(n, 1, 29) }
      return false if data.key?('edges') && !(data['edges'].is_a?(Array) && data['edges'].length == @players.length &&
        data['edges'].all? { |n| valid_input_count?(n) })
      return false unless data['shields'].is_a?(Array) && data['shields'].length == @players.length && data['shields'].all? { |n| n.is_a?(Integer) && n.between?(0, 625) }
      b = data['b']
      return false unless valid_ball?(b)
      data['fx'].is_a?(Array) && data['fx'].length <= 8 && data['fx'].all? { |fx| valid_snapshot_effect?(fx) }
    end

    def valid_snapshot_effect?(fx)
      return false unless fx.is_a?(Array) && fx.length == 5 && fx[0].is_a?(Integer) && fx[0] >= 0
      return false unless SnapshotEffects::KINDS.include?(fx[1])
      # Paddle/contact effects index the participant's position in Audio;
      # wall/invisibility (and ignored effects) legitimately have no player.
      return false if fx[2] == nil && SnapshotEffects.player_required?(fx[1])
      (fx[2] == nil || @players.each_index.include?(fx[2])) && finite?(fx[3], 0, 30) && finite?(fx[4], -1000, 1020)
    end

    def valid_ball?(b)
      b.is_a?(Hash) && finite?(b['x'], 0, 30) && finite?(b['y'], -1000, 1020) &&
        finite?(b['speed'], 0, 1000) && finite?(b['lateral'], 0, 1) &&
        [-1, 0, 1].include?(b['dx']) && [-1, 0, 1].include?(b['dy'])
    end

    def finite?(n, lo, hi); n.is_a?(Numeric) && n.finite? && n.between?(lo, hi); end

    def valid_input_count?(n); n.is_a?(Integer) && n.between?(0, 2**31 - 1); end

    def set_paused(value, waiting: false)
      @waiting_for_serve = waiting
      value = true unless rally_state.snapshot
      if rally_state.paused != value
        rally_state.paused = value
        if value && !waiting
          announce_progress(_('Match paused. Waiting for synchronization.'))
        elsif !value && rally_state.snapshot['b']['dy'] != 0
          announce_progress(_('Match resumed.'))
        end
      end
    end

    def announce_ready(now)
      return if @server_announced || now < rally_state.serve_announce_at || !rally_state.snapshot
      if !@single_point && @initial_rally && @players.none? { |p| GameRoomParticipants.bot?(p) } && !@initial_settings_announced
        @initial_settings_announced = true
        options = @replay.state[:options]
        difficulty = @game.option_definitions.find { |item| item.key == 'difficulty' }.choices[options['difficulty'] - 1].label
        target = @game.points_to_win(options)
        announcement = target ? _('%{variant}. %{difficulty}. %{points} points to win.') : _('%{variant}. %{difficulty}. Unlimited match.')
        announce_progress(announcement % {
          variant: options['arcade'] ? _('Arcade') : _('Classic'), difficulty: GameRoomContent.utf8(difficulty), points: target })
        rally_state.serve_announce_at = now + 0.12
        rally_state.ready_at = [rally_state.ready_at, rally_state.serve_announce_at].max
        return
      end
      @server_announced = true
      if rally_state.rotation&.doubles?
        rally = @replay.state[:rally]
        return if rally.odd? || @serve_announced_block == rally / 2
        @serve_announced_block = rally / 2
        # Presentation only, just like Single. A synthesizer may never return
        # its final speech index; it must not gate the match or extend the
        # ordinary score + SINGLE_SERVE_DELAY deadline for any participant.
        announce_progress(_('%{server} will serve against %{receiver}.') % {
          server: GameRoomContent.utf8(GameRoomParticipants.display_name(@players[rally_state.rotation.server])),
          receiver: GameRoomContent.utf8(GameRoomParticipants.display_name(@players[rally_state.rotation.receiver])) })
      else
        text = if @single_point && @side.nil?
          single_point_spectator_announcement
        else
          _('%{player} serves.') % { player: GameRoomContent.utf8(GameRoomParticipants.display_name(@players[rally_state.snapshot['server']])) }
        end
        announce_progress(text)
      end
      @audio.start_match
    end

    def single_point_spectator_announcement
      _("Watching %{player}. %{server} serves.") % {
        player: GameRoomContent.utf8(GameRoomParticipants.display_name(@players[observer_side])),
        server: GameRoomContent.utf8(GameRoomParticipants.display_name(@players[rally_state.snapshot['server']]))}
    end

    def peer_service_waiting?
      rally_state.rotation.doubles? && rally_state.engine.turn.zero? &&
        @required.any? { |user| connection_state.peers[user.downcase]&.body&.[]('serve_wait') == true }
    end

    def prepare_first_serve(now, healthy)
      return unless @initial_rally && !@server_announced
      unless healthy
        @initial_ready_since = nil
        rally_state.ready_at = rally_state.serve_announce_at = Float::INFINITY
        return
      end
      return if @initial_ready_since
      @initial_ready_since = now
      rally_state.ready_at = rally_state.serve_announce_at = now
    end

    def local_automatic
      @players.each_index.map { |side| side == @side && Preferences.read(@program)['auto_return'] == true }
    end

    def surface_input
      raw = @surface && @form && !@network_wait ? @surface.input(@form) : { 'move' => 0, 'hit' => false }
      @settings_open || @background_input ? raw.merge('move' => 0, 'aim' => 0, 'hit' => false) : raw
    end

    def present
      status = if session_paused?
        _('Game paused.')
      elsif @waiting_for_serve
        _('Waiting for the next serve.')
      elsif rally_state.paused
        _('Match paused. Waiting for synchronization.')
      else
        _('Match in progress.')
      end
      # Listening perspective is read-only. The spec's viewer still controls
      # whether this surface may supply paddle input.
      @surface.listening_seat = audio_side if @surface.respond_to?(:listening_seat=)
      @surface&.present(rally_state.snapshot, status)
      @audio.update(rally_state.snapshot, viewer: audio_side, paused: rally_state.paused)
    end

    def session_pause_changed(paused, elapsed)
      if paused
        rally_state.paused = true
        @mouse.suspend
      else
        # A confirmed point or new control epoch may create a new deadline
        # during the pause. Only preserve time since that deadline existed.
        ready_elapsed = @ready_deadline_created_at ? [elapsed, [@clock.call - @ready_deadline_created_at, 0.0].max].min : elapsed
        rally_state.ready_at += ready_elapsed if rally_state.ready_at
        rally_state.serve_announce_at += ready_elapsed if rally_state.serve_announce_at
        @host_ready_at += elapsed if @host_ready_at
        @hurry_until += elapsed if @hurry_until
        @hurry_cooldowns&.transform_values! { |deadline| deadline + elapsed }
        @peer_disagreements&.clear
        rally_state.physics_at = rally_state.physics_updated_at = nil
        # No frame may charge shields for time spent outside active physics.
        rally_state.engine&.position([], now_ms: (@clock.call * 1000).to_i)
      end
    end
  end
end
