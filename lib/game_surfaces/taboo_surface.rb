require_relative "specifications"
# encoding: UTF-8
require_relative "../game_session_clock"
require_relative "../game_room_localization"

module GameSurfaces
  using GameRoomLocalization::Translations

  class TabooSurface
    include ActionEmitter
    attr_accessor :program
    def initialize(spec, state: {})
      @spec = spec
      @announcement = spec.lines.join(", ") unless spec.lines.empty?
      @list = RefreshAwareListBox.new(labels, header: header, index: state.fetch("index",0), quiet: true)
      @list.on(:select) { select }
      @approve = Button.new(_("Approve this turn"))
      @approve.on(:press) { send_action("approve") }
      @restart = Button.new(_("Repeat this turn because of a technical problem"))
      @restart.on(:press) { restart }
    end
    def fields
      controls = [@list]
      controls << @approve if @spec.master && @spec.phase == :review
      controls << @restart if @spec.master && [:preparing,:describing,:review].include?(@spec.phase)
      controls
    end
    def state; { "index" => @list.index.to_i }; end
    def reusable_for?(spec); spec.is_a?(TabooSpec); end
    def update_spec(spec)
      changed = @spec.token != spec.token
      card_changed = @spec.lines != spec.lines
      revealed = (changed || card_changed) && !spec.lines.empty?
      @spec = spec
      @list.options = labels
      @list.header = header if @list.respond_to?(:header=)
      @list.index = 0 if changed || revealed
      @announcement = nil if changed || card_changed
      @announcement = spec.lines.join(", ") if revealed
      self
    end
    def take_cursor_announcement(index = nil)
      message, @announcement = @announcement, nil
      index == 0 ? message : nil
    end
    def suppress_next_focus!(index = 0); @list.suppress_next_focus! if index == 0; end
    def handle_command(command, payload = {})
      case command
      when "taboo_time"
        now = GameRoomSessionClock.for_state(frozen_at: payload["frozen"], clock_offset: payload["offset"], clock_epoch_offset: payload["epoch"]).to_i
        seconds = [payload["deadline"].to_i-now,0].max
        speak(payload["deadline"].to_i > 0 ? (_("%{seconds} seconds remaining.") % { seconds: seconds }) : _("The turn clock is not running."))
        true
      when "taboo_skipped", "taboo_buzzed"
        valid = command == "taboo_skipped" ? @spec.action == "correct" : @spec.opponent
        return true unless valid && @spec.phase == :describing
        Action.new(kind: "taboo", name: command.delete_prefix("taboo_"), payload: { "token" => @spec.token })
      else false
      end
    end
    private
    def labels
      return @spec.lines unless @spec.lines.empty?
      return @spec.review.map { |e| "#{e[:word]}, #{e[:forbidden].join(', ')}; #{e[:label]}" } if @spec.phase == :review && !@spec.review.empty?
      [@spec.status]
    end
    def header; @spec.lines.empty? ? _("Taboo") : _("Target and forbidden words"); end
    def send_action(name, payload = {})
      emit_action("taboo",name,payload.merge("token" => @spec.token))
    end
    def select
      if @spec.action
        send_action(@spec.action)
      elsif @spec.master && @spec.phase == :review
        token, index = @spec.token, @list.index.to_i
        choice = choose(_("Correct this card's result"), @spec.results.map(&:last))
        send_action("correct_result", "index" => index, "result" => @spec.results[choice][0]) if choice && token == @spec.token
      end
    end
    def restart
      token = @spec.token
      choice = choose(_("Cancel this turn's points and repeat it?"), [_("No"),_("Yes")])
      send_action("restart_turn") if choice == 1 && token == @spec.token
    end
    def choose(prompt, choices)
      GameRoomUI.choose_index(prompt, choices, program: @program)
    end
  end
end
