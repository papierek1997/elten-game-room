require_relative "ui"
require_relative "log"
FormTimer = EltenAPI::Controls::FormTimer unless defined?(FormTimer)

class CheckBox < FakeControl
  attr_accessor :checked
  attr_accessor :label

  def initialize(label, checked: false)
    super()
    @label = label
    @checked = checked
  end
end

class ListBox
  attr_reader :sayoption_count

  def sayoption
    @sayoption_count = @sayoption_count.to_i + 1
  end

  def update
    # The actual host focuses the selected row while processing arrows.
    focus if $game_room_widget_arrow
    super
  end
end

class Program
  def self.server_app(**options); @server_app_uuid = options.fetch(:uuid); end
  def self.server_app_uuid
    @server_app_uuid || (superclass.server_app_uuid if superclass.respond_to?(:server_app_uuid))
  end
  def self.app_runtime; nil; end
end

module Session
  def self.name; "Alice"; end
end

module EltenLink
  class Error < StandardError; end
  class Client; end
  module Contacts
    class << self
      attr_accessor :users, :calls, :error

      def list(_client)
        self.calls = calls.to_i + 1
        raise error if error
        users.to_a
      end
    end
  end
end

module EltenAPI
  module LiveSessions
    class Error < StandardError; end
    class TimeoutError < Error; end
    class SessionClosed < Error; end
    class StackFull < Error; end
  end
  module Tasks
    class Cancelled < StandardError; end
  end
end

require_relative "../../__app"

def assert(condition, message)
  raise message if !condition
end


WidgetSnapshot = Struct.new(:table, :members, keyword_init: true)
class WidgetSnapshot
  def participant_count; members.length; end
end
class WidgetManualWorker
  def start(&operation); return false if busy?; @operation = operation; true; end
  def busy?; @operation != nil || @result != nil; end
  def closed?; @closed == true; end
  def finish
    @result = [@operation.call, nil]
    @operation = nil
  rescue StandardError => error
    @result = [nil, error]
    @operation = nil
  end
  def take; value = @result; @result = nil; value; end
  def close; @closed = true; end
end

class FakePresentation
  attr_reader :default_suppressed

  def initialize(options)
    @options = options
  end

  def sound
    @options[:sound]
  end

  def suppress_default!
    @default_suppressed = true
    self
  end
end

class FakeNotification
  attr_reader :type, :metadata, :sender, :id, :app_uuid

  def initialize(sender)
    @id, @app_uuid = 1, "468f59c5-c9d7-47cd-80f1-1a6fbfd1aa80"
    @type = "game_room.invitation"
    @sender = sender
    @metadata = { "sender" => sender, "table_name" => "Room", "game_name" => "UNO" }
  end

  def presentation(**options)
    FakePresentation.new(options)
  end
end

$game_room_widget_r = false
def key_pressed?(key)
  key == 0x52 && $game_room_widget_r
end
