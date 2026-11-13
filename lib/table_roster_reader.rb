require_relative 'game_room_background'
require_relative 'game_participants'
require_relative 'game_room_localization'
require_relative 'game_content'

# One explicit request for one view; late replies cannot speak over another
# table, a newly focused control, or a reopened list. No joining or polling.
class GameRoomTableDetailsReader
  using GameRoomLocalization::Translations

  def initialize(loader:, selected:, id_for:, active:, speaker:, worker: nil, formatter:, unavailable:)
    @loader, @selected, @id_for, @active, @speaker = loader, selected, id_for, active, speaker
    @formatter, @unavailable = formatter, unavailable
    runtime = Programs.current_runtime if defined?(Programs) && Programs.respond_to?(:current_runtime)
    @worker = worker || GameRoomBackground::Work.new(runtime: runtime)
    @generation = 0
  end

  def invalidate; @generation += 1; end
  def close; invalidate; @worker.close; end

  def request
    return false if @worker.busy? || @worker.closed? || !@active.call
    snapshot = @selected.call
    unless snapshot
      say(_('No table selected.'))
      return false
    end
    request = [@generation, @id_for.call(snapshot).to_s]
    if GameRoomBackground.admit(@worker) { @loader.call(snapshot) }
      @request = request
      true
    else
      say(@unavailable.call)
      false
    end
  end

  def update
    result = @worker.take
    return unless result
    snapshot = @selected.call
    return unless @active.call && snapshot && @request == [@generation, @id_for.call(snapshot).to_s]
    value, error = result
    if error || !value || value[:status] == :unavailable
      say(@unavailable.call)
    elsif value[:status] == :closed
      say(_('This table is no longer available.'))
    elsif value[:status] == :ready
      say(@formatter.call(value) || @unavailable.call)
    else
      say(@unavailable.call)
    end
  end

  private

  def say(text)
    @speaker.call(GameRoomContent.utf8(text))
  end
end

class GameRoomTableRosterReader < GameRoomTableDetailsReader
  using GameRoomLocalization::Translations
  def initialize(**options)
    super(**options, unavailable: -> { _('The table participants are currently unavailable.') }, formatter: ->(value) {
      players = value.fetch(:players).map { |person| GameRoomParticipants.scoped_display_name(person, value[:display_names]) }
      observers = value.fetch(:observers).map { |person| GameRoomParticipants.scoped_display_name(person, value[:display_names]) }
      message = players.empty? ? _('No players at this table.') : _('Players: %{players}.') % {players: players.join(', ')}
      message += ' ' + (_('Observers: %{players}.') % {players: observers.join(', ')}) unless observers.empty?
      message
    })
  end
end

class GameRoomTableOptionsReader < GameRoomTableDetailsReader
  using GameRoomLocalization::Translations
  def initialize(game_for:, **options)
    super(**options, unavailable: -> { _('The settings of this table are not available.') }, formatter: ->(value) {
      game = game_for.call(value[:game])
      game.table_options_announcement(game.options_from_json(value[:options])) if game && !value[:options].to_s.empty?
    })
  end
end
