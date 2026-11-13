require_relative 'rules'

module GameRoomBilliards
  module SpatialAudio
    module_function
    # Listen from the middle of the lower long cushion, facing up the table.
    def position(table, contact)
      return nil unless contact
      x, y = contact.values_at(:x, :y)
      x, y = table.pockets[contact[:id]] if contact[:kind] == :pocket && x.nil? && contact[:id].is_a?(Integer) && contact[:id].between?(0, 5)
      return nil unless [x, y].all? { |value| value.is_a?(Numeric) && value.finite? }
      dx, dz = x - table.width / 2, -(y + 0.35)
      length = Math.hypot(dx, dz)
      return nil if length <= 1e-9
      [dx / length, 0.0, dz / length]
    end
  end
end
