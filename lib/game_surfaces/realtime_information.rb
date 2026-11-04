require_relative '../game_room_localization'
require_relative '../audio_ball/rotation'

module GameSurfaces
  # Read-only announcements shared by the live playfields and passive replays.
  # No keyboard, engine, connection or audio device is needed to describe a frame.
  module RealtimeInformation
    using GameRoomLocalization::Translations
    module_function

    def pong(command, spec:, snapshot:, status: '', listening_seat: nil)
      case command
      when 'scores'
        if spec.score_labels
          spec.score_labels.each_with_index.map do |label, i|
            _('%{team}. Points: %{points}.') % {team: label, points: spec.scores[i]}
          end.join(' ')
        else
          [0, 1].sort_by { |i| [-spec.scores[i].to_i, i] }.map do |i|
            "#{spec.players[i]}, #{spec.scores[i]}"
          end.join('. ')
        end
      when 'server'
        text = if snapshot && spec.score_labels
          _('%{server} will serve against %{receiver}.') % {
            server: spec.players[snapshot['server']], receiver: spec.players[snapshot['receiver']]}
        elsif snapshot
          _('%{player} serves.') % {player: spec.players[snapshot['server']]}
        else
          ''
        end
        [text, status].reject(&:empty?).join(' ')
      when 'position'
        seat = spec.viewer || listening_seat
        x = snapshot && seat.is_a?(Integer) && snapshot['p'][seat]
        if x && spec.viewer.nil?
          _('%{player}: %{position}.') % {
            player: GameRoomParticipants.display_name(spec.players[seat]), position: x.round}
        else
          x ? (_('Paddle: %{position}.') % {position: x.round}) : status
        end
      when 'effects'
        return status unless snapshot
        parts = snapshot['shields'].each_with_index.filter_map do |ticks, i|
          _('%{player}: shield, %{seconds} seconds.') % {
            player: spec.players[i], seconds: (ticks * 0.016).ceil} if ticks > 0
        end
        parts << _('The ball is invisible.') if snapshot['invisible']
        parts.empty? ? _('No active effects.') : parts.join(' ')
      end
    end

    def audio_ball(command, spec:, snapshot:, status: '')
      case command
      when 'scores'
        (spec.score_labels || spec.players).each_with_index.map do |player, side|
          _('%{player}. Points: %{points}. Sets: %{sets}.') % {
            player: GameRoomContent.utf8(player), points: spec.scores[side], sets: spec.sets[side]}
        end.join(' ')
      when 'server'
        server = snapshot && snapshot['server']
        text = ''
        if server.is_a?(Integer) && server.between?(0, spec.players.length - 1)
          receiver = GameRoomAudioBall::Rotation.seat(spec.teams || [0, 1], server, 1)
          template = spec.players.length == 2 ? _('%{player} serves.') : _('%{player} serves to %{receiver}.')
          text = GameRoomContent.utf8(template) % {
            player: GameRoomContent.utf8(spec.players[server]), receiver: GameRoomContent.utf8(spec.players[receiver])}
        end
        [text, status].reject(&:empty?).join(' ')
      end
    end
  end
end
