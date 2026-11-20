# frozen_string_literal: true

# Presentation only. Games decide whether a result is a zero, a bonus or a
# school failure; this helper never reads scores, advances play or starts audio.
module GameRoomFiveDiceSounds
  EFFECTS = {bonus: 'bonus', complete: 'win2', failure: 'lose3', doubled: 'doubled'}.freeze
  STANDALONE_EFFECTS = {bonus: 'five_dice_bonus', doubled: 'five_dice_doubled'}.freeze

  module_function

  def roll(dice)
    complete = dice.is_a?(Array) && dice.length == 5 && dice.all? { |face| face.is_a?(Integer) && face.between?(1, 6) }
    # Five of a kind shares War's drum roll; scoring bonuses keep their own cue.
    complete && dice.uniq.one? ? %w[roll war_open] : 'roll'
  end

  # A column uses the existing combined recording, preserving its timing.
  # `recording` can reuse a cue already attached to accepted history.
  # Zero has a short cue, not General's distinct school-failure recording.
  def score(column: nil, effect: nil, zero: false, recording: nil)
    suffix = EFFECTS.fetch(effect) if effect
    if !column.nil? && !(column.is_a?(Integer) && column.between?(1, 6))
      raise ArgumentError, 'Expected a score column from 1 to 6'
    end
    cue = recording || if column
      ["kosciane_column_#{column}", suffix].compact.join('_')
    else
      suffix ? ['five_dice_record', STANDALONE_EFFECTS.fetch(effect, suffix)] : 'five_dice_record'
    end
    cues = Array(cue)
    if zero && !effect && cues.none? { |name| name.to_s.end_with?('lose3') }
      cues += ['five_dice_zero']
    end
    cues.one? ? cues.first : cues
  end
end
