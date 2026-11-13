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
        remaining = if BalutScoring::TARGETS.key?(category)
          [BalutScoring::TARGETS.fetch(category) - values.sum, 0].max
        elsif category != :balut
          SLOT_COUNT - values.count(&:positive?)
        end
        label = category_label(category)
        if writable
          points = BalutScoring.score(category, state.fetch(:dice))
          label = _("%{category}: record %{points}") % {category: label, points: points}
        end
        [label, *Array.new(SLOT_COUNT) { |index| values.fetch(index, _("not filled")).to_s },
         _("Total: %{points}") % {points: values.sum}, remaining.nil? ? "" : _("Needed for the bonus: %{count}") % {count: remaining}]
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
  end
end
