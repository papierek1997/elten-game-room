module GameRoomGames
  using GameRoomLocalization::Translations
  module BalutScoreGrid
    SLOT_COUNT = 4

    private

    def balut_totals_text(state, player)
      result = BalutScoring.current_result(state.fetch(:sheets).fetch(player))
      _("Game points: %{points}. Sum of recorded scores: %{total}.") % {points: result.fetch(:points), total: result.fetch(:raw)}
    end

    def score_grid(state, player, writable: false)
      sheet = state.fetch(:sheets).fetch(player)
      categories = BalutScoring::CATEGORIES
      categories = categories.select { |category| sheet.fetch(category).size < SLOT_COUNT } if writable
      rows = categories.map do |category|
        values = sheet.fetch(category)
        label = category_label(category)
        if writable
          points = BalutScoring.score(category, state.fetch(:dice))
          label = _("%{category}: enter %{points}") % {category: label, points: points}
          label = score_entry_column_label(label, column: values.size + 1, columns: SLOT_COUNT)
        end
        [label, *Array.new(SLOT_COUNT) { |index| values.fetch(index, _("not filled")).to_s },
         _("Sum of entries: %{total}") % {total: values.sum}, balut_row_status(category, values)]
      end
      result = BalutScoring.current_result(sheet)
      rows << [balut_totals_text(state, player), _("Game points: %{points}") % {points: result.fetch(:points)},
        _("Total: %{points}") % {points: result.fetch(:raw)},
        "", "", "", ""]
      GameSurfaces::GridSpec.new(width: rows.first.size, height: rows.size,
        header: score_sheet_title(state, player), cells: rows, row_origin: :top, hide_coordinates: true,
        row_actions: writable ? categories.map { |category| GameSurfaces::Action.new(kind: 'dice', name: 'score', payload: {'category' => category.to_s}) } : [],
        shortcuts: [announcement_shortcut(key: 'space', label: _("read the dice"), message: dice_text(state))])
    end

    def balut_row_status(category, values)
      points = BalutScoring.row_points(category, values)
      if points.positive? || category == :balut
        _("Game points for this category: %{points}") % {points: points}
      elsif !BalutScoring.row_points_possible?(category, values)
        _("No game points can be earned in this category.")
      elsif BalutScoring::TARGETS.key?(category)
        _("Score still needed: %{count}") % {count: BalutScoring::TARGETS.fetch(category) - values.sum}
      else
        _("Successful entries still needed: %{count}") % {count: SLOT_COUNT - values.length}
      end
    end
  end
end
