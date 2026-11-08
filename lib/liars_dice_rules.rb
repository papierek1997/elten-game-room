require "digest"

module GameRoomLiarsDiceRules
  module_function

  def raise_allowed?(quantity, face, bid, variant:, total:, palifico: false, may_change: false)
    return false unless quantity.is_a?(Integer) && face.is_a?(Integer) && quantity.between?(1, total) && face.between?(1, 6)
    return !(variant == "perudo" && face == 1 && !palifico) unless bid
    old_quantity, old_face = bid.values_at(:quantity, :face)
    if palifico
      may_change ? (quantity > old_quantity || (quantity == old_quantity && face > old_face)) : (quantity > old_quantity && face == old_face)
    elsif variant == "perudo" && face == 1 && old_face != 1
      quantity >= (old_quantity + 1) / 2
    elsif variant == "perudo" && face != 1 && old_face == 1
      quantity >= old_quantity * 2 + 1
    else
      quantity > old_quantity || (quantity == old_quantity && face > old_face)
    end
  end

  def count(dice, face, variant:, palifico: false)
    dice.count { |value| value == face || (variant == "perudo" && !palifico && face != 1 && value == 1) }
  end

  def dice(server_seed, secret, count)
    raise ArgumentError, "Invalid private dice count" unless count.is_a?(Integer) && count.between?(1, 5)
    values, counter = [], 0
    while values.size < count
      bytes = Digest::SHA256.digest("powergames/liars_dice/v1/#{server_seed}/#{secret}/#{counter}").bytes
      values.concat(bytes.select { |byte| byte < 252 }.map { |byte| byte % 6 + 1 })
      counter += 1
    end
    values.take(count)
  end
end
