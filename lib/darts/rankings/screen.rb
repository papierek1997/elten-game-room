require_relative 'result'
require_relative '../../game_room_ui'

module GameRoomDartsRankings
  class Screen
    using GameRoomLocalization::Translations

    def initialize(program:, game:, service:)
      @program, @game, @service = program, game, service
      @closed = false
    end

    def run
      unless @service
        alert(text(_('Darts rankings are temporarily unavailable.')))
        return
      end
      difficulty_index = 0
      loop do
        difficulties = difficulty_choices
        difficulty_index = choose(difficulties.map(&:last), header: _('Darts difficulty'), index: difficulty_index)
        break if difficulty_index == nil
        category_index = 0
        loop do
          categories = category_choices
          category_index = choose(categories.map(&:last), header: _('Ranking type'), index: category_index)
          break if category_index == nil
          show_ranking(difficulties.fetch(difficulty_index).first, categories.fetch(category_index).first)
        end
      end
    end

    def close; @closed = true; end

    private

    def choose(options, header:, index: 0)
      list = ListBox.new(options.map { |label| text(label) }, header: text(header), index: index, quiet: true)
      open_button, back = Button.new(text(_('Open'))), Button.new(text(_('Back')))
      form = GameRoomUI::Form.new([list, open_button, back], program: @program, quiet: true)
      form.accept_button, form.cancel_button = open_button, back
      form.hide(open_button)
      form.hide(back)
      selected = nil
      open_button.on(:press) { selected = list.index; form.resume }
      back.on(:press) { form.resume }
      form.wait
      selected unless @closed
    end

    def show_ranking(difficulty, category)
      values = EltenAPI::Tasks.run(title: text(_('Loading Darts ranking')), cancellable: true, show_after: 2) do
        @service.store.ranking(difficulty: difficulty, category: category, limit: DISPLAY_LIMIT)
      end
      return unless values
      rows = values.map do |row|
        score = if category == 'triple'
          row.fetch('best_round_score').to_s
        else
          format('%.2f', row.fetch('total_score').fdiv(row.fetch('throw_count')))
        end
        time_ms = category == 'triple' ? row.fetch('best_round_time_ms') : row.fetch('total_time_ms').fdiv(row.fetch('throw_count'))
        [row.fetch('place').to_s, text(row.fetch('user')), score, format('%.3f s', time_ms / 1000.0), score_date(row.fetch('played_at'))]
      end
      table = TableBox.new([_('Place'), _('Player'), _('Score'), _('Time'), _('Date')].map { |label| text(label) }, rows,
        header: text(_('%{difficulty}: %{ranking}')) % {difficulty: text(difficulty_label(difficulty)), ranking: text(category_label(category))},
        empty_label: text(_('No results')), quiet: true)
      close_button = Button.new(text(_('Close')))
      form = GameRoomUI::Form.new([table, close_button], program: @program, quiet: true)
      form.accept_button = form.cancel_button = close_button
      form.hide(close_button)
      close_button.on(:press) { form.resume }
      form.wait
    rescue EltenAPI::Tasks::Cancelled
      nil
    rescue StandardError => error
      Log.warning("Darts ranking: #{error.class}: #{error.message}") if defined?(Log)
      alert(text(_('Could not connect to the Darts ranking.')))
    end

    def difficulty_choices
      [['easy', _('Easy')], ['normal', _('Normal')], ['hard', _('Hard')], ['progressive', _('Progressive game')]]
    end

    def category_choices
      [['triple', _('Best three-dart round')], ['average', _('Best average score')]]
    end

    def difficulty_label(value); difficulty_choices.to_h.fetch(value); end
    def category_label(value); category_choices.to_h.fetch(value); end
    def text(value); GameRoomContent.utf8(value.to_s); end
    def score_date(value); Time.at(value).strftime('%Y-%m-%d %H:%M'); rescue StandardError; ''; end
  end
end
