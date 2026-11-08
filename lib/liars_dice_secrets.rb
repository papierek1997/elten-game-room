require_relative "hidden_submissions"
require_relative "liars_dice_rules"

module GameRoomLiarsDiceSecrets
  module_function

  def round_id(state); "liars_dice:#{state[:round]}"; end
  def encode(hex); [[hex].pack("H*")].pack("m0"); end
  def payload(state, player, seed)
    # Seat/round survives archive restore; vault access keeps the live session boundary.
    {"seed"=>seed, "scope"=>"liars_dice:#{state[:round]}:#{state[:players].index(player)}"}
  end

  def decode(text)
    return nil unless text.is_a?(String) && text.match?(/\A[A-Za-z0-9+\/]{43}=\z/)
    bytes = text.unpack1("m0")
    bytes.unpack1("H*") if bytes.bytesize == 32 && [bytes].pack("m0") == text
  rescue ArgumentError
    nil
  end

  def envelope(state, player, context, create: false)
    return nil unless context&.hidden_submissions && context.session_id == state[:session_id]
    vault = context.hidden_submissions
    expected = state[:commits][player]
    value = vault.reveal(session_id: context.session_id, round_id: round_id(state), user: player, commitment: expected)
    if value == nil && create && expected == nil && context.random_source
      bytes = context.random_source.roll(count: 32, sides: 256).values
      hex = bytes.map { |byte| (byte - 1).to_s(16).rjust(2, "0") }.join
      value = vault.prepare(session_id: context.session_id, round_id: round_id(state), user: player,
        payload: payload(state, player, hex[0,32]), nonce: hex[32,32])
    end
    return nil unless value
    valid = vault.verify(value) && value.payload.is_a?(Hash) && value.payload == payload(state, player, value.payload["seed"]) &&
      value.payload["seed"].is_a?(String) && value.payload["seed"].match?(/\A[0-9a-f]{32}\z/) &&
      value.nonce.to_s.match?(/\A[0-9a-f]{32}\z/) && (expected == nil || value.commitment == expected)
    raise HiddenSubmissions::StorageError, "Invalid private dice envelope" unless valid
    value
  end

  def dice(state, player, context)
    return state[:reveals][player].dup if state[:reveals][player]
    return nil unless state[:seed] && state[:commits][player]
    value = envelope(state, player, context)
    GameRoomLiarsDiceRules.dice(state[:seed], value.payload["seed"], state[:counts][player]) if value
  end
end
