require 'securerandom'

module GameRoomPresence
  module Identity
    module_function

    def create
      SecureRandom.uuid
    end

    def valid?(value)
      value.is_a?(String) && value.ascii_only? &&
        /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/.match?(value)
    end
  end
end
