# frozen_string_literal: true
require_relative '../game_room_localization'
require_relative '../game_content'
require_relative 'physics'

module GameRoomBilliards
  module Presentation
    using GameRoomLocalization::Translations
    module_function

    def ball(id, discipline: 'practice')
      if %w[english carom one_cushion three_cushion].include?(discipline)
        return [_('Ball 0, white'), _('Ball 1, yellow'), _('Ball 2, red')].fetch(id)
      end
      if discipline == 'pyramid'
        return id.zero? ? _('Ball 0, coloured') : _('Ball %{number}, white') % {number: id}
      end
      return _('Ball 0, white (cue ball)') if id.zero?
      if discipline == 'snooker'
        format = if id <= 15 then _('Ball %{number}, red')
        else [_('Ball %{number}, yellow'), _('Ball %{number}, green'), _('Ball %{number}, brown'),
          _('Ball %{number}, blue'), _('Ball %{number}, pink'), _('Ball %{number}, black')].fetch(id - 16)
        end
        return format % {number: id}
      end
      format = id == 8 ? _('Ball %{number}, black') : [
        _('Ball %{number}, yellow'), _('Ball %{number}, blue'), _('Ball %{number}, red'),
        _('Ball %{number}, purple'), _('Ball %{number}, orange'), _('Ball %{number}, green'),
        _('Ball %{number}, maroon')][(id > 8 ? id - 9 : id - 1) % 7]
      label = format % {number: id}
      id > 8 ? _('%{ball}, striped') % {ball: label} : label
    end
    def pocket(id)
      [_('Pocket 1, lower left'), _('Pocket 2, lower middle'), _('Pocket 3, lower right'),
        _('Pocket 4, upper left'), _('Pocket 5, upper middle'), _('Pocket 6, upper right')].fetch(id)
    end
    def rail(id)
      {left: _('left cushion'), right: _('right cushion'), top: _('top cushion'),
        bottom: _('bottom cushion'), jaw: _('pocket jaw')}.fetch(id)
    end
    def direction(degrees, clock: false)
      return _('%{angle} degrees') % {angle: format('%.2f', degrees)} unless clock
      hour = ((90 - degrees) / 30.0).round % 12
      _("%{hour} o'clock") % {hour: hour.zero? ? 12 : hour}
    end
    def sector(table, ball)
      columns = [_('left'), _('centre'), _('right')]
      rows = [_('bottom'), _('middle'), _('top')]
      _('%{column}, %{row}') % {column: columns[(ball.x / table.width * 3).to_i.clamp(0, 2)],
        row: rows[(ball.y / table.height * 3).to_i.clamp(0, 2)]}
    end
    def position(table, balls, id, clock: false, cue_id: 0)
      item = balls.find { |b| b.id == id }
      return _('No ball selected.') unless item
      return _('%{ball}: pocketed.') % {ball: ball(id, discipline: table.discipline)} unless item.on_table?
      cue = balls.find { |b| b.id == cue_id && b.on_table? }
      description = _('%{ball}: %{sector}; X %{x} cm, Y %{y} cm.') % {ball: ball(id, discipline: table.discipline), sector: sector(table, item),
        x: format('%.1f', item.x * 100), y: format('%.1f', item.y * 100)}
      if cue && cue != item
        angle = Geometry.angle(item.x - cue.x, item.y - cue.y)
        first = Geometry.trace(table, balls, cue_id, angle)
        description += ' ' + _('Distance %{distance} cm; direction %{direction}.') % {
          distance: format('%.1f', Math.hypot(item.x - cue.x, item.y - cue.y) * 100), direction: direction(angle, clock: clock)}
        description += ' ' + if first && first[:kind] == :ball && first[:id] != id
          _('Blocked by %{ball}.') % {ball: ball(first[:id], discipline: table.discipline)}
        else
          _('Direct contact is available.')
        end
      end
      GameRoomContent.utf8(description)
    end
    def target(contact, discipline: 'practice')
      return _('Place the cue ball before aiming.') unless contact
      if contact[:kind] == :ball
        contact_type = if contact[:offset].abs < 0.15
          _('centre')
        elsif contact[:offset] < 0
          _('right edge')
        else
          _('left edge')
        end
        _('%{ball}, %{contact}.') % {ball: ball(contact[:id], discipline: discipline), contact: contact_type}
      else
        contact[:kind] == :rail ? rail(contact[:id]) : pocket(contact[:id])
      end
    end
    def behind(contacts, discipline: 'practice')
      first, *following = contacts
      return target(first, discipline: discipline) unless first && first[:kind] == :ball
      labels = following.map do |contact|
        case contact[:kind]
        when :ball then ball(contact[:id], discipline: discipline)
        when :rail then rail(contact[:id])
        when :pocket then pocket(contact[:id])
        end
      end
      return _('%{ball}; nothing further.') % {ball: ball(first[:id], discipline: discipline)} if labels.empty?
      GameRoomContent.utf8(_('%{ball}; further: %{targets}.') % {ball: ball(first[:id], discipline: discipline), targets: labels.join('; ')})
    end
    def parameters(shot)
      _('Angle %{angle} degrees; power %{power} percent; top/back spin %{top}; right/left spin %{side}.') % {
        angle: format('%.2f', shot['angle'] / 100.0), power: format('%.1f', shot['power'] / 10.0), top: shot['top'], side: shot['side']}
    end
    def rebound(result, discipline: 'practice', cue_id: 0)
      contacts = result.events.select { |e| [:ball, :rail, :pocket].include?(e[:kind]) && (e[:a] == cue_id || e[:kind] == :ball && e[:b] == cue_id) }
      first = contacts.first
      return _('At this power, the cue ball stops before reaching a cushion.') unless first
      return _('The cue ball reaches %{target} before a cushion.') % {target: first[:kind] == :ball ?
        ball(first[:a] == cue_id ? first[:b] : first[:a], discipline: discipline) : pocket(first[:pocket])} unless first[:kind] == :rail
      text = _('Rebound from the %{cushion}.') % {cushion: rail(first[:rail])}
      target = contacts.find { |e| e[:kind] == :ball || e[:kind] == :pocket }
      count = contacts.take_while { |e| !e.equal?(target) }.count { |e| e[:kind] == :rail }
      following = if target && target[:kind] == :ball
        _('After %{count} cushion contacts, the cue ball hits %{ball}.') % {count: count, ball: ball(target[:a] == cue_id ? target[:b] : target[:a], discipline: discipline)}
      elsif target
        _('After %{count} cushion contacts, the cue ball enters %{pocket}.') % {count: count, pocket: pocket(target[:pocket])}
      else
        _('No object ball is reached after the rebound.')
      end
      GameRoomContent.utf8(text + ' ' + following)
    end
    def contact(event, discipline: 'practice')
      case event[:kind]
      when :cue then _('Cue strike.')
      when :ball then _('%{first} hits %{second}.') % {first: ball(event[:a], discipline: discipline), second: ball(event[:b], discipline: discipline)}
      when :rail then _('%{ball} hits the %{cushion}.') % {ball: ball(event[:a], discipline: discipline), cushion: rail(event[:rail])}
      when :pocket then _('%{ball} enters the %{pocket}.') % {ball: ball(event[:a], discipline: discipline), pocket: pocket(event[:pocket])}
      when :crossing
        message = {head: _('%{ball} crosses the head string.'), middle: _('%{ball} crosses the centre line.'),
          baulk: _('%{ball} crosses the baulk line.')}.fetch(event[:line])
        message % {ball: ball(event[:a], discipline: discipline)}
      when :zone_exit then _('%{ball} leaves corner zone %{number}.') % {ball: ball(event[:a], discipline: discipline), number: event[:zone] + 1}
      end
    end
    def summary(result, discipline: 'practice', cue_id: nil)
      cue_id ||= result.events.find { |e| e[:kind] == :cue }&.dig(:a) || 0
      first = result.events.find { |e| e[:kind] == :ball && (e[:a] == cue_id || e[:b] == cue_id) }
      pots = result.events.select { |e| e[:kind] == :pocket }
      text = first ? _('First contact: %{ball}.') % {ball: ball(first[:a] == cue_id ? first[:b] : first[:a], discipline: discipline)} : _('No object ball was hit.')
      text += ' ' + (pots.empty? ? _('No balls pocketed.') : pots.map { |e| contact(e, discipline: discipline) }.join(' '))
      GameRoomContent.utf8(text)
    end
    def cue(event)
      {cue: 'billiards_cue', ball: 'billiards_collision', rail: 'billiards_cushion', pocket: 'billiards_pocket'}[event[:kind]]
    end

    def object_prediction(result, id, discipline: 'practice')
      name = ball(id, discipline: discipline)
      contacts = result.events.select { |e| [:ball, :rail, :pocket].include?(e[:kind]) && (e[:a] == id || e[:kind] == :ball && e[:b] == id) }
      first = contacts.index { |e| e[:kind] == :ball }
      return _('%{ball}: this shot will not reach it.') % {ball: name} unless first
      after = contacts.drop(first + 1)
      labels = after.first(3).map do |e|
        case e[:kind]
        when :rail then rail(e[:rail])
        when :ball then ball(e[:a] == id ? e[:b] : e[:a], discipline: discipline)
        when :pocket then pocket(e[:pocket])
        end
      end.compact
      pot = after.find { |e| e[:kind] == :pocket }
      ending = pot ? pocket(pot[:pocket]) : _('stops on the table')
      labels << ending unless labels.last == ending
      GameRoomContent.utf8(_('%{ball}: %{path}.') % {ball: name, path: labels.join('; ')})
    end
  end
end
