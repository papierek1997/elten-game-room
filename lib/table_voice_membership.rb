require_relative 'table_voice_protocol'

# Local identities survive a cleared invitation and the table form's lifetime.
# Never infer ownership from a channel number alone or disconnect another call.
class GameRoomTableVoiceMembership
  def initialize(conference:)
    @conference, @tables = conference, {}
  end
  def remember(table)
    voice=table['voice']
    # Native join acknowledges before its channel update reaches the UI.
    # Retain the accepted invitation now; depart still checks the exact
    # connected ID and name before touching Conference.
    return unless GameRoomTableVoice.valid?(voice) && voice['status']=='ready'
    @tables[table['__id']]=voice.dup.freeze
    @tables.shift while @tables.size>16
  end
  def connected?(table)
    GameRoomTableVoice.connected?(table['voice'],@conference) ||
      GameRoomTableVoice.connected?(@tables[table['__id']],@conference)
  end
  def depart(table, disconnect: true)
    remember(table)
    voice=@tables[table['__id']]
    if disconnect && GameRoomTableVoice.connected?(voice,@conference)
      return false unless @conference.leave
    end
    @tables.delete(table['__id'])
    true
  end
end
