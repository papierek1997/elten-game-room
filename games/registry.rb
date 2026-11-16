# encoding: UTF-8
module GameRoomGames
  class Registry
    def initialize(game_types)
      @game_types = {}
      game_types.each do |game_type|
        game = game_type.new
        id = game.id.to_s
        raise ArgumentError, "a game must have an id" if id.empty?
        raise ArgumentError, "duplicate game id: #{id}" if @game_types.key?(id)

        game.card_hand_order if game.respond_to?(:card_hand_order)
        game.rule_book

        @game_types[id] = game_type
      end
    end

    def ids
      @game_types.keys.sort_by { |id| [self.class.sort_key(name(id)),id] }
    end

    # Polish letters have their own positions, rather than sorting after Z.
    # The same alphabet also retains the usual order of English names.
    SORT_ALPHABET = (('0'..'9').to_a + %w[a ą b c ć d e ę f g h i j k l ł m n ń o ó p q r s ś t u v w x y z ź ż]).freeze
    def self.sort_key(label)
      text = label.to_s.dup
      text.force_encoding(Encoding::UTF_8) if text.encoding == Encoding::ASCII_8BIT
      text = text.encode(Encoding::UTF_8, invalid: :replace, undef: :replace).downcase
      text = UnicodeNormalize.normalize(text,:nfc) if defined?(UnicodeNormalize)
      text.each_char.map { |char| char == ' ' ? 0 : (SORT_ALPHABET.index(char) || 1000+char.ord)+1 }
    end

    def build(id)
      game_type = @game_types[id.to_s]
      game_type == nil ? nil : game_type.new
    end

    def name(id)
      game = build(id)
      game == nil ? nil : game.name
    end

    def tournament_capabilities(id, options: {})
      game = build(id)
      game && game.tournament_capabilities(options: options)
    end

    def tournament_ids
      ids.select { |id| !tournament_capabilities(id)[:player_counts].empty? }
    end
  end
end
