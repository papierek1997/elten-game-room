# frozen_string_literal: true

require_relative '../../lib/game_room_localization'

module GameRoomGames
  module CategoriesCatalog
    using GameRoomLocalization::Translations

    # Keep the supplied order and assign each category the first difficulty
    # at which it can be drawn. Translate labels at display time.
    CATEGORIES = {
      "country" => ["easy", -> { _("Country") }],
      "capital_city" => ["medium", -> { p_("categories", "Capital city") }],
      "city" => ["easy", -> { _("City") }],
      "river" => ["medium", -> { p_("categories", "River") }],
      "body_of_water" => ["medium", -> { p_("categories", "Lake, sea or ocean") }],
      "mountain" => ["medium", -> { _("Mountain") }],
      "island" => ["medium", -> { _("Island") }],
      "male_first_name" => ["easy", -> { p_("categories", "Male first name") }],
      "female_first_name" => ["easy", -> { p_("categories", "Female first name") }],
      "mammal" => ["easy", -> { p_("categories", "Mammal") }],
      "bird" => ["easy", -> { p_("categories", "Bird") }],
      "fish" => ["easy", -> { p_("categories", "Fish") }],
      "insect" => ["easy", -> { p_("categories", "Insect") }],
      "tree_or_shrub" => ["easy", -> { p_("categories", "Tree or shrub") }],
      "flower" => ["easy", -> { p_("categories", "Flower") }],
      "vegetable" => ["easy", -> { p_("categories", "Vegetable") }],
      "fruit" => ["easy", -> { p_("categories", "Fruit") }],
      "profession" => ["easy", -> { _("Profession") }],
      "food" => ["easy", -> { _("Food") }],
      "soft_drink" => ["easy", -> { p_("categories", "Non-alcoholic drink") }],
      "cocktail_name" => ["hard", -> { p_("categories", "Cocktail name") }],
      "alcohol_type" => ["medium", -> { p_("categories", "Type of alcoholic drink") }],
      "alcohol_brand" => ["hard", -> { p_("categories", "Alcohol brand") }],
      "cosmetic_type" => ["easy", -> { p_("categories", "Type of cosmetic product") }],
      "color" => ["easy", -> { _("Color") }],
      "individual_sport" => ["medium", -> { p_("categories", "Individual sport") }],
      "team_sport" => ["medium", -> { p_("categories", "Team sport") }],
      "male_athlete" => ["medium", -> { p_("categories", "Famous male athlete") }],
      "female_athlete" => ["medium", -> { p_("categories", "Famous female athlete") }],
      "vehicle" => ["easy", -> { _("Vehicle") }],
      "clothing" => ["easy", -> { _("Clothing item") }],
      "body_part" => ["easy", -> { _("Body part") }],
      "tool" => ["easy", -> { _("Tool") }],
      "musical_instrument" => ["easy", -> { _("Musical instrument") }],
      "film" => ["medium", -> { _("Film") }],
      "tv_series_or_cartoon" => ["medium", -> { p_("categories", "Series or cartoon") }],
      "music_group" => ["medium", -> { _("Music group") }],
      "male_actor" => ["medium", -> { p_("categories", "Male actor") }],
      "actress" => ["medium", -> { p_("categories", "Actress") }],
      "male_singer" => ["medium", -> { p_("categories", "Male singer") }],
      "female_singer" => ["medium", -> { p_("categories", "Female singer") }],
      "male_writer" => ["hard", -> { p_("categories", "Male writer") }],
      "female_writer" => ["hard", -> { p_("categories", "Female writer") }],
      "historical_figure" => ["medium", -> { p_("categories", "Historical figure") }],
      "screen_character" => ["hard", -> { p_("categories", "Film or TV series character") }],
      "book_character" => ["hard", -> { p_("categories", "Book character") }],
      "mythological_deity" => ["hard", -> { p_("categories", "Mythological deity") }],
      "language" => ["easy", -> { _("Language") }],
      "hobby" => ["easy", -> { p_("categories", "Hobby") }],
      "video_game" => ["medium", -> { p_("categories", "Video game") }],
      "board_or_card_game" => ["medium", -> { p_("categories", "Board or card game") }],
      "childrens_game" => ["medium", -> { p_("categories", "Children's game or pastime") }],
      "furniture" => ["easy", -> { p_("categories", "Piece of furniture") }],
      "room_in_house" => ["easy", -> { p_("categories", "Room in a home") }],
      "electronic_device" => ["easy", -> { p_("categories", "Electronic device") }],
      "kitchen_utensil" => ["easy", -> { p_("categories", "Kitchen utensil") }],
      "car_brand" => ["medium", -> { p_("categories", "Car brand") }],
      "phone_brand" => ["medium", -> { p_("categories", "Phone brand") }],
      "computer_brand" => ["medium", -> { p_("categories", "Computer brand") }],
      "field_of_science" => ["hard", -> { p_("categories", "Field of science") }],
      "astronomical_object" => ["hard", -> { p_("categories", "Astronomical object") }],
      "currency" => ["medium", -> { p_("categories", "Currency") }],
      "tv_channel" => ["medium", -> { p_("categories", "TV channel") }],
      "reality_show" => ["hard", -> { p_("categories", "Reality show") }],
      "disease" => ["hard", -> { p_("categories", "Disease") }],
      "tv_game_show" => ["hard", -> { p_("categories", "TV game show") }],
      "dairy_product" => ["medium", -> { p_("categories", "Cheese or dairy product") }],
      "scientist" => ["hard", -> { p_("categories", "Scientist") }],
      "philosopher" => ["hard", -> { p_("categories", "Philosopher") }],
      "comedian" => ["hard", -> { p_("categories", "Comedian") }],
      "tv_presenter" => ["hard", -> { p_("categories", "TV presenter") }],
      "radio_presenter" => ["hard", -> { p_("categories", "Radio presenter") }],
      "sewing_material" => ["hard", -> { p_("categories", "Sewing material") }],
      "jewelry_material" => ["hard", -> { p_("categories", "Jewelry material") }],
      "exercise_equipment" => ["hard", -> { p_("categories", "Exercise equipment") }],
      "weapon" => ["hard", -> { p_("categories", "Weapon") }],
      "dance" => ["medium", -> { p_("categories", "Dance") }],
      "politician" => ["hard", -> { p_("categories", "Politician") }],
      "youtuber" => ["hard", -> { p_("categories", "YouTuber") }],
      "political_party" => ["hard", -> { p_("categories", "Political party") }],
      "bank_name" => ["hard", -> { p_("categories", "Bank name") }],
      "social_media_platform" => ["medium", -> { p_("categories", "Social media platform") }],
      "newspaper" => ["hard", -> { p_("categories", "Newspaper") }],
      "toy" => ["easy", -> { p_("categories", "Toy") }],
      "medical_equipment" => ["hard", -> { p_("categories", "Medical equipment") }],
      "unit_of_measurement" => ["hard", -> { p_("categories", "Unit of measurement") }]
    }.transform_values(&:freeze).freeze
    IDS = CATEGORIES.keys.freeze
    BY_DIFFICULTY = IDS.group_by { |id| CATEGORIES.fetch(id).first }.transform_values(&:freeze).freeze
    DIFFICULTIES = %w[easy medium hard].freeze
    POOLS = DIFFICULTIES.each_with_index.to_h do |difficulty, index|
      included = DIFFICULTIES.take(index + 1)
      [difficulty, IDS.select { |id| included.include?(CATEGORIES.fetch(id).first) }.freeze]
    end.freeze

    def self.label(id)
      CATEGORIES[id]&.last&.call
    end
  end
end
