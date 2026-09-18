module GameSurfaces
  QuestionOption = Struct.new(:id, :label, :value, keyword_init: true)
  QuestionSpec = Struct.new(
    :id,
    :prompt,
    :mode,
    :options,
    :value,
    :submit_label,
    :show_submit_button,
    :required,
    :read_only,
    :max_length,
    :submit_on_select,
    :prompt_in_choices,
    :clear_on_submit,
    :extra_commands,
    keyword_init: true
  )

  class QuestionSurface
    include ActionEmitter

    MODES = [:text, :single_choice, :multiple_choice, :information].freeze

    def initialize(spec, state: {})
      @spec = spec
      raise ArgumentError, "a question requires an id" if @spec.id.to_s.empty?
      @mode = (@spec.mode || :text).to_sym
      raise ArgumentError, "unsupported question mode" if !MODES.include?(@mode)

      @options = @spec.options.to_a
      validate_options! if [:single_choice, :multiple_choice].include?(@mode)
      @answer = build_answer_control(state)
      bind_immediate_choice
      @submit = build_submit_button
      @answer.on_submit { submit_answer } if @mode == :text && !@spec.read_only
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
      [@answer, @submit].compact + @extra_buttons
    end

    def state
      case @mode
      when :text
        { "text" => @answer.text.to_s, "index" => @answer.index,
          "check" => @answer.check, "question_id" => @spec.id }
      when :single_choice
        { "index" => @answer.index.to_i }
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
        payload: {
          "question_id" => @spec.id.to_s,
          "answer" => answer,
          "required" => @spec.required == true
        }
      ).tap { clear_text_answer if @mode == :text && @spec.clear_on_submit == true }
    end

    private

    def bind_immediate_choice
      return if @mode != :single_choice || @spec.submit_on_select != true

      @answer.on(:select) do
        answer = answer_value
        next if answer == nil

        emit_action(
          "question",
          "submit",
          {
            "question_id" => @spec.id.to_s,
            "answer" => answer,
            "required" => @spec.required == true
          }
        )
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
        header = @spec.prompt.to_s
        if prompt_in_choices?
          labels.unshift(@spec.prompt.to_s)
          header = ""
        end
        list = RefreshAwareListBox.new(
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
      clear_text_answer if @mode == :text && @spec.clear_on_submit == true
      emit_action(
        "question",
        action,
        {
          "question_id" => @spec.id.to_s,
          "answer" => value,
          "required" => @spec.required == true
        }
      )
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
      @mode == :single_choice && @spec.respond_to?(:prompt_in_choices) && @spec.prompt_in_choices == true
    end

    def validate_options!
      raise ArgumentError, "a choice question requires options" if @options.empty?
      ids = @options.map { |option| option.id.to_s }
      raise ArgumentError, "question option ids must not be empty" if ids.any?(&:empty?)
      raise ArgumentError, "question option ids must be unique" if ids.uniq.length != ids.length
    end

    def state_value(state, key, default)
      return default if !state.respond_to?(:key?)
      return state[key] if state.key?(key)
      return state[key.to_sym] if state.key?(key.to_sym)

      default
    end
  end
end
