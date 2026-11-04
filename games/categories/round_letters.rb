module GameRoomGames
  using GameRoomLocalization::Translations
  class Categories
    # One round command owns all category letters, both locally and with a
    # verified server seed. Presentation and review use the same assignment.
    module RoundLetters
      private

      def draw_round_letters(options, categories, first)
        return [first] unless options['separate_letters']

        available = LANGUAGE_LETTERS.fetch(options['answer_language']) - [first]
        [first] + Array.new(categories.length - 1) { available.delete_at(yield(available.length)) }
      end

      def valid_round_letters?(parsed, options, used)
        letters = parsed.fetch(:letters)
        return false unless available_letters(options, used).include?(letters.first)
        return letters.length == 1 unless options['separate_letters']

        alphabet = LANGUAGE_LETTERS.fetch(options['answer_language'])
        letters.length == parsed.fetch(:categories).length && letters.uniq == letters && (letters - alphabet).empty?
      end

      def round_letter(state, category)
        state.fetch(:category_letters).fetch(category, state[:letter])
      end

      def round_category_label(state, category)
        return category_label(category) unless state[:options]['separate_letters']

        _("%{category} for letter %{letter}") % {
          category: category_label(category), letter: answer_letter_label(round_letter(state, category))
        }
      end
    end
    include RoundLetters
  end
end
