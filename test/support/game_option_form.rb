require_relative "ui"
require_relative "log"
FormTimer = EltenAPI::Controls::FormTimer unless defined?(FormTimer)

class Program
  def self.server_app(**options); @server_app_uuid = options.fetch(:uuid); end
  def self.server_app_uuid
    @server_app_uuid || (superclass.server_app_uuid if superclass.respond_to?(:server_app_uuid))
  end
end

module Session
  def self.name
    "Alice"
  end
end

class EditBox
  undef_method :text=

  module Flags
    Numbers = 8
  end

  def select_all
    @index, @check = 0, text.length
  end
end

class Static < FakeControl
  attr_reader :text

  def initialize(text)
    super()
    @text = text
  end

  def focus(*_arguments); end
end

class Form
  class << self
    attr_accessor :driver
  end

  alias wait_with_option_test_driver wait

  def wait
    wait_with_option_test_driver
    Form.driver.call(self)
  end

  def resume; end
end

require_relative "../../__app"

def assert(condition, message)
  raise message if !condition
end

class CheckBox < FakeControl
  attr_accessor :checked
  def initialize(label, checked: false)
    super()
    @header, @checked = label, checked
  end
end
