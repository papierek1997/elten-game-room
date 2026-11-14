require_relative 'client_state'
require 'digest'
require_relative 'engine'
require_relative 'defense_input'
require_relative 'bot'
require_relative 'audio'
require_relative '../realtime/event_channel'
require_relative '../realtime/timer'
require_relative '../realtime/progress'
require_relative '../realtime/task_ui'
require_relative '../realtime/table_control'

require_relative "../game_room_localization"

module GameRoomAudioBall
  using GameRoomLocalization::Translations
  class Client
    include GameRoomRealtime::TableControl
    include GameRoomRealtime::ProgressClient
    SEND_INTERVAL = 0.04
    POINT_PAUSE = 5.7
    SET_PAUSE = 5.0
    STREAM_TIMEOUT = 4.0


    def initialize(program, game, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, channel_factory: nil, audio: nil, transport: nil)
      @program, @game, @clock = program, game, clock
      @activity_transport = transport
      @channel_factory = channel_factory || ->(**args) { GameRoomRealtime::EventChannel.new(**args) }
      @audio = audio || Audio.new(program, clock: clock)
      rally_state.paused, @closed = true, false
      connection_state.peers, connection_state.connections, rally_state.deferred = {}, {}, []
      connection_state.sequence = connection_state.event_sequence = 0
      connection_state.next_send = 0.0
      connection_state.last_reconnect = -30.0
      @selected_lane = nil
      @defense_input = DefenseInput.new
    end

    def bind_screen(session_id:, table_id:, owner:, viewer:, members:, match_scope: nil, single_point: false)
      unless match_scope.nil? || (match_scope.is_a?(String) && !match_scope.empty?)
        raise ArgumentError, 'Invalid Audio Ball match scope'
      end
      raise ArgumentError, 'Invalid Audio Ball single-point mode' unless single_point == true || single_point == false
      @activity_table, @activity_session = table_id, session_id
      @single_point = single_point
      @owner, @viewer = owner.to_s, viewer.to_s
      connection_state.connection_started = @clock.call
      # Scope only the realtime channel; activity still belongs to the real
      # table and LiveSession. Ordinary games retain their existing identity.
      match_key = "GameRoom:audio_ball:#{table_id}:#{session_id}"
      match_key = match_key.b + "\0scope\0".b + match_scope.b unless match_scope.nil?
      @match = Digest::SHA256.hexdigest(match_key)[0, 24]
      @base_match, @members_provider = @match, members
      @channel = @channel_factory.call(program: @program, match: @match, owner: @owner,
        viewer: @viewer, clock: @clock, members: members)
      @channel.enable_events('audio-ball-peer-2', routing: :peers)
    end

    def start
      register_ping_channel
      @audio.load
      start_progress
      true
    end

    def host?; @owner.casecmp?(@viewer); end
    def refresh_due?; false; end
    def context_data; {'audio_ball_point' => point_state.pending_point}; end
    def action(_selection, _replay, _viewer); false; end
    def error(_status); end
    def automatic_error(_status); end

    def finish_single_point(winner:)
      return false unless @single_point && !@closed && @replay && !@replay.finished?
      return false unless winner.is_a?(Integer) && winner.between?(0, 1)
      preview = point_state.goal_preview
      unless preview && preview[:rally] == @replay.state[:rally] && preview[:winner] == winner
        @audio.goal(viewer: @side, winner: winner)
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

    def after_events(replay, viewer, context:); before_wait(replay, viewer); end

    def before_wait(replay, viewer)
      @channel.configure_p2p(replay.state[:options])
      changed = !@replay || @replay.state.values_at(:rally, :server) != replay.state.values_at(:rally, :server)
      @replay, @players = replay, replay.players
      @teams=@game.team_assignment(replay.state[:options],players:@players)&.seats || [0,1]
      @side = @players.index { |player| player.to_s.casecmp?(viewer.to_s) }
      @side = nil if bot_seat?(viewer)
      @required = @players.reject { |player| bot_seat?(player) || player.to_s.casecmp?(@viewer) }
      @channel.enable_events(@players.length==4 ? 'audio-ball-peer-3' : 'audio-ball-peer-2', routing: :peers)
      @channel.required_members = (@required + [@owner]).uniq
      reset_rally if changed
      if replay.finished?
        rally_state.paused = true
        detach_view
        unregister_ping_channel
        @channel.close
      end
    end

    def event(event, before, after, viewer, _repository)
      return unless event['action'] == 'audio_ball_point' && before && after
      rally = after.state[:rally]
      return unless rally == before.state[:rally] + 1 && rally > presentation_state.announced_rally.to_i
      presentation_state.announced_rally = rally
      return if @replay && rally < @replay.state[:rally]
      result = after.state[:last_point]
      return unless result
      seat = after.players.index { |player| player.to_s.casecmp?(viewer.to_s) }
      side = seat && @teams[seat]
      preview = point_state.goal_preview if point_state.goal_preview && point_state.goal_preview[:rally] == before.state[:rally] &&
        point_state.goal_preview[:winner] == result[:winner]
      @audio.point(result[:scores], sets: after.state[:sets], set_finished: result[:set_finished],
        winner: result[:winner], viewer: side, finished: after.finished?, goal_at: preview && preview[:at])
      rally_state.ready_at = point_ready_at(result)
      @ready_deadline_created_at = @clock.call
      point_state.goal_preview = nil
    end

    def presents_game_event?(event); event['action'] == 'audio_ball_point' && presents_point?; end
    def presents_game_result?(replay); replay.finished? && replay.state[:rally] == presentation_state.announced_rally && presents_point?; end

    def attach_view(form, surface)
      if @form.equal?(form) && @surface.equal?(surface) && @timer && @replay && !@replay.finished?
        # A retained view can have moved to chat since the preceding frame.
        # Stop capture now; ordinary input refresh reacquires it on return.
        @surface.deactivate_input if @surface.respond_to?(:deactivate_input) && !@surface.input_selected?(@form)
        return
      end
      detach_view
      return unless surface.respond_to?(:present) && @replay && !@replay.finished?
      @form, @surface = form, surface
      # A quiet view replacement keeps the form's focus, but activecontrols
      # still describes the previous native frame. Rebind capture to the new
      # selected field now; actual input keeps the stricter active-frame guard.
      @surface.activate_input if @surface.respond_to?(:activate_input) && @surface.input_selected?(@form)
      @surface.on_audio_ball_command = method(:local_command) if @surface.respond_to?(:on_audio_ball_command=)
      @progress.attach(@form)
      @timer = @progress.timer
      present
    end

    def detach_view
      @progress&.detach
      @defense_input.forget_held
      @surface.deactivate_input if @surface.respond_to?(:deactivate_input)
      @surface.on_audio_ball_command = nil if @surface.respond_to?(:on_audio_ball_command=)
      @form.delete_timer(@timer) if @form && @timer
      @timer = @surface = @form = nil
      @audio.update(rally_state.snapshot, viewer: listening_side, paused: true) if rally_state.snapshot
    end

    def tick
      return if @closed
      @audio.tick if @audio.respond_to?(:tick)
      return if !@replay || @replay.finished?
      connected = connection_state.connected || @channel.connected?
      @channel.tick
      connection_state.connected = @channel.connected?
      if connected && !connection_state.connected && !host? && @side != nil
        connection_state.resync_requested, rally_state.paused = true, true
      end
    end

    def frame
      return if @closed || !@replay || @replay.finished?
      return if @control_ready == false
      input_flight = incoming_flight
      tick
      now = @clock.call
      synchronize_epoch
      receive_packets(now)
      receive_events
      check_connection(now)
      healthy = healthy?(now)
      active = !session_paused? && healthy && local_ready?(now)
      playable = active && !rally_state.paused
      elapsed = rally_state.last_frame && !rally_state.paused && active && !@clock_reset ? [now - rally_state.last_frame, 0.0].max : 0.0
      @clock_reset = false
      rally_state.last_frame, rally_state.paused = now, !active
      commands = @surface ? @surface.input(@form) : []
      commands = [] if @background_input # Drain, but never replay keys from the covered view.
      allowed_input = playable && @side != nil && !@background_input && !@network_wait && !@settings_open
      flight = incoming_flight
      @selected_lane = @defense_input.update(flight: flight,
        enabled: allowed_input && input_flight && input_flight == flight,
        input: (@surface.defense_input if @surface.respond_to?(:defense_input)), commands: commands)
      @selected_flight = @selected_lane ? flight : nil
      if active
        announce_set
        if allowed_input && rally_state.engine.wrong_turn?(@side) && commands.any? { |command| Engine::SHOTS.include?(command) }
          wrong_turn_press
          commands=[]
        end
        advance_engine(elapsed)
        commands.each do |command|
          next unless allowed_input && rally_state.engine.phase != :flying
          drain_transitions if rally_state.engine.press(@side, command)
        end
      end
      rally_state.snapshot = rally_state.engine&.snapshot
      send_state(now, healthy)
      agree_point(now) if host? && healthy && !session_paused?
      present
    end

    def network_task_ui(**options)
      GameRoomRealtime::TaskUI.new(**options, clock: @clock, tick: -> {
        if GameRoomRealtime::TaskUI.updates_form?(options[:ui], @form)
          # The owned form's existing timer advances the client once.
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

    def show_settings
      return if @settings_open || @closed
      opened_here = true
      @settings_open = true
      @program.send(:show_audio_ball_settings, tick: -> { progress_frame }, clock: @clock)
    ensure
      if opened_here
        @settings_open = false
        @surface.clear_input if @surface.respond_to?(:clear_input)
        @audio.refresh_preferences if @audio.respond_to?(:refresh_preferences)
      end
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

    private

    # Control replacement repeats only the unfinished rally. Audio Ball owns
    # its connection and input state; the table layer knows no physics fields.
    def reset_table_control
      @defense_input.reset
      connection_state.connection_started = @clock.call
      connection_state.epoch = nil
      connection_state.peers, connection_state.connections, rally_state.deferred = {}, {}, []
      connection_state.sequence = connection_state.event_sequence = 0
      point_state.pending_point = point_state.goal_preview = @replay = nil
      rally_state.paused = true
      @surface.clear_input if @surface&.respond_to?(:clear_input)
    end

    def presents_point?
      !@audio.respond_to?(:presents_point) || @audio.presents_point
    end

    def reset_rally
      @defense_input.reset
      @selected_lane = @selected_flight = nil
      server = @replay.state[:server]
      rally_state.engine = server == nil ? nil : Engine.new(level: @replay.state[:options]['difficulty'], server: server,teams:@teams)
      rally_state.snapshot = rally_state.engine&.snapshot
      presentation_state.observer_synced = false
      presentation_state.observer_audio_floor = @last_audio_transition = nil
      bot_sides = host? ? @players.each_index.select { |side| bot_seat?(@players[side]) } : []
      @controlled = ([@side].compact + bot_sides).uniq
      seed = Digest::SHA256.hexdigest("#{@match}:#{connection_state.epoch}:#{@replay.state[:rally]}")[0, 12].to_i(16)
      @bots = bot_sides.map do |side|
        Bot.new(side, level: @replay.state[:options]['difficulty'], rng: Random.new(seed + side))
      end
      point_state.pending_point = point_state.point_reason = presentation_state.warning_key = nil
      @disagreements = {}
      @wrong_request_key=nil
      result = @replay.state[:last_point]
      rally_state.ready_at = result ? point_ready_at(result) : @clock.call
      @ready_deadline_created_at = @clock.call
      rally_state.last_frame = nil
      rally_state.paused = true
      connection_state.next_send = 0.0
      @audio.reset
    end

    def synchronize_epoch
      return unless @channel.epoch && @channel.epoch != connection_state.epoch
      local_connection = local_match?
      connection_state.epoch = @channel.epoch
      connection_state.recovering = false
      connection_state.resync_requested = false
      connection_state.connection_started = @clock.call
      connection_state.connections.clear
      connection_state.peers.clear
      connection_state.sequence = connection_state.event_sequence = 0
      rally_state.deferred.clear
      reset_rally unless local_connection || point_state.pending_point
    end

    def packet_valid?(packet, kind)
      packet.is_a?(Hash) && packet['m'] == @match && packet['e'] == connection_state.epoch &&
        packet['v'] == GameRoomRealtime::Protocol::VERSION && packet['k'] == kind &&
        [packet['n'], packet['a']].all? { |number| number.is_a?(Integer) && number.between?(0, GameRoomRealtime::Protocol::MAX_SEQUENCE) } && packet['d'].is_a?(Hash)
    end

    def receive_packets(now)
      @channel.take_packets.each do |sender, packet|
        name = sender.to_s.downcase
        next unless host? ? @required.any? { |player| player.to_s.casecmp?(name) } : @owner.casecmp?(name)
        next unless packet_valid?(packet, host? ? 'input' : 'state')
        body = packet['d']
        next unless body['r'].is_a?(Integer) && (body['r'] - @replay.state[:rally]).abs <= 1 &&
          body['turn'].is_a?(Integer) && body['turn'].between?(0, 2**31 - 1) &&
          [nil, 0, 1].include?(body['goal']) && [true, false].include?(body['ready']) &&
          (!body.key?('resync') || [true, false].include?(body['resync']))
        connection = (connection_state.connections[name] ||= GameRoomRealtime::PeerState.new)
        next unless connection.receive(packet, now: now, last_sent: connection_state.sequence)
        next unless body['r'] == @replay.state[:rally]
        peer = (connection_state.peers[name] ||= GameRoomRealtime::PeerState.new)
        next unless peer.receive(packet, now: now, last_sent: connection_state.sequence)
        next if session_paused?
        if !host? && @side == nil && rally_state.engine && body['state'].is_a?(Hash) && body['turn'] >= rally_state.engine.turn
          state = body['state']
          next unless state['server'] == @replay.state[:server] && state['level'] == @replay.state[:options]['difficulty'] &&
            state['turn'] == body['turn'] && state['goal'] == body['goal']
          if rally_state.engine.restore(state)
            presentation_state.observer_audio_floor = rally_state.engine.turn unless presentation_state.observer_synced
            presentation_state.observer_synced = true
            connection_state.recovering = false if @channel.connected?
          end
        end
      end
    end

    def receive_events
      return unless rally_state.engine
      @channel.take_events.each do |sender, packet|
        next if !host? && @side == nil && !presentation_state.observer_synced
        next unless packet_valid?(packet, 'event')
        data = packet['d']
        next unless valid_event?(data) && (data['r'] - @replay.state[:rally]).between?(0, 1)
        player = @players[data['side']]
        author = %w[point wrong_turn].include?(data['action']) || bot_seat?(player) ? @owner : player.to_s
        next unless author.casecmp?(sender.to_s) && !sender.to_s.casecmp?(@viewer)
        next if data['action'] == 'warn' && bot_seat?(player)
        next if data['action']=='wrong_press' && !host?
        next if rally_state.deferred.include?(data)
        base_turn = data['r'] == @replay.state[:rally] ? rally_state.engine.turn : 0
        if data['turn'] > base_turn + GameRoomRealtime::EventChannel::LIMIT || rally_state.deferred.length >= GameRoomRealtime::EventChannel::LIMIT
          recover('AudioBallActionGap')
          break
        end
        rally_state.deferred << data
      end
      return if session_paused?
      rally_state.deferred.sort_by! { |data| [data['r'], data['turn'], %w[warn point].include?(data['action']) ? 1 : 0] }
      rally_state.deferred.delete_if do |data|
        next true if data['r'] < @replay.state[:rally]
        next false if data['r'] > @replay.state[:rally]
        if data['action']=='wrong_press'
          next false if data['turn']>rally_state.engine.turn
          if data['turn']==rally_state.engine.turn && !rally_state.paused && local_ready?(@clock.call)
            drain_transitions if rally_state.engine.wrong_turn(data['side'])
          end
          next true
        end
        if data['action']=='wrong_turn' && data['turn']==rally_state.engine.turn
          transition_audio(data) if rally_state.engine.apply(data.reject { |key,_| key=='r' })
          next true
        end
        if data['action'] == 'warn'
          next false if data['turn'] > rally_state.engine.turn
          accept_warning(data)
          next true
        end
        if data['action'] == 'point'
          next false if data['turn'] > rally_state.engine.turn
          preview_goal(data['side']) if !host? && rally_state.engine.turn == data['turn'] && rally_state.engine.goal == data['side']
          next true
        end
        if data['turn'] <= rally_state.engine.turn
          # An observer may receive the owner's current snapshot before the
          # matching reliable event. Present its cue once without applying
          # the transition again or playing historical cues on initial join.
          transition_audio(data) if observer_snapshot_cue?(data)
          next true
        end
        next false if data['turn'] > rally_state.engine.turn + 1
        if rally_state.engine.apply(data.reject { |key, _| key == 'r' })
          note_play_activity if %w[hit defend].include?(data['action'])
          @clock_reset = true
          transition_audio(data)
        end
        true
      end
    end

    def valid_event?(data)
      return false unless data['r'].is_a?(Integer) && data['r'] >= 0 && data['turn'].is_a?(Integer) && data['turn'].between?(0, 2**31 - 1)
      return false unless data['side'].is_a?(Integer) && data['side'].between?(0,data['action']=='point' ? 1 : @players.length-1)
      keys = %w[r action side turn]
      case data['action']
      when 'wrong_press','wrong_turn'
        return false unless @players.length==4
      when 'prepare', 'point'
      when 'hit', 'defend'
        return false unless Engine::SHOTS.include?(data['shot'])
        keys << 'shot'
      when 'miss'
        if data.key?('reason')
          return false unless data['reason'] == 'timeout'
          keys << 'reason'
        end
      when 'warn'
        return false unless data['hits'].is_a?(Integer) && data['hits'].between?(0, 2**31 - 1)
        keys << 'hits'
      else
        return false
      end
      data.keys.sort == keys.sort
    end

    def recover(reason)
      connection_state.resync_requested = true if !host? && @side != nil
      return if connection_state.recovering || @clock.call - connection_state.last_reconnect < 10.0
      connection_state.last_reconnect = @clock.call
      connection_state.recovering, rally_state.paused = true, true
      rally_state.deferred.clear
      @channel.reconnect(reason: reason)
    end

    def check_connection(now)
      return if local_match? || !rally_state.engine
      names = host? ? @required : [@owner]
      expired = names.any? do |name|
        peer = connection_state.connections[name.downcase]
        received = host? ? peer&.ack_updated_at : peer&.received_at
        received ? now - received > STREAM_TIMEOUT : now - connection_state.connection_started > 10.0
      end
      recover('AudioBallStatusTimeout') if expired
      return unless host? && !point_state.pending_point && !session_paused?
      @required.each do |name|
        peer = connection_state.peers[name.downcase]
        if peer && peer.body['resync']
          recover('AudioBallPeerRejoined')
          next
        end
        identity = peer && [rally_state.engine.turn, rally_state.engine.goal, peer.body['turn'], peer.body['goal']]
        if !peer || !peer.fresh?(now, timeout: STREAM_TIMEOUT) || peer.body['r'] != @replay.state[:rally] ||
            (peer.body['turn'] == rally_state.engine.turn && peer.body['goal'] == rally_state.engine.goal)
          @disagreements.delete(name)
        elsif @disagreements[name]&.first != identity
          @disagreements[name] = [identity, now]
        elsif now - @disagreements[name][1] > STREAM_TIMEOUT
          recover('AudioBallActionDisagreement')
        end
      end
    end

    def healthy?(now)
      return false if connection_state.recovering || connection_state.resync_requested || (!host? && @side == nil && !presentation_state.observer_synced)
      return true if local_match?
      return false unless @channel.connected? && @channel.required_members_present?
      if host?
        @required.all? do |name|
          peer = connection_state.peers[name.downcase]
          peer && peer.body['r'] == @replay.state[:rally] && peer.fresh?(now, timeout: STREAM_TIMEOUT) && peer.ack_fresh?(now, timeout: STREAM_TIMEOUT) && peer.body['ready'] && !peer.body['resync']
        end
      else
        peer = connection_state.peers[@owner.downcase]
        peer && peer.body['r'] == @replay.state[:rally] && peer.fresh?(now, timeout: STREAM_TIMEOUT) && peer.body['ready']
      end
    end

    def send_state(now, healthy)
      signature = rally_state.engine && [rally_state.engine.turn, rally_state.engine.goal, rally_state.paused]
      return unless connection_state.epoch && rally_state.engine && (now >= connection_state.next_send || signature != @sent_signature)
      @sent_signature = signature
      connection_state.next_send = now + SEND_INTERVAL
      connection_state.sequence += 1
      body = {'r' => @replay.state[:rally], 'turn' => rally_state.engine.turn, 'goal' => rally_state.engine.goal,
        'ready' => local_ready?(now) && (host? ? !!healthy : true), 'resync' => !!connection_state.resync_requested}
      body['state'] = rally_state.snapshot if host?
      ack = host? ? 0 : connection_state.connections[@owner.downcase]&.sequence.to_i
      @channel.send(GameRoomRealtime::Protocol.encode(match: @match, epoch: connection_state.epoch, sequence: connection_state.sequence,
        kind: host? ? 'state' : 'input', body: body, ack: ack))
    end

    def local_match?
      host? && @required.empty?
    end

    def incoming_flight
      [rally_state.engine, rally_state.engine.turn] if rally_state.engine && rally_state.engine.phase == :flying && rally_state.engine.receiver == @side
    end

    def advance_engine(elapsed)
      return if elapsed > STREAM_TIMEOUT
      while elapsed > 0.000001
        seconds = [elapsed, 0.008].min
        defenses = @selected_lane && @selected_flight == incoming_flight ? {@side => @selected_lane} : {}
        @bots.each do |bot|
          lane = bot.selected_lane(rally_state.engine)
          defenses[bot.side] = lane if lane
        end
        rally_state.engine.step(seconds, controlled: @controlled, defenses: defenses)
        drain_transitions
        @bots.each { |bot| bot.step(rally_state.engine, seconds: seconds); drain_transitions }
        elapsed -= seconds
      end
    end

    def drain_transitions
      while (data = rally_state.engine.take_transition)
        note_play_activity if %w[hit defend].include?(data['action'])
        transition_audio(data)
        emit_event(data)
      end
    end

    def emit_event(data)
      return if !connection_state.epoch || !@channel.connected?
      connection_state.event_sequence += 1
      queued = @channel.send_event(GameRoomRealtime::Protocol.encode(match: @match, epoch: connection_state.epoch, sequence: connection_state.event_sequence,
        kind: 'event', body: data.merge('r' => @replay.state[:rally])))
      recover('AudioBallActionNotQueued') unless queued
    end

    def local_command(command)
      return false unless command == 'hurry' && !@closed && !session_paused? && !rally_state.paused && !@network_wait && !@settings_open && @side != nil && rally_state.engine
      data = {'action' => 'warn', 'side' => @side, 'turn' => rally_state.engine.turn, 'hits' => rally_state.engine.hits}
      return false unless accept_warning(data)
      emit_event(data)
      true
    end

    def accept_warning(data)
      return false unless data['hits'] == rally_state.engine.hits && (rally_state.engine.turn - data['turn']).between?(0, 1)
      return false unless [:waiting, :prepared].include?(rally_state.engine.phase) && @teams[data['side']] != @teams[rally_state.engine.holder]
      key = [@replay.state[:rally], rally_state.engine.hits, rally_state.engine.holder]
      return false if presentation_state.warning_key == key
      return false unless rally_state.engine.warn(data['side']) || (!host? && @side == nil && rally_state.engine.warning)
      presentation_state.warning_key = key
      @clock_reset = true
      @audio.hurry(GameRoomParticipants.display_name(@players[rally_state.engine.holder]))
      true
    end

    def local_ready?(now)
      rally_state.engine != nil && !point_state.pending_point && !connection_state.recovering && !connection_state.resync_requested && now >= rally_state.ready_at
    end

    def listening_side
      @side && @teams ? @teams[@side] : 0
    end

    def wrong_turn_press
      key=[@replay.state[:rally],rally_state.engine.turn]
      return if @wrong_request_key==key
      @wrong_request_key=key
      if host?
        drain_transitions if rally_state.engine.wrong_turn(@side)
      else
        emit_event('action'=>'wrong_press','side'=>@side,'turn'=>rally_state.engine.turn)
      end
    end

    def agree_point(now)
      return if point_state.pending_point || !rally_state.engine || rally_state.engine.goal == nil
      return unless @required.all? do |name|
        peer = connection_state.peers[name.downcase]
        peer && peer.fresh?(now, timeout: STREAM_TIMEOUT) && peer.body['r'] == @replay.state[:rally] &&
          peer.body['turn'] == rally_state.engine.turn && peer.body['goal'] == rally_state.engine.goal
      end
      point_state.pending_point = "#{@replay.state[:rally]}:#{rally_state.engine.goal}"
      point_state.pending_point += ':timeout' if point_state.point_reason == 'timeout'
      # Only the owner, after every human agrees, confirms the goal sound.
      # Scores and match results still wait for the accepted LiveSessions event.
      preview_goal(rally_state.engine.goal)
      emit_event('action' => 'point', 'side' => rally_state.engine.goal, 'turn' => rally_state.engine.turn)
    end

    def preview_goal(winner)
      return if point_state.goal_preview && point_state.goal_preview[:rally] == @replay.state[:rally]
      point_state.goal_preview = {rally: @replay.state[:rally], winner: winner, at: @clock.call}
      options = {viewer: @side && listening_side, winner: winner}
      options[:reason] = 'wrong_turn' if rally_state.engine.snapshot['fault'] != nil
      @audio.goal(**options)
    end

    def point_ready_at(result)
      now = @clock.call
      # Keep the durable five-second set break, also enforced by replay.
      return now + SET_PAUSE if result[:set_finished]
      preview = point_state.goal_preview if point_state.goal_preview && point_state.goal_preview[:rally] == @replay.state[:rally] - 1 &&
        point_state.goal_preview[:winner] == result[:winner]
      preview ? [now, preview[:at] + 3.0].max + (POINT_PAUSE - 3.0) : now + POINT_PAUSE
    end

    def transition_audio(data)
      point_state.point_reason = data['reason'] if data['action'] == 'miss'
      return unless %w[prepare defend].include?(data['action'])
      key = [@replay.state[:rally], data['turn'], data['action']]
      return if @last_audio_transition == key
      @last_audio_transition = key
      @audio.prepare(@teams[data['side']], viewer: listening_side) if data['action'] == 'prepare'
      @audio.stop_ball(@teams[data['side']], viewer: listening_side) if data['action'] == 'defend' && @audio.respond_to?(:stop_ball)
    end

    def observer_snapshot_cue?(data)
      return false if host? || @side != nil || !presentation_state.observer_synced
      return false unless data['turn'] == rally_state.engine.turn && data['turn'] > presentation_state.observer_audio_floor.to_i && rally_state.engine.holder == data['side']
      (data['action'] == 'prepare' && rally_state.engine.phase == :prepared) ||
        (data['action'] == 'defend' && rally_state.engine.phase == :waiting)
    end

    def announce_set
      if @single_point
        view = @side || 0
        left = Preferences.read(@program)['listening_side'] == 'left' ? view : 1 - view
        orientation = [@players[left], @players[1 - left]]
        if @announced_orientation != orientation
          @announced_orientation = orientation
          @audio.announce(GameRoomContent.utf8(_('%{left} is on the left; %{right} is on the right.')) % {
            left: GameRoomContent.utf8(GameRoomParticipants.display_name(orientation[0])),
            right: GameRoomContent.utf8(GameRoomParticipants.display_name(orientation[1]))})
        end
      end
      number = @replay.state[:set_number]
      if presentation_state.announced_set != number
        presentation_state.announced_set = number
        @audio.announce_set(number) unless @single_point
      end
      server = @replay.state[:server]
      receiver = Rotation.seat(@teams, server, 1)
      service = [number, @replay.state[:scores].sum / 2, @players[server], @players[receiver]]
      return if @announced_service == service
      @announced_service = service
      template = @players.length == 2 ? _('%{player} serves.') : _('%{player} serves to %{receiver}.')
      text = GameRoomContent.utf8(template) % {
        player: GameRoomContent.utf8(GameRoomParticipants.display_name(@players[server])),
        receiver: GameRoomContent.utf8(GameRoomParticipants.display_name(@players[receiver]))}
      if @audio.respond_to?(:announce)
        @audio.announce(text)
      else
        announce_progress(text, interrupt: false)
      end
    end

    def present
      return unless rally_state.snapshot
      @surface.present(rally_state.snapshot, pause_status) if @surface
      @audio.update(rally_state.snapshot, viewer: listening_side, paused: rally_state.paused)
    end

    def pause_status
      return '' unless rally_state.paused
      return _('Game paused.') if session_paused?
      return _('Waiting for the point to be saved.') if point_state.pending_point || rally_state.engine&.goal != nil
      result = @replay.state[:last_point]
      if result && @clock.call < rally_state.ready_at
        return result[:set_finished] ? _('Break between sets.') : _('Break between points.')
      end
      _('Waiting for players.')
    end

    def session_pause_changed(paused, elapsed)
      rally_state.paused = true
      @clock_reset = true
      @defense_input.forget_held
      @selected_lane = @selected_flight = nil
      unless paused
        ready_elapsed = @ready_deadline_created_at ? [elapsed, [@clock.call - @ready_deadline_created_at, 0.0].max].min : elapsed
        rally_state.ready_at += ready_elapsed if rally_state.ready_at
        @disagreements&.clear
      end
      rally_state.last_frame = @clock.call
    end
  end
end
