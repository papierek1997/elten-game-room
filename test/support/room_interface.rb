require_relative "ui"
require_relative "log"
require_relative "manual_form_timer"

class Program
  def self.server_app(**_options); end

  def self.read_json(_path, default:)
    Marshal.load(Marshal.dump(default))
  end
end

module Session
  def self.name
    "Alice"
  end
end

class Form
  class << self
    attr_accessor :driver
  end

  alias wait_with_native_entry wait

  def wait
    raise "unexpected form wait" if Form.driver == nil
    wait_with_native_entry
    Form.driver.call(self)
  end

  def resume; end

  def focus
    fields[index].focus
  end

  def keyboard_idle_frame?
    true
  end
end

require_relative "../../__app"

def assert(condition, message)
  raise message unless condition
end

class InterfaceGameRepository
  def players_for(_session)
    ["Alice", "Bob"]
  end

  def actor_of(event, _session = nil)
    event["actor"]
  end

  def event_id(event)
    event["id"]
  end

  def session_id(session)
    session.to_h["__id"].to_i
  end
end
