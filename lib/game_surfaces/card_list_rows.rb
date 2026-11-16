module GameSurfaces
  # Informational rows share the native list, never its physical hand IDs.
  module CardListRows
    private

    def leading_rows(zone)
      rows = zone.leading_rows.to_a
      unless rows.all? { |row| row.is_a?(CardListRow) && !row.id.to_s.empty? && !row.label.to_s.empty? } &&
          rows.map { |row| row.id.to_s }.uniq.length == rows.length
        raise ArgumentError, 'leading card-list rows require unique IDs and labels'
      end
      rows
    end

    def card_index_for(zone, control)
      control.index.to_i - leading_rows(zone).length
    end

    def restore_leading_cursor(zone, cards, remembered, index, changed)
      id = remembered.fetch('selected_leading_rows', {})[zone.id.to_s]
      return [index, changed] unless id
      if zone.hand_order != nil
        cursor = remembered.fetch('hand_cursors', {})[zone.id.to_s]
        return [index, changed] unless cursor && cursor['epoch'] == zone.hand_epoch.to_s
        return [index, changed] if zone.select_drawn != false && !(zone.hand_order.map(&:to_s) - cursor.fetch('raw_ids')).empty?
      end
      rows = leading_rows(zone)
      position = rows.index { |row| row.id.to_s == id }
      position ? [position - rows.length, false] : [index, changed]
    end

    def activate_leading_row(zone)
      action = zone.activation_action
      emit_action(action.kind, action.name, action.payload, source: action.source) if action
    end
  end
end
