require_relative "specifications"
require_relative "../game_room_localization"

module GameSurfaces
  using GameRoomLocalization::Translations



  class AnswerSheet
    include ActionEmitter

    def initialize(spec, state: {})
      @spec = spec
      raise ArgumentError, "an answer sheet requires an id" if @spec.id.to_s.empty?
      remembered_id = state_value(state, "sheet_id", @spec.id)
      state = {} if remembered_id.to_s != @spec.id.to_s
      @field_specs = @spec.fields.to_a
      validate_fields!
      remembered = state_value(state, "answers", {})
      @heading = build_heading if !@spec.title.to_s.empty?
      @controls = @field_specs.map do |field|
        value = remembered_value(remembered, field)
        flags = 0
        flags |= EditBox::Flags::ReadOnly if @spec.read_only == true
        flags |= EditBox::Flags::MultiLine if field.multiline == true
        RefreshAwareEditBox.new(
          field.label.to_s,
          type: flags,
          text: value,
          quiet: true,
          max_length: maximum_length(field)
        )
      end
      @submit = build_submit_button
    end

    def fields
      [@heading].compact + @controls + [@submit].compact
    end

    def state
      { "sheet_id" => @spec.id.to_s, "answers" => answers }
    end

    def submission_action
      return nil if @spec.read_only == true

      GameSurfaces::Action.new(
        kind: "answer_sheet",
        name: "submit",
        payload: {
          "sheet_id" => @spec.id.to_s,
          "answers" => answers,
          "required_fields" => @field_specs.select { |field| field.required == true }.map { |field| field.id.to_s }
        }
      )
    end

    private

    def build_heading
      RefreshAwareListBox.new(
        [_('Use Tab to move between answer fields.')],
        header: @spec.title.to_s,
        index: 0,
        quiet: true
      )
    end

    def build_submit_button
      return nil if @spec.read_only == true

      button = Button.new((@spec.submit_label || _("Submit answers")).to_s)
      button.on(:press) do
        action = submission_action
        emit_action(action.kind, action.name, action.payload, source: action.source) if action != nil
      end
      button
    end

    def answers
      result = {}
      @field_specs.each_with_index do |field, index|
        result[field.id.to_s] = @controls[index].text.to_s
      end
      result
    end

    def validate_fields!
      raise ArgumentError, "an answer sheet requires fields" if @field_specs.empty?
      ids = @field_specs.map { |field| field.id.to_s }
      raise ArgumentError, "answer field ids must not be empty" if ids.any?(&:empty?)
      raise ArgumentError, "answer field ids must be unique" if ids.uniq.length != ids.length
    end

    def maximum_length(field)
      configured = field.max_length.to_i
      configured > 0 ? configured : 64
    end

    def remembered_value(remembered, field)
      return field.value.to_s if !remembered.respond_to?(:key?)
      return remembered[field.id.to_s].to_s if remembered.key?(field.id.to_s)
      return remembered[field.id.to_sym].to_s if field.id.respond_to?(:to_sym) && remembered.key?(field.id.to_sym)

      field.value.to_s
    end


  end
end
