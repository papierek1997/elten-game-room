require_relative 'game_room_localization'
require_relative 'game_room_server_tables'

# Presentation only: no probes, settings changes or network work. A launcher
# refusal and an inconclusive connection check must not share a diagnosis.
module GameRoomAvailability
  using GameRoomLocalization::Translations
  module_function

  def reason(tables, error: nil)
    if tables&.stamp_required? || (error.respond_to?(:code) && error.code.to_s == GameRoomServerTables::STAMP_REQUIRED)
      _('Server table access was denied because Elten did not provide confirmation from its official launcher. You are most likely using developer mode. Start Elten normally with its official launcher, then reopen Power Games.')
    else
      _('Server table access could not be confirmed. Check your connection. If you are using developer mode, start Elten normally with its official launcher, then reopen Power Games.')
    end
  end

  def unavailable(feature, tables:, developer: $developer_mode == true, error: nil)
    if !error && tables&.available?
      return statistics_disabled if developer && [:statistics, :room_activity].include?(feature)
      return nil
    end
    description = case feature
    when :rankings then _('Rankings are unavailable without server table access.')
    when :tournaments then _('Tournaments are unavailable without server table access.')
    when :statistics then _('Statistics are unavailable without server table access.')
    when :invitations then _('Sending invitations is unavailable without server table access.')
    when :subscriptions then _('New-table notification subscriptions are unavailable without server table access. You can still change other settings.')
    when :room_activity then _('Room activity is unavailable without server table access.')
    else raise ArgumentError, "Unknown server feature: #{feature}"
    end
    [description, reason(tables, error: error)].join(' ')
  end

  def startup(tables:, developer: $developer_mode == true)
    if tables&.available?
      return statistics_disabled if developer
      return nil
    end
    [_('Server features are unavailable: global lobby history, sending invitations, new-table notification subscriptions, tournaments, rankings and statistics.'),
      reason(tables), _('You can still create and join ordinary games.')].join(' ')
  end

  def table(tables:, ranked:, developer: $developer_mode == true)
    unless tables&.available?
      description = if ranked
        _('This Elten session will not send game statistics or ranking results because server table access has not been confirmed.')
      else
        _('This Elten session will not send game statistics because server table access has not been confirmed.')
      end
      return [description, reason(tables)].join(' ')
    end
    return nil unless developer
    [statistics_disabled, (_('Rankings remain available because server table access is confirmed.') if ranked)].compact.join(' ')
  end

  def statistics_disabled
    _('Statistics are disabled in developer mode. Games played in this mode are not included in server statistics.')
  end
end
