module GameSurfaces
  SurfacePart = Struct.new(:id, :surface, keyword_init: true)
  CompositeSpec = Struct.new(:parts, keyword_init: true)

  class CompositeSurface
    include ActionEmitter

    attr_reader :command_field_index

    def initialize(spec, state: {}, previous: nil)
      @spec = spec
      @parts = @spec.parts.to_a
      validate_parts!
      remembered = state_value(state, "parts", {})
      @surfaces = @parts.map do |part|
        child_state = remembered_value(remembered, part.id)
        surface = GameSurfaces.reconcile(part.surface, previous: previous, state: child_state)
        surface.on_action do |action|
          @action_handler&.call(action.with_source(part.id))
        end
        surface
      end
      raise ArgumentError, "a composite surface must expose at least one field" if fields.empty?
    end

    def fields
      @surfaces.flat_map(&:fields)
    end

    # Layout may place selected game controls after the shared chat/history.
    # Actions and remembered state still belong to their original surface.
    def fields_for_parts(ids)
      @parts.each_with_index.flat_map do |part, index|
        ids.include?(part.id.to_s) ? @surfaces[index].fields : []
      end
    end

    def state
      values = {}
      @parts.each_with_index do |part, index|
        values[part.id.to_s] = @surfaces[index].state
      end
      { "parts" => values }
    end

    def reuse_candidates
      @surfaces.flat_map { |surface| surface.respond_to?(:reuse_candidates) ? surface.reuse_candidates : [surface] }
    end

    def take_cursor_announcement(field_index = nil)
      offset = 0
      message = nil
      @surfaces.each do |surface|
        count = surface.fields.length
        selected = field_index != nil && field_index >= offset && field_index < offset + count
        value = surface.take_cursor_announcement(selected ? field_index - offset : nil)
        message = value if selected
        offset += count
      end
      message
    end

    def submission_action
      @surfaces.each do |surface|
        next if !surface.respond_to?(:submission_action)

        action = surface.submission_action
        return action if action != nil
      end
      nil
    end

    def suppress_next_focus!(field_index = 0)
      remaining = field_index.to_i
      @surfaces.each do |surface|
        count = surface.fields.length
        if remaining < count
          surface.suppress_next_focus!(remaining)
          return
        end
        remaining -= count
      end
    end

    def cancel_pending_action?
      @surfaces.any? do |surface|
        surface.respond_to?(:cancel_pending_action?) && surface.cancel_pending_action?
      end
    end

    def cancel_pending_action!
      surface = @surfaces.find do |candidate|
        candidate.respond_to?(:cancel_pending_action?) && candidate.cancel_pending_action?
      end
      return false if surface == nil

      surface.cancel_pending_action!
    end

    def handle_command(command, payload = {})
      @command_field_index = nil
      offset = 0
      @surfaces.each do |surface|
        if surface.respond_to?(:handle_command)
          result = surface.handle_command(command, payload)
          if result
            child_index = surface.respond_to?(:command_field_index) ? surface.command_field_index : nil
            @command_field_index = offset + (child_index || 0)
            return result
          end
        end
        offset += surface.fields.length
      end
      false
    end

    private

    def validate_parts!
      raise ArgumentError, "a composite surface requires parts" if @parts.empty?
      ids = @parts.map { |part| part.id.to_s }
      raise ArgumentError, "surface part ids must not be empty" if ids.any?(&:empty?)
      raise ArgumentError, "surface part ids must be unique" if ids.uniq.length != ids.length
      raise ArgumentError, "surface parts require a specification" if @parts.any? { |part| part.surface == nil }
    end

    def remembered_value(remembered, id)
      return {} if !remembered.respond_to?(:key?)
      return remembered[id.to_s] if remembered.key?(id.to_s)
      return remembered[id.to_sym] if id.respond_to?(:to_sym) && remembered.key?(id.to_sym)

      {}
    end

    def state_value(state, key, default)
      return default if !state.respond_to?(:key?)
      return state[key] if state.key?(key)
      return state[key.to_sym] if state.key?(key.to_sym)

      default
    end
  end
end
