# Native LiveSessions failures do not inherit from EltenLink::Error. Keep the
# expected network boundary shared, without swallowing programming errors.
module GameRoomNetworkErrors
  # An earlier move must be resolved before another plan can replace it.
  class PendingMove < StandardError; end
  class UncertainWrite < StandardError; end
  class UnsupportedInvitation < StandardError; end
  class GamePaused < StandardError; end
  # A roster or owner can change after the participant menu was opened.
  # Keep this expected conflict distinct from invalid arguments/programming errors.
  class RoleChangeUnavailable < ArgumentError
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super(reason == :not_owner ? "Only the table master may change another user's role" : "The user is not at this table")
    end
  end
  class ClockUnavailable < IOError; end

  def self.expected?(error)
    error.is_a?(PendingMove) || error.is_a?(UncertainWrite) || error.is_a?(UnsupportedInvitation) || error.is_a?(GamePaused) || error.is_a?(ClockUnavailable) ||
      (defined?(EltenLink::Error) && error.is_a?(EltenLink::Error)) ||
      (defined?(EltenAPI::LiveSessions::Error) && error.is_a?(EltenAPI::LiveSessions::Error))
  end

  def self.cancelled?(error)
    defined?(EltenAPI::Tasks::Cancelled) && error.is_a?(EltenAPI::Tasks::Cancelled)
  end

  def self.transient?(error)
    return true if error.is_a?(PendingMove) || error.is_a?(UncertainWrite) || error.is_a?(ClockUnavailable) || cancelled?(error)
    return false if !expected?(error)

    name = error.class.name.to_s.split("::").last
    return true if %w[TimeoutError QueueOverflow].include?(name)
    code = error.respond_to?(:code) ? error.code.to_s : ""
    return true if %w[network_error timeout invalid_json rate_limits.exceeded rate_limits.unavailable
      apps.live_sessions.rate_limited apps.live_sessions.busy apps.live_sessions.unavailable].include?(code)
    status = error.respond_to?(:status) ? error.status.to_i : 0
    return true if status == 429 || status.between?(500, 599)
    text = "#{code} #{error.message}"
    text.match?(/(?:network_error|timeout|temporar|unavailable|connection|rate.?limit|too many requests|HTTP (?:429|5\d\d))/i)
  end

  def self.retry_delay(error, normal:, rate_limit:)
    code = error.respond_to?(:code) ? error.code.to_s : ""
    limited = "#{code} #{error.message}".match?(/(?:too many requests|rate.?limit|\b429\b)/i)
    limited ||= error.respond_to?(:status) && error.status.to_i == 429
    advertised = error.respond_to?(:retry_after) ? error.retry_after.to_f : 0.0
    advertised = 0.0 if !advertised.finite?
    [limited ? rate_limit : normal, advertised].max
  end
end
