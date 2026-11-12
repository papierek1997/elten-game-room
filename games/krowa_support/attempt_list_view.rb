# encoding: UTF-8
require_relative '../../lib/game_room_localization'

module GameRoomGames
  using GameRoomLocalization::Translations

  class KrowaAttemptListView
    attr_reader :field

    def initialize(game, selection:, &load)
      @game, @selection, @load = game, selection, load
      @field = ListBox.new([], header: _("Attempt list"), quiet: true,
        empty_label: _("No recorded attempts"))
      @field.on(:before_focus) { refresh }
    end

    def refresh
      identity = @selection.call
      return if @loaded && identity == @identity
      value = @load.call(identity)
      # The cached identity belongs to the displayed contents. A failed or
      # hidden selection replaces those contents, so it must invalidate an
      # earlier successful selection as well as allow retrying the current one.
      @loaded = ![:failed, :hidden].include?(value)
      @identity = identity
      options = if value.is_a?(Hash)
        value.fetch(:words).map do |trial|
          _("%{word}. %{matches}") % {word: trial, matches: @game.attempt_matches(trial, value.fetch(:word))}
        end
      else
        []
      end
      @field.options = options
      @field.empty_label = case value
      when :hidden then _("Today's Daily Krowa attempts are hidden until the next day.")
      when :failed then _("Could not load the attempt list. Return to the result and try again.")
      else _("No recorded attempts")
      end
      @field.index = 0
    end
  end
end
