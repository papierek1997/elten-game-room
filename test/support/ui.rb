require_relative 'host_controls'
require_relative 'native_tasks'

def _(text)
  text
end

$spoken_messages = []
$speech_wait_calls = 0

def speak(text, **_options)
  $spoken_messages << text.to_s
end

def speech_wait
  $speech_wait_calls += 1
end

class FakeControl
  Registration = Struct.new(:dispose) do
    def close
      callback, self.dispose = dispose, nil
      callback&.call
    end
  end
  attr_accessor :header
  def initialize
    @handlers = {}
  end

  def on(event, *arguments, &handler)
    register_event(event, *arguments, &handler)
  end

  def register_event(event, *_arguments, &handler)
    @handlers ||= {}
    (@handlers[event] ||= []) << handler
    Registration.new(-> { @handlers[event].delete(handler) })
  end

  def trigger(event, payload = nil)
    @handlers[event].to_a.each { |handler| handler.call(payload) }
  end

  def bind_context(header = "", &handler)
    register_context(header, &handler)
  end

  def register_context(_header = "", &handler)
    (@contexts ||= []) << handler
    Registration.new(-> { @contexts.delete(handler) })
  end

  def context(menu, submenu = true)
    return if submenu && @context_disabled_globally

    @contexts.to_a.each { |handler| handler.call(menu) }
  end

  def disable_contextinglobal
    @context_disabled_globally = true
  end

  def contextinglobal_enabled?
    @context_disabled_globally != true
  end

  def add_tip(_tip)
  end

  def update
    nil
  end

  def key_processed(_key)
    true
  end
end

class GridBox < FakeControl
  attr_accessor :x, :y
  attr_reader :cells, :last_focus_spoken

  def initialize(width, height, header:, x:, y:, quiet:)
    super()
    @width = width
    @height = height
    @x = x
    @y = y
  end

  def set_cells(cells)
    @cells = cells
  end

  def move_by(dx, dy)
    @x = [[@x + dx.to_i, 0].max, @width - 1].min
    @y = [[@y + dy.to_i, 0].max, @height - 1].min
  end

  def focus(_index = nil, _count = nil, spk = true, include_header: true)
    @last_focus_spoken = spk
    true
  end
end

class ListBox < FakeControl
  attr_accessor :index, :header, :next_character, :options, :empty_label
  attr_reader :last_focus_spoken, :last_focus_header

  module Flags
    MultiSelection = 1
  end

  def initialize(options, header:, index: 0, flags: 0, quiet: true, empty_label: nil)
    super()
    @options = options
    @header = header
    @index = index
    @flags = flags
    @empty_label = empty_label
    @selected = Array.new(options.length, false)
  end

  def select_multiselection_indices(indices)
    indices.each { |index| @selected[index] = true if index.between?(0, @selected.length - 1) }
  end

  def options=(values)
    @item_keys = nil
    @options = values
    @selected = Array.new(values.length, false)
  end

  # The native-control regressions cover the full host implementation. This
  # model-only fixture keeps its stable identity/selection contract.
  def update_options(values, keys:, fallback: :nearest)
    raise ArgumentError, 'Invalid list keys' unless keys.length == values.length && keys.uniq.length == keys.length && !keys.include?(nil)
    previous = (@item_keys || []).each_with_index.to_h
    current = @item_keys&.[](@index)
    @selected = keys.map { |key| previous.key?(key) ? @selected[previous[key]] : false }
    @index = keys.index(current) || (fallback == :first ? 0 : [[@index.to_i, values.length - 1].min, 0].max)
    @options, @item_keys = values, keys.dup
    self
  end

  def require_multiselection_indices(indices)
    @required_multiselection_indices = indices.uniq.select { |index| index >= 0 && index < @options.size }
    select_multiselection_indices(@required_multiselection_indices)
  end

  def deselect_multiselection_indices(indices)
    indices = indices.uniq.select do |index|
      index >= 0 && index < @options.size && @selected[index] == true && !@required_multiselection_indices.to_a.include?(index)
    end
    return :unchanged if indices.empty?
    trigger(:multiselection_beforechanged)
    indices.each do |index|
      @selected[index] = false
      trigger(:multiselection_unselected, index)
    end
    trigger(:multiselection_changed)
    :changed
  end

  def multiselections
    @selected.each_index.select { |index| @selected[index] }
  end

  def focus(_index = nil, _count = nil, header = @header, spk = true)
    @last_focus_spoken = spk
    @last_focus_header = header
  end

  private

  def getkeychar(*_arguments)
    @next_character.to_s
  end
end

class Button < FakeControl
  attr_accessor :label
  attr_reader :last_focus_spoken

  def focus(_index = nil, _count = nil, spk = true)
    @last_focus_spoken = spk
  end

  def initialize(label)
    super()
    @label = label
  end
end

class Form < FakeControl
  attr_accessor :index, :cancel_button, :accept_button, :held_modifiers
  attr_reader :fields, :hidden_controls, :wait_entry_state, :wait_announced

  def initialize(fields, index: 0, quiet: true)
    super()
    @fields = fields
    @index = index
    @quiet = quiet
    @updated = false
    @hidden_controls = []
  end

  def controls
    @fields
  end

  def wait
    @wait_entry_state = [@updated, @quiet]
    @wait_announced = @announce_wait != false && (@updated == true || @quiet == true)
    @fields[@index.to_i]&.focus if @wait_announced
    @updated = true
  end

  def resume
    @wait = false
  end

  def resume_for_refresh
    @wait = false
  end

  def wait_without_announcement
    previous = @announce_wait
    @announce_wait = false
    wait
  ensure
    @announce_wait = previous
  end

  def show_all
    @hidden_controls = []
  end

  def hide(control)
    @hidden_controls << control if !@hidden_controls.include?(control)
  end

  def show(control)
    @hidden_controls.delete(control)
  end

  def add_timer(timer, *_arguments)
    (@timers ||= []) << timer
  end

  def delete_timer(timer)
    @timers.delete(timer)
  end

  def modifier_held?(modifier)
    @held_modifiers.to_a.include?(modifier)
  end

  def raw_key_held?(key)
    key == :key_shift && @held_modifiers.to_a.include?(:shift)
  end
end

class EditBox < FakeControl
  attr_accessor :text, :index, :check, :flags
  attr_reader :header, :last_focus_spoken

  module Flags
    ReadOnly = 1
    MultiLine = 2
    MarkDown = 32
  end

  class Element < Struct.new(:from, :to, :type, :param)
    Header = 1
    Link = 2
    ListItem = 4
    Frame = 14
  end

  def append_text_links; end

  def initialize(header, type: 0, text: "", quiet: true, max_length: -1, detect_text_links: true)
    super()
    @header = header
    @type = type
    @flags = type
    @text = text
    @index = @check = 0
    @max_length = max_length
    @elements = []
  end

  def focus(_index = nil, _count = nil, spk = true)
    @last_focus_spoken = spk
  end

  def set_text(text, reset = true, **_options)
    @text = text.to_s.delete("\r").sub(/\n+\z/, '')
    @index = reset ? 0 : @index.to_i.clamp(0, @text.length)
  end

  def text_len(value = @text)
    value.to_s.length
  end

  def context(menu, _submenu = false)
    menu.submenu("Edit") do |edit_menu|
      edit_menu.option("Quick translation", nil, "t") {}
      edit_menu.option("Translate", nil, "T") {}
    end
  end
end

class FakeMenu
  attr_reader :options

  def initialize
    @options = []
  end

  def option(label, value = nil, shortcut = "", &handler)
    @options << [label, value, shortcut, handler]
  end

  def submenu(_label)
    yield(self)
  end
end


# Match ELTEN's distinction between the active form-wide menu and the focused
# field's own context. Invitation shortcuts belong to the form so they remain
# available from every field.
def assert_global_invitation_menu(form, keys:)
  invitation_keys = %w[i I j J]
  global_menu = FakeMenu.new
  ([form] + form.fields).each do |control|
    control.context(global_menu, true)
    local_menu = FakeMenu.new
    control.context(local_menu, false)
    actual = local_menu.options.map { |option| option[2] } & invitation_keys
    expected = control.equal?(form) ? keys : []
    assert(actual.sort == expected.sort, "invitation shortcuts are attached to the wrong field")
  end
  actual_global = global_menu.options.map { |option| option[2] } & invitation_keys
  assert(actual_global.sort == keys.sort, "the global menu lost invitation shortcuts")
  events = form.instance_variable_get(:@handlers).keys
  assert(events.none? { |event| event.to_s.start_with?("game_room_invitation_") }, "form still intercepts invitation keys globally")
end

def assert_invitation_menu_scope(form, list:, keys:)
  invitation_keys = %w[i I j J]
  global_menu = FakeMenu.new
  ([form] + form.fields).each do |control|
    control.context(global_menu, true)
    local_menu = FakeMenu.new
    control.context(local_menu, false)
    actual = local_menu.options.map { |option| option[2] } & invitation_keys
    expected = control.equal?(list) ? keys : []
    assert(actual.sort == expected.sort, "invitation shortcuts are attached to the wrong field")
  end
  assert((global_menu.options.map { |option| option[2] } & invitation_keys).empty?, "invitation shortcuts leaked into the global menu")
  events = form.instance_variable_get(:@handlers).keys
  assert(events.none? { |event| event.to_s.start_with?("game_room_invitation_") }, "form still intercepts invitation keys globally")
end
