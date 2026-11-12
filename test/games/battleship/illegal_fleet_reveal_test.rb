require_relative '../../support/session_runner'
require_relative '../../../games/battleship'

valid = [[0, 1, 2, 3], [20, 21, 22], [40, 41, 42], [60, 61], [80, 81], [85, 86], [8], [28], [48], [68]]
touching = [[0, 1, 2, 3], [10, 11, 12], [30, 31, 32], [50, 51], [70, 71], [90, 91], [5], [7], [9], [25]]

[true, false].each do |allowed|
  game = GameRoomGames::Battleship.new
  h = NativeRoomHarness.new(game: game, users: %w[Alice Bob], options: game.normalize_options('touching' => allowed))
  begin
    h.start
    vault = HiddenSubmissions::Vault.new(HiddenSubmissions::MemoryStorage.new)
    context = GameRoomGames::ActionContext.new(session_id: h.session.fetch('__id'),
      table_id: h.table.fetch('__id'), hidden_submissions: vault)
    h.submit('Alice', context: context)
    h.submit('Alice', {'action' => 'seal', 'ships' => JSON.generate(valid)}, context: context)
    status, = game.action_for({'action' => 'seal', 'ships' => JSON.generate(touching)}, h.replay('Bob'), 'Bob', context: context)
    assert(status == (allowed ? :ok : :invalid), 'Ordinary setup must still reject an illegal fleet')

    # A modified client can seal its own bad setup, but cannot write as Alice.
    # Final verification must assess the evidence, not wait forever for a
    # different, legal payload which could never match that accepted seal.
    envelope = vault.prepare(session_id: context.session_id, round_id: 'fleet', user: 'Bob', payload: {'ships' => touching})
    h.write('Bob', [GameRoomGames::EventCommand.new(action: 'place', value: envelope.commitment)])
    misses = (0...100).to_a - valid.flatten
    struck = []
    touching.flatten.each_with_index do |cell, index|
      if index.positive?
        miss = misses.shift
        h.submit('Bob', {'kind' => 'grid', 'action' => 'select', 'x' => miss % 10, 'y' => miss / 10})
        h.submit('Alice', context: context)
      end
      h.submit('Alice', {'kind' => 'grid', 'action' => 'select', 'x' => cell % 10, 'y' => cell / 10})
      struck << cell
      ship = touching.find { |cells| cells.include?(cell) }
      result = ship.all? { |square| struck.include?(square) } ? 'sunk' : 'hit'
      h.write('Bob', [GameRoomGames::EventCommand.new(action: 'answer', value: result)])
    end
    before = h.replay('Alice')
    assert(before.state[:phase] == :revealing && before.accepted_events.size == h.events('Alice').size,
      'All normal shot/answer transitions must reach the actual reveal boundary')
    h.submit('Alice', context: context)
    h.write('Bob', [GameRoomGames::EventCommand.new(action: 'open', value: envelope.nonce)])

    # Structural corruption is not a fleet proof and must remain unaccepted.
    [nil, {}, [[100]], [[]], [[0]] * 11].each do |shape|
      h.write('Bob', [GameRoomGames::EventCommand.new(action: 'fleet', value: JSON.generate(shape))])
      assert(!h.replay('Alice').state[:fleets].key?('Bob'), 'Malformed fleet mutated the reveal state')
    end
    wire = game.send(:encode_fleet, touching)
    assert(HiddenSubmissions::Commitment.valid?(payload: {'ships' => touching}, nonce: envelope.nonce,
      commitment: envelope.commitment), 'The opened payload must prove the accepted seal')
    h.write('Bob', [GameRoomGames::EventCommand.new(action: 'fleet', value: wire)])
    final = h.replay('Alice')
    assert(final.finished? && final.winner == 'Alice', 'A complete illegal self-reveal must not strand the match')
    assert(final.state[:invalid] == (allowed ? [] : ['Bob']), 'Final audit must distinguish variant legality')
    assert(final.accepted_events.last['value'] == wire, 'The actual reveal evidence was not accepted')
    assert(final.history.count { |item| item.kind == :invalid } == (allowed ? 0 : 1), 'Invalid result was lost or duplicated')
    h.assert_converged('legal and disqualified final reveals')
  ensure
    h.users.each { |user| h.as(user) { h.view(user)&.leave } }
  end
end

puts 'PASS final fleet audit: complete matching but illegal self-reveal is disqualified; setup, structure and ordinary legal game preserved'
