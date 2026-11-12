require_relative "specifications"
require_relative "../game_room_localization"

module GameSurfaces
  using GameRoomLocalization::Translations



  class QuestionSurface
    include ActionEmitter

    # Only plain vertical arrows cross this two-control boundary. Native text
    # navigation, selection and screen-reader modifier keys stay with ELTEN.
    module PromptNavigation
      def question_navigation(form, target, key)
        @question_navigation = [form, target, key]
      end

      def update
        if @question_navigation
          form, target, key = @question_navigation
          if key_pressed?(key) && GameRoomUI.modifiers_when_pressed(self, key, include_insert: true).empty? &&
              (key == :key_down || index.to_i == 0) &&
              form.fields[form.index.to_i].equal?(self) && (target_index = form.fields.index(target))
            trigger(:blur)
            blur
            form.index = target_index
            form.focus
            form.trigger(:move, target_index)
            return
          end
        end
        super
      end
    end

    class PromptText < RefreshAwareEditBox
      include PromptNavigation
    end

    class AnswerList < RefreshAwareListBox
      include PromptNavigation
    end

    MODES = [:text, :single_choice, :multiple_choice, :information].freeze

    def initialize(spec, state: {})
      @spec = spec
      raise ArgumentError, "a question requires an id" if @spec.id.to_s.empty?
      @mode = (@spec.mode || :text).to_sym
      raise ArgumentError, "unsupported question mode" if !MODES.include?(@mode)

      @options = @spec.options.to_a
      validate_options! if [:single_choice, :multiple_choice].include?(@mode)
      if prompt_as_text?
        state = {} if state_value(state, "question_id", @spec.id).to_s != @spec.id.to_s
        @prompt = PromptText.new(_("Question"), type: EditBox::Flags::ReadOnly,
          text: @spec.prompt.to_s, quiet: true)
        @prompt.restore_selection(index: state_value(state, "prompt_index", 0), check: state_value(state, "prompt_check", 0))
      end
      @answer = build_answer_control(state)
      bind_immediate_choice
      @submit = build_submit_button
      @answer.on_submit { submit_answer } if @mode == :text && !@spec.read_only && @spec.show_submit_button == false
      @extra_buttons = if @spec.read_only || @mode != :text
        []
      else
        @spec.extra_commands.to_a.map do |command|
          button = Button.new(command.label)
          button.on(:press) { submit_answer(command.id) }
          button
        end
      end
    end

    def fields
      [@prompt, @answer, @submit].compact + @extra_buttons
    end

    def attach_form(form)
      return unless @prompt

      @prompt.question_navigation(form, @answer, :key_down)
      @answer.question_navigation(form, @prompt, :key_up)
    end

    def state
      case @mode
      when :text
        { "text" => @answer.text.to_s, "index" => @answer.index,
          "check" => @answer.check, "question_id" => @spec.id }
      when :single_choice
        result = { "index" => @answer.index.to_i }
        result.merge!("question_id" => @spec.id, "prompt_index" => @prompt.index,
          "prompt_check" => @prompt.check) if @prompt
        result
      when :multiple_choice
        { "selected" => @answer.multiselections }
      else
        {}
      end
    end

    def submission_action
      return nil if @spec.read_only == true || @mode == :information

      answer = answer_value
      return nil if answer == nil

      GameSurfaces::Action.new(
        kind: "question",
        name: "submit",
        payload: answer_payload(answer)
      )
    end

    def action_accepted(selection)
      return false unless @mode == :text && @spec.clear_on_submit == true && !@spec.read_only
      return false unless selection['kind'] == 'question' && selection['question_id'] == @spec.id.to_s &&
        selection['_text_input'] == text_input_identity && selection['answer'] == @answer.text.to_s
      return false unless selection['action'] == 'submit' ||
        @spec.extra_commands.to_a.any? { |command| command.id.to_s == selection['action'] }

      clear_text_answer
      true
    end

    # Only game-declared validation errors consume the submitted draft. The
    # same control/generation check protects text typed during a pending write.
    def action_rejected(selection, status)
      return false unless @spec.clear_on_rejection.to_a.include?(status.to_s)

      action_accepted(selection)
    end

    private

    def bind_immediate_choice
      return if @mode != :single_choice || @spec.submit_on_select != true

      @answer.on(:select) do
        action = submission_action
        emit_action(action.kind, action.name, action.payload) if action
      end
    end

    def build_answer_control(state)
      case @mode
      when :text
        remembered_id = state_value(state, "question_id", @spec.id)
        state = {} if remembered_id != @spec.id
        text = state_value(state, "text", @spec.value.to_s)
        flags = @spec.read_only == true ? EditBox::Flags::ReadOnly : 0
        control = RefreshAwareEditBox.new(
          @spec.prompt.to_s,
          type: flags,
          text: text,
          quiet: true,
          max_length: maximum_length
        )
        control.restore_selection(
          index: state_value(state, "index", text.length),
          check: state_value(state, "check", text.length)
        )
        control
      when :information
        RefreshAwareEditBox.new(
          @spec.prompt.to_s,
          type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine,
          text: @spec.value.to_s,
          quiet: true
        )
      when :single_choice, :multiple_choice
        flags = @mode == :multiple_choice ? ListBox::Flags::MultiSelection : 0
        labels = @options.map { |option| option.label.to_s }
        header = prompt_as_text? ? _("Answers") : @spec.prompt.to_s
        if prompt_in_choices?
          labels.unshift(@spec.prompt.to_s)
          header = ""
        end
        list_class = prompt_as_text? ? AnswerList : RefreshAwareListBox
        list = list_class.new(
          labels,
          header: header,
          index: selected_index(state),
          flags: flags,
          quiet: true
        )
        if @mode == :multiple_choice
          selected = state_value(state, "selected", selected_option_indices)
          list.select_multiselection_indices(selected.to_a.map(&:to_i))
        end
        list
      end
    end

    def build_submit_button
      return nil if @spec.read_only == true || @mode == :information || @spec.submit_on_select == true
      return nil if @spec.show_submit_button == false

      button = Button.new((@spec.submit_label || _("Submit answer")).to_s)
      button.on(:press) { submit_answer }
      button
    end

    def submit_answer(action = "submit")
      value = answer_value
      emit_action("question", action, answer_payload(value))
    end

    def answer_payload(value)
      payload = {"question_id" => @spec.id.to_s, "answer" => value,
        "required" => @spec.required == true}
      # Local UI receipt only: a copied action may wait behind a chat write.
      # The game still writes its own EventCommands, never this control token.
      payload['_text_input'] = text_input_identity if @mode == :text && @spec.clear_on_submit == true
      payload
    end

    def text_input_identity
      [@answer.object_id, @answer.game_room_edit_generation]
    end

    def clear_text_answer
      if @answer.respond_to?(:set_text)
        @answer.set_text("")
      else
        @answer.text = ""
      end
      @answer.restore_selection(index: 0, check: 0)
    end

    def answer_value
      case @mode
      when :text
        @answer.text.to_s
      when :single_choice
        index = @answer.index.to_i
        index -= 1 if prompt_in_choices?
        return nil if index < 0

        option_value(@options[index])
      when :multiple_choice
        @answer.multiselections.map { |index| option_value(@options[index]) }
      end
    end

    def option_value(option)
      return nil if option == nil
      return option.value if option.value != nil

      option.id.to_s
    end

    def selected_index(state)
      stored = state_value(state, "index", nil)
      return stored.to_i if stored != nil

      values = Array(@spec.value).map(&:to_s)
      index = @options.index do |option|
        values.include?(option_value(option).to_s) || values.include?(option.id.to_s)
      end
      return 0 if index == nil

      prompt_in_choices? ? index + 1 : index
    end

    def selected_option_indices
      values = Array(@spec.value).map(&:to_s)
      @options.each_index.select do |index|
        values.include?(option_value(@options[index]).to_s) || values.include?(@options[index].id.to_s)
      end
    end

    def maximum_length
      configured = @spec.max_length.to_i
      configured > 0 ? configured : 64
    end

    def prompt_in_choices?
      @mode == :single_choice && @spec.prompt_in_choices == true && !prompt_as_text?
    end

    def prompt_as_text?
      @mode == :single_choice && @spec.prompt_as_text == true
    end

    def validate_options!
      raise ArgumentError, "a choice question requires options" if @options.empty?
      ids = @options.map { |option| option.id.to_s }
      raise ArgumentError, "question option ids must not be empty" if ids.any?(&:empty?)
      raise ArgumentError, "question option ids must be unique" if ids.uniq.length != ids.length
    end


  end
end
