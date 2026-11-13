module GameRoomGames
  module BalutScoreGrid
    SLOT_COUNT = 4

    private

    def balut_totals_text(state, player)
      result = BalutScoring.current_result(state.fetch(:sheets).fetch(player))
      "Wynik gry: #{result.fetch(:points)}. Suma punkt\u00f3w: #{result.fetch(:raw)}."
    end

    def score_grid(state, player, writable: false)
      sheet = state.fetch(:sheets).fetch(player)
      categories = BalutScoring::CATEGORIES
      categories = categories.select { |category| sheet.fetch(category).size < SLOT_COUNT } if writable
      rows = categories.map do |category|
        values = sheet.fetch(category)
        remaining = if BalutScoring::TARGETS.key?(category)
          [BalutScoring::TARGETS.fetch(category) - values.sum, 0].max
        elsif category != :balut
          SLOT_COUNT - values.count(&:positive?)
        end
        label = category_label(category)
        if writable
          points = BalutScoring.score(category, state.fetch(:dice))
          label += ", do zapisu: #{points}"
        end
        label += ", suma #{values.sum}" if BalutScoring::TARGETS.key?(category)
        [label, *Array.new(SLOT_COUNT) { |index| values.fetch(index, "puste").to_s },
         "Suma: #{values.sum}", remaining.nil? ? "" : "Do premii: #{remaining}"]
      end
      result = BalutScoring.current_result(sheet)
      rows << [balut_totals_text(state, player), "Wynik gry: #{result.fetch(:points)}",
        "Suma punkt\u00f3w: #{result.fetch(:raw)}",
        "", "", "", ""]
      GameSurfaces::GridSpec.new(width: rows.first.size, height: rows.size,
        header: score_sheet_title(state, player), cells: rows, row_origin: :top, hide_coordinates: true, score_categories: writable ? categories.map(&:to_s) : nil)
    end
  end
end
