require_relative 'background_help_native'
require_relative 'native_tasks'
require_relative 'assertions'
require_relative '../../lib/game_surfaces'
require_relative '../../lib/game_layout'
require_relative '../../lib/game_shortcut_bindings'
require_relative '../../games/cash_auction'

unless defined?(Session)
  module Session
    def self.name; 'Alice'; end
  end
end

module EltenWindow
  class << self
    attr_accessor :cash_auction_characters
    def take_character(_multi)
      value, self.cash_auction_characters = cash_auction_characters.to_s, ''
      value
    end
  end
end

module CashAuctionNative
  QUESTION = {question_id: 'native-example', category: 0,
    prompt: 'Which answer should be selected?', choices: %w[First Second Third Fourth],
    correct_index: 2, used: ['native-example']}.freeze

  class Driver
    def initialize
      @now = 0.0
      $native_tutorial_driver = self
      EltenAPI::KeyboardState.reset
    end

    def raw(keys)
      value = "\0" * 256
      keys.each { |key| value.setbyte(key, 0x80) }
      value
    end

    def tap(key, modifiers: [])
      modifiers.map { |modifier| [modifier, true] } +
        [[key, true, raw([key] + modifiers)], [key, false]] +
        modifiers.reverse.map { |modifier| [modifier, false] }
    end

    def snapshot(events = [], held = [])
      @now += 0.016
      EltenAPI::KeyboardState.update(raw_state: raw(held), events: events, now: @now,
        pressed_implies_held: false, synthesize_repeats: false)
      $input_frame_serial = $input_frame_serial.to_i + 1
      $keyboard_state_frame_serial = $input_frame_serial
      $keyboard_state_frame_thread = Thread.current
      $activecontrols = []
    end

    def tick(_form)
      snapshot
    end

    def frame(form, events, held: [], characters: '')
      $native_tutorial_driver = self
      EltenWindow.cash_auction_characters = characters
      snapshot(events, held)
      form.update
    end
  end

  # Real shared native controls, with a capture-only action listener. There is
  # no transport, repository or executor, so control input cannot append moves.
  class Fixture
    attr_reader :game, :state, :replay, :layout, :actions, :shortcut_actions

    def initialize(phase: :auction, viewer: 'Alice')
      @driver = Driver.new
      @viewer = viewer
      @game = GameRoomGames::CashAuction.new
      @state = GameRoomCashAuction::Rules.initial(%w[Alice Bob Carol], game.default_options).merge(game_id: 'native-cash-test')
      raise 'Native fixture did not enter auction' unless GameRoomCashAuction::Rules.draw!(state, category: 0, chest: false, now: 100)
      if phase == :answering
        rules = GameRoomCashAuction::Rules
        raise 'Native fixture did not accept opening bid' unless rules.bid!(state, 0, 100, now: 101, revision: 1)
        raise 'Native fixture did not award question' unless rules.award!(state, now: state[:auction_deadline])
        raise 'Native fixture did not open question' unless rules.start_question!(state, QUESTION)
      elsif phase == :opening_chests
        state[:phase], state[:chests][0] = :opening_chests, 2
      end
      @events, @actions, @shortcut_actions = [], [], []
      build_replay
      @layout = GameRoomLayout::Screen.new(view_spec: game.game_view_spec(replay, @viewer),
        user_items: replay.players, users_header: 'Players', phase: :active)
      form.game_room_background_help_enabled = true
      bind
      layout.focus_game
      form.focus
    end

    def form; layout.form; end
    def surface; layout.surface; end
    def input; surface.fields.first; end

    def press(key, modifiers: [])
      held = modifiers + [key]
      @driver.frame(form, modifiers.map { |code| [code, true] } +
        [[key, true, @driver.raw(held)]], held: held)
      @driver.frame(form, [[key, false]] + modifiers.reverse.map { |code| [code, false] })
    end

    def type(text)
      layout.focus_game
      press(0x41, modifiers: [0x11])
      events = text.chars.flat_map { |character| @driver.tap(character.upcase.ord) }
      @driver.frame(form, events, characters: text)
    end

    def refresh
      build_replay
      layout.update(view_spec: game.game_view_spec(replay, @viewer), history_items: [],
        user_items: replay.players, users_header: 'Players', phase: :active)
      bind
    end

    def close
      layout.begin_bindings
      form.resume
      $activecontrols = []
    end

    private

    def build_replay
      @replay = GameRoomGames::Replay.new(players: state[:players], state: state,
        accepted_events: @events, history: [], winner: nil, draw: false)
    end

    def bind
      layout.begin_bindings
      surface.on_action { |action| actions << action.to_h }
      GameRoomShortcutBindings.bind(form, layout.game_help_fields,
        GameRoomShortcutBindings.normalize(game.game_shortcuts(replay, @viewer)),
        consume: ->(_key) { EltenAPI::KeyboardState.clear_current_frame }) do |shortcut|
        shortcut_actions << shortcut
      end
    end
  end
end
