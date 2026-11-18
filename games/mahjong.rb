# frozen_string_literal: true
require_relative 'mahjong_support/options'
require_relative 'mahjong_support/table_game'
require_relative 'mahjong_support/solitaire_game'
require_relative 'mahjong_support/solitaire_presentation'
require_relative 'mahjong_support/information_shortcuts'
require_relative 'mahjong_support/private_table'

module GameRoomGames
  using GameRoomLocalization::Translations

  # One catalog entry selects the variant; the shared executor owns all
  # adapters, including bot decisions.
  class Mahjong < Base
    GameRoomServerRandom.register('mahjong', %w[mahjong_deal mahjong],
      json_actions: {'mahjong' => {'a'=>'deal'}})

    include MahjongOptions
    include MahjongRules
    include MahjongInformationShortcuts

    module Identity
      def id; 'mahjong'; end
      def round_timing_start_actions; %w[mahjong_deal mahjong_begin]; end
      def round_timing_event_ids(replay, repository:)
        first, last = super
        round = replay.state[:round]
        if round.respond_to?(:finished?) && round.finished?
          end_event = replay.accepted_events.reverse_each.find { |event| event['action'] != 'mahjong_ready' }
          last = repository.event_id(end_event) if end_event
        end
        [first, last]
      end
      def name; _('Mahjong'); end
      def minimum_players; 1; end
      def maximum_players; 4; end
    end
    include Identity

    class Table < Base
      include Identity
      include MahjongTableGame
      include MahjongOptions
      prepend MahjongPrivateTable
    end
    class Solitaire < Base
      include Identity
      include MahjongSolitaireGame
      include MahjongSolitairePresentation
      include MahjongOptions
    end

    def supports_bots?; true; end
    def player_spatial_audio?; true; end
    def bot_strategy; @strategy ||= MahjongTableGame::Strategy.new; end

    def short_description
      _('Play Mahjong Solitaire, Hong Kong, Riichi or MCR.')
    end

    def event_sound_cues(event:, before_replay:, after_replay:, history:, viewer:, random_variant:)
      return nil unless before_replay&.state && after_replay&.state &&
        after_replay.accepted_events.include?(event) && !before_replay.accepted_events.include?(event)
      before, after = before_replay.state, after_replay.state
      return nil unless before[:session_id] == after[:session_id]

      if event['action'] == 'mahjong'
        return 'domino_refill' if !before[:board] && after[:board]
        if before[:board] && after[:board]
          return 'domino_move_tile' if after[:moves].length > before[:moves].length
          return 'reverse' if after[:moves].length < before[:moves].length
        end
      elsif event['action'] == 'mahjong_deal'
        return 'domino_refill' if after[:round] &&
          (!before[:round] || before[:hand_number] != after[:hand_number])
      elsif %w[mahjong_move mahjong_drawn private_show].include?(event['action'])
        first, last = before[:round], after[:round]
        return nil unless first && last
        if after[:private_cards] && before[:private_opening] && !after[:private_opening] && after[:phase] == :playing
          return 'domino_refill'
        end
        completed = last.finished? && (!after[:private_cards] || %i[finished between_hands].include?(after[:phase]))
        was_completed = first.finished? && (!before[:private_cards] || %i[finished between_hands].include?(before[:phase]))
        if completed && !was_completed
          return 'draw' if last.result.draw?
          # The shared presenter supplies the final match victory/loss cue.
          return 'win1' unless after_replay.finished?
          return nil
        end
        return nil if after[:private_cards] && last.finished? && !completed
        return nil if first.flow.generation == last.flow.generation
        return 'play2' if first.flow.melds != last.flow.melds
        return 'domino_move_tile' if last.flow.discards.length > first.flow.discards.length
        return 'domino_take_chip' if last.flow.wall.length < first.flow.wall.length ||
          last.flow.reserve.length < first.flow.reserve.length
      end
      nil
    end


    def replay(session, events, repository)
      adapter_for_options(options_from_json(session['options'])).replay(session, events, repository)
    end

    def incremental_replay(previous, session, events, repository)
      return nil unless previous && previous.state
      adapter_for_options(options_from_json(session['options'])).incremental_replay(previous, session, events, repository)
    end

    def action_for(selection, replay, actor, context: nil)
      adapter_for_replay(replay).action_for(selection, replay, actor, context: context)
    end

    def automatic_action(replay, actor, context: nil)
      adapter_for_replay(replay).automatic_action(replay, actor, context: context)
    end

    def automatic_action_due?(replay, actor, context: nil)
      !automatic_action(replay, actor, context: context).nil?
    end

    def automatic_actor(replay, viewer, table_owner:)
      if replay&.state&.dig(:private_cards)
        return replay.players.first if %i[awaiting_deal private_prepare].include?(replay.state[:phase]) && same_user?(viewer, table_owner)
        return viewer
      end
      super
    end

    def automatic_action_allowed?(replay, actor, table_owner:)
      return super unless replay&.state&.dig(:private_cards)
      same_user?(actor, table_owner) || replay.players.any? { |player| same_user?(player, actor) }
    end

    def legal_actions(replay, actor, context: nil)
      adapter_for_replay(replay).legal_actions(replay, actor, context: context)
    end

    def active_actors(replay)
      adapter_for_replay(replay).active_actors(replay)
    end

    def required_decision_key(replay, viewer)
      return nil if replay.nil?
      adapter_for_replay(replay).required_decision_key(replay, viewer)
    end

    def participant_scores(replay)
      adapter_for_replay(replay).participant_scores(replay)
    end

    def tournament_scores(replay, options:)
      participant_scores(replay)
    end

    def concurrent_session_input?(before, after, selection)
      return false unless before && after && before.state && after.state
      return false unless before.state[:profile] == after.state[:profile]
      adapter_for_replay(after).concurrent_session_input?(before, after, selection)
    end

    def table_bot_selection(replay, actor)
      return nil unless replay&.state&.key?(:profile)
      adapter_for_replay(replay).table_bot_selection(replay, actor)
    end

    def custom_game_shortcuts(replay, viewer)
      return [] unless replay && replay.state
      shortcuts = adapter_for_replay(replay).custom_game_shortcuts(replay, viewer).to_a.dup
      scores = mahjong_shortcut_scores(replay)
      text = replay.players.map do |player|
        _('%{player}: %{points}') % {player: participant_full_name(player), points: scores.fetch(player)}
      end.join('; ')
      shortcuts << announcement_shortcut(key: 's', label: _('read the scores'), message: text)
      if (round = replay.state[:round]) && (!replay.state[:private_cards] || %i[playing between_hands finished].include?(replay.state[:phase]))
        shortcuts.concat(mahjong_information_shortcuts(replay, viewer))
        message = "#{_('Wall')}. #{_('Tiles left: %{count}.') % {count: round.flow.wall.length}}"
        shortcuts << announcement_shortcut(key: 'm', label: _('read the number of tiles left in the wall'), message: message)
        seat = replay.players.index { |player| same_user?(player, viewer) }
        if !round.finished? && round.window&.pending&.include?(seat) &&
            %i[reactions kong_reactions].include?(round.flow.phase)
          tile = round.flow.phase == :kong_reactions ? round.added_kong_kind * 4 : round.flow.discards.last.last
          shortcuts << announcement_shortcut(key: 'd', label: _('read the tile awaiting your response'),
            message: GameRoomMahjong::TileLabels.label(tile))
        end
      elsif (board = replay.state[:board])
        message = _('%{pairs} pairs removed; %{tiles} tiles remaining.') % {pairs: replay.state[:moves].length, tiles: board.remaining.length}
        shortcuts << announcement_shortcut(key: 'm', label: _('read the number of tiles left in the layout'), message: message)
      end
      shortcuts
    end

    def surface_spec(replay, viewer_name = nil, viewer: viewer_name, context: nil)
      adapter = adapter_for_replay(replay)
      return adapter.surface_spec(replay, viewer) if adapter.is_a?(Solitaire)
      adapter.surface_spec(replay, viewer: viewer, context: context)
    end

    def game_view_spec(replay, viewer)
      surface = surface_spec(replay, viewer)
      target, index = nil, nil
      round = replay.state[:round]
      if surface.is_a?(GameSurfaces::CompositeSpec) && round && !round.finished?
        target = surface.parts.find { |part| part.id == 'claims' }
        seat = replay.players.index { |player| same_user?(player, viewer) }
        if !target && seat == round.flow.seat
          if %i[draw replacement].include?(round.flow.phase)
            target = surface.parts.find { |part| part.id == 'commands' }
          elsif round.flow.phase == :discard
            target = surface.parts.find { |part| part.id == 'hand' }
            if round.flow.last_draw
              [target, surface.parts.find { |part| part.id == 'all_tiles' }].compact.each do |part|
                found = part.surface.options.index { |option| option.value == round.flow.last_draw.to_s }
                next if found.nil?
                target, index = part, found
                break
              end
            end
          end
        end
      end
      key = target && [replay.state[:session_id], replay.state[:hand_number], round.flow.generation,
        target.id, viewer.to_s.downcase].freeze
      GameRoomLayout::ViewSpec.new(surface: surface, decision_focus_part: target&.id,
        decision_focus_key: key, decision_focus_index: index)
    end

    def build_presentation_game; build_session_game; end

    private

    def mahjong_shortcut_scores(replay)
      scores = participant_scores(replay)
      if (match = replay.state[:match])
        replay.players.each_with_index.to_h { |player, seat| [player, match.initial_points.fetch(seat) + scores.fetch(player)] }
      elsif replay.state[:profile]&.fetch('variant') == 'riichi'
        round = replay.state[:round]
        values = round&.riichi_outcome&.points || round&.riichi_state&.points || Array.new(replay.players.length, 30_000)
        replay.players.each_with_index.to_h { |player, seat| [player, values.fetch(seat)] }
      else
        scores
      end
    end

    def adapter_for_options(options)
      variant = normalize_options(options).fetch('variant')
      @adapters ||= {}
      adapter = @adapters[variant] ||= variant == 'solitaire' ? Solitaire.new : Table.new
      adapter.receiver_name_presentation = receiver_name_presentation
      adapter
    end

    def adapter_for_replay(replay)
      raise ArgumentError, 'Missing Mahjong replay' unless replay && replay.state
      variant = replay.state[:profile]&.fetch('variant') || 'solitaire'
      adapter_for_options('variant'=>variant)
    end
  end
end
