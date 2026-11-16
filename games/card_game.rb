require "digest"
require_relative "base"
require_relative "../lib/card_deck_history"
require_relative "../lib/game_random"

require_relative "../lib/game_room_localization"

module GameRoomGames
  using GameRoomLocalization::Translations
  # Shared deterministic card helpers.  Games still own their rules and event
  # payloads, but they use one shuffle, labelling and hand presentation model.
  class CardGame < Base
    include GameRoomCardDeckHistory
    CARD_SUITS = %w[C D H S].freeze
    CARD_RANKS = %w[2 3 4 5 6 7 8 9 T J Q K A].freeze

    def perfect_information?
      false
    end

    protected

    def standard_deck(jokers: 0)
      deck = CARD_SUITS.flat_map { |suit| CARD_RANKS.map { |rank| "#{rank}#{suit}" } }
      jokers.to_i.times { |index| deck << "X#{index + 1}" }
      deck
    end

    def shuffled_cards(cards, seed)
      seed_text = seed.to_s
      numeric_seed = seed_text.match?(/\A[0-9a-f]+\z/i) ? seed_text.to_i(16) : Digest::SHA256.hexdigest(seed_text).to_i(16)
      random = Random.new(numeric_seed)
      GameRoomRandom.shuffle(cards, random: random)
    end

    def card_seed(source)
      source.roll(count: 16, sides: 256).values.map do |item|
        (item.to_i - 1).to_s(16).rjust(2, "0")
      end.join
    end

    def playing_card_rank(card)
      card.to_s[0]
    end

    def playing_card_suit(card)
      card.to_s[1]
    end

    def playing_card_label(card)
      return _("joker") if playing_card_rank(card) == "X"

      ranks = {
        "T" => _("10"), "J" => _("jack"), "Q" => _("queen"),
        "K" => _("king"), "A" => _("ace")
      }
      suits = {
        "C" => _("clubs"), "D" => _("diamonds"),
        "H" => _("hearts"), "S" => _("spades")
      }
      _("%{rank} of %{suit}") % {
        rank: ranks.fetch(playing_card_rank(card), playing_card_rank(card)),
        suit: suits.fetch(playing_card_suit(card), playing_card_suit(card))
      }
    end

    def playing_card_sort_key(card)
      [
        CARD_SUITS.index(playing_card_suit(card)) || CARD_SUITS.length,
        CARD_RANKS.index(playing_card_rank(card)) || CARD_RANKS.length,
        card.to_s
      ]
    end

    def card_hand_surface(cards, header: _("Your hand"), zone: "hand", choices: nil, hand_epoch: nil)
      visible = cards.to_a.sort_by { |card| playing_card_sort_key(card) }.map do |card|
        GameSurfaces::Card.new(
          id: card,
          label: playing_card_label(card),
          value: card,
          navigation_group: standard_hand_navigation_group(rank: playing_card_rank(card), suit: playing_card_suit(card)),
          sort_keys: standard_hand_sort_keys(rank: playing_card_rank(card), suit: playing_card_suit(card), position: cards.index(card)),
          choices: choices.respond_to?(:call) ? choices.call(card) : nil
        )
      end
      GameSurfaces::CardTableSpec.new(
        zones: [
          GameSurfaces::CardZoneSpec.new(
            id: zone,
            header: header,
            cards: visible,
            hand_order: cards.to_a.dup, hand_epoch: hand_epoch,
            empty_label: _("Your hand is empty")
          )
        ]
      )
    end
  end
end
