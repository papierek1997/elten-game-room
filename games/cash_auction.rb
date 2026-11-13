# encoding: UTF-8
require_relative 'base'
require_relative '../content/languages'
require_relative '../content/quiz_general_en'
require_relative '../content/quiz_general_ru'
require_relative '../content/quiz_pl_wikidata'
require_relative '../content/quiz_witcher_pl'
require_relative '../content/quiz_harry_potter_pl'
require_relative '../lib/game_bots'
require_relative '../lib/game_replay_cache'
require_relative '../lib/game_session_clock'
require_relative '../lib/cash_auction/rules'
require_relative '../lib/cash_auction/question_bank'

GameRoomServerRandom.register('cash_auction', %w[wheel question chest])

module GameRoomGames
  using GameRoomLocalization::Translations

  class CashAuction < Base
    include PublicHistoryAnnouncements
    R = GameRoomCashAuction::Rules
    CHEST_REWARDS = R::CHEST_REWARDS

    def id; 'cash_auction'; end
    def name; _('Cash Auction'); end
    def short_description; _('Bid against everyone at once, answer quiz questions and open black chests to compete for the most points.'); end
    def minimum_players; 2; end
    def maximum_players; 8; end
    def rule_sections; generated_rule_sections; end
    def content_pack_kind; 'quiz'; end
    def content_pack_game_id; 'quiz'; end
    def notification_option_keys(_options); %w[content_language_id content_set_id]; end
    def supports_bots?; true; end
    def player_spatial_audio?; true; end
    def table_sound_event?(event); !%w[bid pass].include?(event['action']); end
    def perfect_information?; false; end
    def actions_during_bot_turn?; true; end
    def session_history_capacity(_options); 32_768; end
    def shortcut_features; [:scores]; end
    def bot_strategy; @bot_strategy ||= GameRoomBots::HeuristicStrategy.new; end

    def option_definitions
      [OptionDefinition.new(key: 'starting_points', label: _('Starting points (10 to 1000000)'), kind: :integer, default: 1000),
       OptionDefinition.new(key: 'ante', label: _('Ante paid by each player'), kind: :integer, default: 10),
       OptionDefinition.new(key: 'pass_penalty', label: _('Penalty for every third pass'), kind: :integer, default: 200),
       OptionDefinition.new(key: 'rounds', label: _('Number of auction rounds (8 to 32)'), kind: :integer, default: 8),
       OptionDefinition.new(key: 'count_interval', label: _('Seconds between auction calls (1 to 5)'), kind: :integer, default: 2),
       OptionDefinition.new(key: 'black_chest_chance', label: _('Black chest probability in percent (5 to 10)'), kind: :integer, default: 5)]
    end

    def options_error(options, player_count: nil)
      values = normalize_options(options)
      return _('Choose from 2 to 8 players.') if player_count && !player_count.between?(2, 8)
      return _('Starting points must be from 10 to 1000000.') unless values['starting_points'].between?(10, 1_000_000)
      return _('The ante must be positive and no greater than the starting points.') unless values['ante'].between?(1, values['starting_points'])
      return _('The pass penalty must be from 0 to 1000000.') unless values['pass_penalty'].between?(0, 1_000_000)
      return _('Choose from 8 to 32 auction rounds.') unless values['rounds'].between?(8, 32)
      return _('Choose from 1 to 5 seconds between auction calls.') unless values['count_interval'].between?(1, 5)
      return _('The black chest probability must be from 5 to 10 percent.') unless values['black_chest_chance'].between?(5, 10)
      content_options_error(values)
    end

    def participant_scores(replay)
      replay.players.each_with_index.to_h { |player, seat| [player, replay.state[:cash][seat]] }
    end

    def eliminated_from_game?(replay, viewer)
      seat = player_index(replay.players, viewer)
      seat != nil && replay.state[:eliminated][seat]
    end

    def active_actors(replay)
      state = replay.state
      return [] if replay.finished?
      seats = case state[:phase]
      when :auction then R.active_seats(state).reject { |seat| state[:passed][seat] || seat == state[:leader] }
      when :answering then [state[:leader]]
      when :opening_chests then state[:chests].each_index.select { |seat| state[:chests][seat] > 0 }
      else []
      end
      seats.compact.map { |seat| replay.players[seat] }
    end

    def required_decision_key(replay, viewer)
      return nil if replay.nil? || replay.finished?
      if replay.state[:phase] == :auction
        seat = player_index(replay.players, viewer)
        return [:auction, replay.state[:game_id], replay.state[:round]] if seat && !replay.state[:eliminated][seat] && !replay.state[:passed][seat]
        return nil
      end
      return nil unless active_actors(replay).any? { |actor| same_user?(actor, viewer) }
      [replay.state[:phase], replay.state[:game_id], replay.state[:round]]
    end

    def concurrent_session_input?(before, after, selection)
      return false unless before.state[:phase] == :auction && after.state[:phase] == :auction
      before.state[:game_id] == after.state[:game_id] && before.state[:round] == after.state[:round] &&
        selection['question_id'].to_s == auction_id(after.state)
    end
  end
end

require_relative 'cash_auction/presentation'
require_relative 'cash_auction/actions'
require_relative 'cash_auction/replay'
require_relative 'generated/rulebooks/cash_auction'
