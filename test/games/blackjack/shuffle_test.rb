require_relative "../../support/elten_array_shuffle"
require_relative "../../../games/blackjack"
require_relative "../../support/blackjack"

game = GameRoomGames::Blackjack.new
repository = BlackjackChecksSupport::Repository.new(%w[Alice Bob])
session = {"options" => JSON.generate(game.default_options)}
event = BlackjackChecksSupport.event(1, "Alice", "deal", "1|#{'a' * 32}")
first = game.replay(session, [event], repository)
second = game.replay(session, [event], repository)
raise "Deal or replay changed under the host shuffle API" unless first.state == second.state
cards = first.state[:deck] + first.state[:dealer] + first.state[:hands].values.flatten.flat_map { |hand| hand[:cards] }
raise "Duplicate physical cards" unless cards.size == 312 && cards.uniq.size == 312
random, reference = Random.new(1234), Random.new(1234)
values = (0...312).to_a
expected = values.dup
(expected.size - 1).downto(1) do |index|
  other = reference.rand(index + 1)
  expected[index], expected[other] = expected[other], expected[index]
end
raise "Shuffle order changed" unless GameRoomRandom.shuffle(values, random: random) == expected
raise "Subsequent RNG state changed" unless random.rand(1_000_000) == reference.rand(1_000_000)
puts "Blackjack shuffle: deal, replay, physical IDs and subsequent RNG state passed"
