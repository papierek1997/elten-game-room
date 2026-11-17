# A smoothed, match-local model built exclusively from public history entries.
# Never accepts the replay state, concealed hands, deck or private discards.
module GameRoomPokerOpponents
  MAX_ENTRIES = 2048
  module_function

  def profiles(history)
    counts = Hash.new { |rows, name| rows[name] = new_counts.merge(contexts: {}) }
    last_aggression = {}
    history.last(MAX_ENTRIES).each do |entry|
      data = entry.value
      next unless data.is_a?(Hash)
      name = entry.actor.to_s.downcase
      next if name.empty?
      row = counts[name]
      if entry.field == 'poker_bet'
        record_bet(row,data)
        street_key = [data['street'],nil]
        record_bet(row[:contexts][street_key] ||= new_counts,data)
        if data['pot'].to_f.positive? && data['call'].positive?
          key = [data['street'],pressure_band(data['call'].fdiv(data['pot']+data['call']))]
          record_bet(row[:contexts][key] ||= new_counts,data)
        end
        if data.fetch('raise_by').positive?
          last_aggression[[name, data['hand']]] = data['street']
        end
      elsif entry.field == 'poker_showdown'
        street = last_aggression[[name, data['hand']]]
        # A missed river does not prove an earlier value bet was a bluff.
        # Only aggression at the final stage is calibrated from the shown hand.
        last_street = data['variant'] == 'draw' ? 1 : 3
        if street == last_street
          row[:shown] += 1
          row[:weak] += 1 if data.fetch('category') <= 1
          local = row[:contexts][[street,nil]]
          local[:shown] += 1
          local[:weak] += 1 if data.fetch('category') <= 1
        end
      end
    end
    counts.transform_values do |row|
      global = rates(row)
      global.merge(contexts: row[:contexts].to_h { |key,local| [key,rates(local,global).freeze] }.freeze).freeze
    end.freeze
  end

  def profile(profiles, player, street: nil, pressure: nil)
    global = profiles.fetch(player.to_s.downcase, {observations: 0, fold: 3.0 / 8, aggression: 2.0 / 8, weak_aggression: 1.0 / 6})
    return global if street.nil?
    contexts = global.fetch(:contexts,{})
    local = contexts.fetch([street,nil],global)
    return local if pressure.nil?
    # Size evidence adjusts response frequency, not showdown credibility.
    sized = contexts[[street,pressure_band(pressure)]]
    sized ? local.merge(fold:sized[:fold]) : local
  end

  def new_counts; {actions:0,faced:0,folds:0,raises:0,shown:0,weak:0}; end

  def record_bet(row,data)
    row[:actions] += 1
    row[:faced] += 1 if data['call'].positive?
    row[:folds] += 1 if data['action']=='fold' && data['call'].positive?
    row[:raises] += 1 if data['raise_by'].positive?
  end

  def pressure_band(pressure); pressure<=0.25 ? 0 : (pressure<=0.5 ? 1 : 2); end

  def rates(row,prior={fold:3.0/8,aggression:2.0/8,weak_aggression:1.0/6})
    {observations:row[:actions],fold:(8*prior[:fold]+row[:folds])/(8+row[:faced]),
      aggression:(8*prior[:aggression]+row[:raises])/(8+row[:actions]),
      weak_aggression:(6*prior[:weak_aggression]+row[:weak])/(6+row[:shown])}
  end

  def range_weight(profile, raises, strength, pressure: 0.0)
    # Frequent/bluff-heavy raisers have wider ranges than quiet value bettors.
    credibility = (1 - profile[:weak_aggression]) / (0.6 + profile[:aggression] * 3) * (1.35 / (5.0 / 6))
    # With no observations/pressure preserve the former neutral range. New
    # opponents must not look weak simply because no profile exists yet.
    evidence = [raises, 3].min * 1.5 * (1 + [pressure, 2].min * 0.25)
    (1 + evidence * (strength - 0.5) * credibility).clamp(0.12, 3.5)
  end

  def fold_probability(profile, pressure, raises)
    ((pressure * 0.8) * (profile[:fold] / (3.0 / 8)) / (1 + raises * 0.5)).clamp(0.005, 0.85)
  end

  # Public fold/call response model. Poker has at most seven opponents, so
  # every subset fits in 128 cases; no unbounded betting tree is introduced.
  def responders(players, fold_rates)
    raise ArgumentError, 'Too many poker opponents' if players.size > 7
    players.reduce([[[], 1.0]]) do |cases, player|
      fold = fold_rates.fetch(player)
      following = cases.flat_map do |calling, chance|
        result = []
        result << [calling, chance * fold] if fold.positive?
        result << [calling + [player], chance * (1 - fold)] if fold < 1
        result
      end
      Thread.pass
      following
    end
  end
end
