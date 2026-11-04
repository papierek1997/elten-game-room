require_relative '../game_surfaces/specifications'
require_relative '../game_surfaces/realtime_information'

module GameRoomRecordings
  class Information
    using GameRoomLocalization::Translations

    def initialize(player)
      @player=player
    end

    def players
      @player.metadata.fetch('players')
    end

    def teams
      frame=@player.frame
      source=frame && (frame.dig('snapshot','teams') || frame['teams'])
      valid=source==[0,1] || (source.is_a?(Array) && source.size==4 && source.count(0)==2 && source.count(1)==2)
      valid && source.size==players.size ? source : (players.size==4 ? [0,1,0,1] : [0,1])
    end

    def score_labels
      return players if players.size==2
      [0,1].map do |team|
        names=players.each_index.select { |seat| teams[seat]==team }.map { |seat| players[seat] }
        if @player.metadata['game']=='axel_pong'
          _('Team %{team}: %{players}') % {team:%w[A B][team],
            players:_('%{first} and %{second}') % {first:names[0],second:names[1]}}
        else
          names.join(', ')
        end
      end
    end

    def perspectives
      if @player.metadata['game']=='axel_pong'
        players.each_with_index.map { |name,seat| [seat,name] }
      else
        score_labels.each_with_index.map { |name,team| [teams.index(team),name] }
      end
    end

    def perspective_index
      perspectives.index { |seat,_| @player.metadata['game']=='axel_pong' ? seat==@player.seat : teams[seat]==teams[@player.seat] }
    end

    def message(command)
      frame=@player.frame
      return unless frame
      snapshot=frame['snapshot']
      if @player.metadata['game']=='axel_pong'
        spec=GameSurfaces::PongSpec.new(players:players,viewer:nil,scores:frame['scores'],
          score_labels:players.size==4 ? score_labels : nil)
        GameSurfaces::RealtimeInformation.pong(command,spec:spec,snapshot:snapshot,listening_seat:@player.seat)
      else
        spec=GameSurfaces::AudioBallSpec.new(players:players,viewer:nil,scores:frame['scores'],
          sets:frame['sets'],teams:teams,score_labels:score_labels)
        GameSurfaces::RealtimeInformation.audio_ball(command,spec:spec,snapshot:snapshot)
      end
    end
  end
end
