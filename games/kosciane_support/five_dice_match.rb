require_relative "five_dice_scoring"

module GameRoomGames
  class FiveDiceMatch
    attr_reader :current_player, :rolls, :categories

    def initialize(players, columns: 3, parity: false, fixed: false, double_first: false, strict_school: false)
      raise ArgumentError unless players.size >= 2 && players.uniq == players && columns.is_a?(Integer) && columns.positive?
      @players, @columns = players.dup.freeze, columns
      @categories = FiveDiceScoring.categories(parity: parity).freeze
      @fixed, @double_first, @strict_school = fixed, double_first, strict_school
      @sheets = players.to_h { |player| [player, @categories.to_h { |category| [category, []] }] }
      @reserves = players.to_h { |player| [player, Hash.new(0)] }
      @bonuses = players.to_h { |player| [player, {}] }
      @claimed, @blocked = {}, {}
      begin_turn(players.first)
    end

    def dice
      @dice.dup
    end

    def sheet(player)
      @sheets.fetch(player).transform_values(&:dup)
    end

    def reserve(player, category)
      @reserves.fetch(player)[category]
    end

    def bonuses(player)
      @bonuses.fetch(player).dup
    end

    def total(player)
      @sheets.fetch(player).values.sum { |row| row.grep(Integer).sum } + @bonuses.fetch(player).values.sum
    end

    def winners
      return unless @current_player.nil?
      best = @players.map { |player| total(player) }.max
      @players.select { |player| total(player) == best }
    end

    # Faces must come from the caller's verified random event in network play.
    def roll(player, indices, faces)
      return false unless @current_player && player == @current_player && @rolls < 3
      return false unless indices.is_a?(Array) && faces.is_a?(Array) && indices.size.between?(1, 5)
      return false unless indices.size == faces.size && indices.uniq == indices
      return false unless indices.all? { |i| i.is_a?(Integer) && i.between?(0, 4) }
      return false unless faces.all? { |face| face.is_a?(Integer) && face.between?(1, 6) }
      return false if @rolls.zero? && indices.size != 5
      indices.zip(faces).each { |index, face| @dice[index] = face }
      @rolls += 1
      true
    end

    def preview(category)
      return unless @current_player && @rolls.positive?
      row = @sheets.fetch(@current_player)[category]
      return unless row && row.size < @columns
      FiveDiceScoring.score(category, @dice, reserve: reserve(@current_player, category),
        fixed: @fixed, double_first: @double_first, rolls: @rolls)
    end

    def record(player, category, cross: false)
      return false unless @current_player && player == @current_player && @rolls.positive?
      rows = @sheets.fetch(player)
      row = rows[category]
      return false unless row && row.size < @columns
      if cross
        return false unless @rolls == 3
        row << :cross
        if FiveDiceScoring::SCHOOL.include?(category)
          @bonuses.fetch(player).clear
          @blocked[player] = true if @strict_school
        end
      else
        result = preview(category)
        return false unless result
        points, delta = result
        row << points
        @reserves.fetch(player)[category] += delta if FiveDiceScoring::SCHOOL.include?(category)
        if row.size == @columns && !row.include?(:cross)
          claim(player, [:row, category].freeze, points)
        end
        column = row.size - 1
        if rows.values.all? { |entries| entries[column].is_a?(Integer) }
          claim(player, [:column, column].freeze, 60)
        end
      end
      next_player = @players.rotate(@players.index(player) + 1).find do |candidate|
        @sheets.fetch(candidate).values.any? { |entries| entries.size < @columns }
      end
      begin_turn(next_player)
      true
    end

    private

    def begin_turn(player)
      @current_player = player
      @dice = Array.new(5)
      @rolls = 0
    end

    def claim(player, key, points)
      return unless FiveDiceScoring.bonuses_enabled?(@columns)
      return if @blocked[player] || @claimed[key]
      @claimed[key] = true
      @bonuses.fetch(player)[key] = points
    end
  end
end
