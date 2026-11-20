require_relative '../../support/krowa'

run = KrowaTestGame.new(variant: 'race', players: %w[Alice Bob])
assert(run.automatic == :ok, 'Krowa account-name fixture did not start')
assert(run.guess('Alice', 'las') == :ok && run.automatic == :ok, 'Krowa account-name fixture did not score a guess')
guess = run.replay.history.find { |entry| entry.kind == :guess }
assert(guess.actor == 'Alice' && guess.text.start_with?('Alice: las,'), 'Krowa guess history lost the account name or changed its actor/word')
assert(run.guess('Alice', 'kot') == :ok && run.automatic == :ok, 'Krowa account-name fixture did not solve the word')
solved = run.replay.history.find { |entry| entry.kind == :solved }
assert(solved.actor == 'Alice' && solved.text.start_with?('Alice guesses'), 'Krowa solved history lost the account login')
assert(run.surrender('Bob') == :ok, 'Krowa account-name fixture did not surrender')
surrender = run.replay.history.find { |entry| entry.kind == :surrender }
assert(surrender.actor == 'Bob' && surrender.text == 'Bob surrenders.', 'Krowa surrender history lost the full name or canonical actor')
summary = run.game.send(:result_summary, run.replay.state)
assert(summary.include?('Alice:') && summary.include?('Bob: surrendered'), 'Krowa results did not keep full names')
label = run.game.send(:trial_label, run.replay.state[:attempts].first, 3, show_player: true)
assert(label.start_with?('Alice: las,'), 'Krowa attempt list did not keep full names and the original word')
assert(run.replay.state[:results].keys.sort == %w[Alice Bob] && run.events.all? { |event| %w[Alice Bob].include?(event['actor']) },
  'Krowa display labels changed canonical result or event keys')

vocabulary = KrowaTestGame.new
vocabulary.automatic
assert(vocabulary.guess('Alice', 'lis', adding: true) == :ok, 'Krowa vocabulary fixture did not add a noun')
dictionary = vocabulary.replay.history.find { |entry| entry.kind == :dictionary }
assert(dictionary.actor == 'Alice' && dictionary.text == 'Alice adds a noun: lis.', 'Krowa vocabulary history changed the noun or account label')
assert(vocabulary.events.find { |event| event['action'] == 'krowa_vocab' }['value'] == 'lis', 'Krowa noun bytes were rewritten')

tower = KrowaTestGame.new(variant: 'tower', players: %w[Alice Bob])
tower.automatic
spec = tower.game.surface_spec(tower.replay, 'Alice')
turn = spec.parts.find { |part| part.id == 'turn' }.surface.options.first.label
assert(turn == 'Alice', 'Krowa inspected turn list lost the full name')
assert(tower.replay.current_player == 'Alice', 'Krowa displayed turn changed the canonical player')
puts 'PASS Krowa account names in guess/solved/surrender/dictionary history and result/attempt/turn lists, unchanged actors and noun bytes'
