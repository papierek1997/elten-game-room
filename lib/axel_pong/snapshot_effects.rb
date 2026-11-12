# frozen_string_literal: true

module GameRoomPong
  # Effect vocabulary shared by live snapshots and passive-file validation.
  # Contact cues index a paddle; wall/invisibility and ignored cues need not.
  module SnapshotEffects
    KINDS = %w[step edge serve hit wall shield_on shield_off shield_hit invisible goal].freeze
    PLAYER_REQUIRED = %w[serve hit shield_on shield_off shield_hit].freeze

    def self.player_required?(kind)
      PLAYER_REQUIRED.include?(kind)
    end
  end
end
