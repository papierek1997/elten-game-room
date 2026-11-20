module GameRoomTest
  module CardHandOrderContract
    def self.check(game, spec, options: {})
      case spec
      when GameSurfaces::CompositeSpec
        spec.parts.each { |part| check(game, part.surface, options: options) }
      when GameSurfaces::CardTableSpec, GameSurfaces::MeldHandSpec
        check_hand(game, spec, options) if spec.zones.any? { |zone| zone.hand_order != nil }
      when GameSurfaces::PacketCardSpec
        check_hand(game, spec, options) if spec.hand_order != nil
      end
    end

    def self.check_hand(game, spec, options)
      unless game.class.const_defined?(:CARD_HAND_ORDER, false)
        raise "#{game.id}: a card game must explicitly declare CARD_HAND_ORDER"
      end
      order = game.card_hand_order(options: options)
      unless order.is_a?(GameRoomGames::CardHandOrder) && spec.default_sort == order.default_sort && spec.sort_modes == order.sort_modes
        raise "#{game.id}: marked hand default disagrees with its declared card order"
      end
    end
    private_class_method :check_hand
  end
end
