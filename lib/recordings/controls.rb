require_relative 'information'

module GameRoomRecordings
  # One set of currently usable actions drives both the native context menu
  # and F1. Native button/arrows handle non-letter keys; letters use native
  # symbol shortcuts. No hidden Ctrl-only duplicates.
  class Controls
    using GameRoomLocalization::Translations
    attr_reader :information

    def initialize(player,position_text:,speaker:)
      @player,@position_text,@speaker=player,position_text,speaker
      @information=Information.new(player)
    end

    def operations
      rows=[[@player.playing ? :pause : :play,@player.playing ? _('Pause replay') : _('Play replay'),:space]]
      rows << [:back,_('Back 5 seconds'),:left] if @player.position>0
      rows << [:forward,_('Forward 5 seconds'),:right] if @player.position<@player.duration
      [[:action,:previous_action,:next_action,_('Previous action'),_('Next action'),:a,:n],
       [:point,:previous_point,:next_point,_('Previous point'),_('Next point'),:g,:h],
       [:set,:previous_set,:next_set,_('Previous set'),_('Next set'),:u,:j]].each do |kind,previous,following,back,next_label,back_key,next_key|
        rows << [previous,back,back_key] if @player.navigable?(kind,-1)
        rows << [following,next_label,next_key] if @player.navigable?(kind,1)
      end
      rows << [:beginning,_('Beginning'),:k] if @player.position>0
      rows << [:end,_('End'),:e] if @player.position<@player.duration
      rows << [:scores,_('read scores'),:s] if @player.frame
      rows << [:server,_('read the server'),:t] if @player.frame&.dig('snapshot','server').is_a?(Integer)
      rows << [:information,_('Playback position'),:l]
      information.perspectives.each_with_index do |(seat,name),index|
        next if index==information.perspective_index
        rows << [[:perspective,seat],_('Perspective: %{player}.') % {player:name},(index+1).to_s.to_sym]
      end
      rows
    end

    def key_label(key)
      case key
      when :space then _('Space')
      when :left then _('Left arrow')
      when :right then _('Right arrow')
      else key.to_s.upcase
      end
    end

    def context_key(key)
      %i[space left right].include?(key) ? '' : key
    end

    def perform(action)
      return false unless operations.any? { |row| row[0]==action }
      case action
      when :play then @player.play
      when :pause then @player.pause
      when :back then @player.seek_by(-5000)
      when :forward then @player.seek_by(5000)
      when :previous_action then @player.navigate(:action,-1)
      when :next_action then @player.navigate(:action,1)
      when :previous_point then @player.navigate(:point,-1)
      when :next_point then @player.navigate(:point,1)
      when :previous_set then @player.navigate(:set,-1)
      when :next_set then @player.navigate(:set,1)
      when :beginning then @player.seek(0)
      when :end then @player.seek(@player.duration)
      when :scores then @speaker.call(information.message('scores'))
      when :server then @speaker.call(information.message('server'))
      when :information then @speaker.call(@position_text.call(@player))
      when Array
        @player.seat=action[1]
        name=information.perspectives.find { |seat,_| seat==action[1] }[1]
        @speaker.call(_('Perspective: %{player}.') % {player:name})
      end
      true
    end
  end
end
