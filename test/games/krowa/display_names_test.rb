require_relative '../../support/krowa'

GameRoomParticipants.configure_display_name(account: 'Viewer', name: '')
GameRoomParticipants.remember_display_name('Alice', 'Anna Kowalska')
GameRoomParticipants.remember_display_name('Bob', 'Jan Nowak')

run = KrowaTestGame.new(variant: 'race', players: %w[Alice Bob])
assert(run.automatic == :ok, 'Krowa display-name fixture did not start')
assert(run.guess('Alice', 'las') == :ok && run.automatic == :ok, 'Krowa display-name fixture did not score a guess')
guess = run.replay.history.find { |entry| entry.kind == :guess }
assert(guess.actor == 'Alice' && guess.text.start_with?('Anna Kowalska: las,'), 'Krowa guess history lost a full name or changed its actor/word')
assert(run.guess('Alice', 'kot') == :ok && run.automatic == :ok, 'Krowa display-name fixture did not solve the word')
solved = run.replay.history.find { |entry| entry.kind == :solved }
assert(solved.actor == 'Alice' && solved.text.start_with?('Anna Kowalska guesses'), 'Krowa solved history still exposes a raw login')
assert(run.surrender('Bob') == :ok, 'Krowa display-name fixture did not surrender')
surrender = run.replay.history.find { |entry| entry.kind == :surrender }
assert(surrender.actor == 'Bob' && surrender.text == 'Jan Nowak surrenders.', 'Krowa surrender history lost the full name or canonical actor')
summary = run.game.send(:result_summary, run.replay.state)
assert(summary.include?('Anna Kowalska:') && summary.include?('Jan Nowak: surrendered'), 'Krowa results did not keep full names')
label = run.game.send(:trial_label, run.replay.state[:attempts].first, 3, show_player: true)
assert(label.start_with?('Anna Kowalska: las,'), 'Krowa attempt list did not keep full names and the original word')
assert(run.replay.state[:results].keys.sort == %w[Alice Bob] && run.events.all? { |event| %w[Alice Bob].include?(event['actor']) },
  'Krowa display labels changed canonical result or event keys')

vocabulary = KrowaTestGame.new
vocabulary.automatic
assert(vocabulary.guess('Alice', 'lis', adding: true) == :ok, 'Krowa vocabulary fixture did not add a noun')
dictionary = vocabulary.replay.history.find { |entry| entry.kind == :dictionary }
assert(dictionary.actor == 'Alice' && dictionary.text == 'Anna Kowalska adds a noun: lis.', 'Krowa vocabulary history changed the noun or kept the raw actor label')
assert(vocabulary.events.find { |event| event['action'] == 'krowa_vocab' }['value'] == 'lis', 'Krowa noun bytes were rewritten')

tower = KrowaTestGame.new(variant: 'tower', players: %w[Alice Bob])
tower.automatic
spec = tower.game.surface_spec(tower.replay, 'Alice')
turn = spec.parts.find { |part| part.id == 'turn' }.surface.options.first.label
assert(turn == 'Anna Kowalska', 'Krowa inspected turn list lost the full name')
assert(tower.replay.current_player == 'Alice', 'Krowa displayed turn changed the canonical player')
puts 'PASS Krowa full names in guess/solved/surrender/dictionary history and result/attempt/turn lists, unchanged actors and noun bytes'
