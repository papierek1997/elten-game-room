require_relative '../game_room_localization'

module GameRoomBilliards
  module Controls
    using GameRoomLocalization::Translations
    module_function

    def shortcuts(competition: false)
      bindings = [
        ['k', [], 'angle', _('Read cue direction')],
        ['f', [], 'power', _('Read shot power')],
        ['g', [], 'line', _('Read the first contact on the shot line')],
        ['h', [], 'near', _('List balls near the shot line')],
        ['i', [], 'selected', _('Describe the selected ball')],
        ['o', [], 'overview', _('List all balls and their positions')],
        ['l', [], 'next', _('Select the next object ball')],
        ['l', [:shift], 'previous', _('Select the previous object ball')],
        ['j', [], 'pocket', _('Choose a target pocket')],
        ['a', [], 'aim', _('Aim at the centre of the selected ball')],
        ['a', [:shift], 'pocket_aim', _('Aim the selected ball towards the chosen pocket')],
        ['e', [], 'parameters', _('Enter exact angle, power and spin')],
        ['w', [], 'top', _('Increase follow spin')],
        ['b', [], 'behind', _('Describe objects behind the aimed ball')],
        ['b', [:shift], 'back', _('Increase draw spin')],
        ['n', [], 'left_spin', _('Increase left spin')],
        ['d', [], 'right_spin', _('Increase right spin')],
        ['r', [], 'neutral', _('Remove spin')],
        ['c', [], 'clock', _('Switch between degrees and clock directions')],
        ['y', [], 'predict', _('Predict this shot without moving the balls')],
        ['u', [], 'contacts', _('Read contacts from the last shot')],
        ['v', [], 'rebound', _('Predict the cushion rebound and next ball contact')],
        ['comma', [], 'object_prediction', _('Predict the aimed ball using the current shot parameters')],
        ['m', [], 'place', _('Place a ball for practice')],
        ['z', [], 'undo', _('Undo the last shot in solo practice')],
        ['r', [:shift], 'reset', _('Restore the original practice layout')],
        ['p', [:shift], 'pass', _('Pass the cue to the next player')],
        ['q', [], 'finish', _('Finish practice')]
      ]
      return bindings unless competition
      bindings.reject! { |_, _, command, _| %w[place undo reset pass finish].include?(command) }
      bindings + [['m', [], 'place', _('Place the cue ball in hand')],
        ['p', [], 'match_options', _('Declare a shot or choose the decision after a foul')],
        ['p', [:shift], 'match_status', _('Read the discipline, legal balls and match status')],
        ['q', [], 'concede', _('Concede this rack or frame')]]
    end

    # These definitions drive both native arrow input and its F1 help.
    def adjustments
      [[:left, [], 'angle', 100, _('Left: turn anticlockwise by 1 degree.')],
       [:right, [], 'angle', -100, _('Right: turn clockwise by 1 degree.')],
       [:left, [:shift], 'angle', 10, _('Shift+Left: turn anticlockwise by 0.1 degree.')],
       [:right, [:shift], 'angle', -10, _('Shift+Right: turn clockwise by 0.1 degree.')],
       [:left, [:control], 'angle', 1, _('Ctrl+Left: turn anticlockwise by 0.01 degree.')],
       [:right, [:control], 'angle', -1, _('Ctrl+Right: turn clockwise by 0.01 degree.')],
       [:up, [], 'power', 10, _('Up: increase power by 1 percent.')],
       [:down, [], 'power', -10, _('Down: decrease power by 1 percent.')],
       [:up, [:shift], 'power', 1, _('Shift+Up: increase power by 0.1 percent.')],
       [:down, [:shift], 'power', -1, _('Shift+Down: decrease power by 0.1 percent.')]]
    end

    def decimal(text, scale:, range:)
      value = text.to_s.strip.tr(',', '.')
      return nil unless value.match?(/\A[+-]?\d{1,6}(?:\.\d{1,4})?\z/)
      number = Float(value)
      scaled = number * scale
      return nil unless number.finite? && range.cover?(number) && (scaled - scaled.round).abs < 1e-7
      scaled.round
    end
  end
end
