require_relative '../../support/cat_head_tail'
values = CatHeadTailPlanning.turn_values
assert(values.frozen? && values.size == 257, 'Shared continuation values are not bounded/immutable')
maximum_error = 0.0
(-80..110).each do |total|
  at = ->(sum) { values.fetch(sum + 128) }
  # Independent one-step enumeration: two and seven retain the turn, but
  # only two banks two points immediately. One loses the unbanked total.
  outcomes = [0.0, 2 + at.call(total), at.call(total + 3), at.call(total + 4),
    at.call(total + 5), at.call(total + 6), at.call(total), (at.call(total - 8) + at.call(total + 8)) / 2]
  best = [total.to_f, outcomes.sum / 8].max
  maximum_error = [maximum_error, (at.call(total) - best).abs].max
end
assert(maximum_error < 1e-7, 'Turn values disagree with real eight-sided outcome probabilities')
assert(values[19 + 128] > 19 && (values[24 + 128] - 24).abs < 1e-8, 'Rolling/banking thresholds are not the expected-value policy')
assert(values.equal?(CatHeadTailPlanning.turn_values), 'Recomputed the table for another candidate/turn')
puts 'PASS eight-sided Bellman expectation, banked two, repeat seven, signed eight and reused bounded values'
