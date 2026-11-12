require_relative '../../support/duck_game_adapter'
include GameRoomTest::Assertions

class DuckScoreCleanupStorage < HiddenSubmissions::MemoryStorage
  attr_accessor :blocked
  attr_reader :reads, :failed_updates
  def initialize
    super
    @reads = @failed_updates = 0
  end
  def read
    @reads += 1
    super
  end
  def update(&block)
    if @blocked
      @failed_updates += 1
      raise HiddenSubmissions::StorageError, 'Deliberately unavailable local score cleanup'
    end
    super
  end
end

# A normal current game accepts real locally played compact rhythm results.
# This is not an injected closure or an invented result bypassing action_for.
fixture = DuckGameAdapterTest::Harness.new(kind: 'rhythm')
stores = fixture.players.to_h { |user| [user, DuckScoreCleanupStorage.new] }
stores.each { |user, storage| fixture.vaults[user] = HiddenSubmissions::Vault.new(storage) }
fixture.open_round
round = fixture.replay.state.fetch(:round)
assert_equal(:playing, round.fetch(:phase))
challenge = round.fetch(:challenge)
plans = challenge.fetch(:participants).to_h do |seat|
  [seat, GameRoomDuckRacing::ChallengeBot.plan(challenge, seat: seat, seed: 90,
    resources: fixture.resources, compact: true)]
end
at = round.fetch(:started_at) + plans.values.map(&:last).max + 1
challenge.fetch(:participants).each do |seat|
  fixture.accept({'action' => 'submit_trace', 'challenge' => challenge.fetch(:id),
    'trace' => plans.fetch(seat).first}, actor: fixture.players.fetch(seat), at: at)
end
replay = fixture.replay
assert_equal(challenge.fetch(:id), replay.state.fetch(:last_resolution).fetch(:id))
user = fixture.players.first
vault, storage = fixture.vault(user), stores.fetch(user)
scope = {session_id: fixture.session.fetch('__id'), round_id: "duck-score:#{challenge.fetch(:id)}", user: user}
original = vault.reveal(**scope)
assert(original && vault.verify(original), 'Accepted local result has no durable copy')
other = fixture.vault(fixture.players.last).reveal(**scope.merge(user: fixture.players.last))
unresolved = vault.prepare(**scope.merge(round_id: 'duck-score:99999'),
  payload: original.payload.merge('round' => 99999))
foreign = vault.prepare(**scope.merge(session_id: scope.fetch(:session_id) + 1), payload: original.payload)
before = storage.read
storage.blocked = true
fixture.game.cleanup_session_answers(replay, session_id: scope.fetch(:session_id),
  actors: [user], hidden_submissions: vault)
assert_equal(1, storage.failed_updates)
assert_equal(before, storage.read, 'Failed cleanup changed an existing envelope')
storage.blocked = false
fixture.game.cleanup_session_answers(replay, session_id: scope.fetch(:session_id),
  actors: [user], hidden_submissions: vault)
assert_equal(nil, vault.reveal(**scope), 'Same-replay retry was incorrectly memoized as complete')
assert_equal(unresolved, vault.reveal(**scope.merge(round_id: 'duck-score:99999')))
assert_equal(foreign, vault.reveal(**scope.merge(session_id: scope.fetch(:session_id) + 1)))
assert_equal(other, fixture.vault(fixture.players.last).reveal(**scope.merge(user: fixture.players.last)))
reads = storage.reads
fixture.game.cleanup_session_answers(replay, session_id: scope.fetch(:session_id),
  actors: [user], hidden_submissions: vault)
assert_equal(reads, storage.reads, 'Successful score cleanup kept reading the vault')

# The same existing atomic commitment guard protects a replacement between
# enumeration and removal. A failed compare must not be memoized as cleaned.
vault.prepare(**scope, payload: original.payload, nonce: original.nonce)
replacement_storage = HiddenSubmissions::MemoryStorage.new
replacement_vault = HiddenSubmissions::Vault.new(replacement_storage)
answer = original.payload.fetch('answer').fetch('score')
replacement = replacement_vault.prepare(**scope,
  payload: original.payload.merge('answer' => {'score' => [answer[0] + 1, answer[1]]}))
replacement_data = replacement_storage.read.fetch('entries').values.first
current_update = storage.method(:update)
storage.define_singleton_method(:update) do |&block|
  current_update.call do |root|
    key = root.fetch('entries').find do |_key, entry|
      entry['session_id'] == scope.fetch(:session_id) && entry['round_id'] == scope.fetch(:round_id) &&
        entry['user'] == user
    end&.first
    root.fetch('entries')[key] = replacement_data if key
    block.call(root)
  end
end
fresh = GameRoomGames::DuckRacing.new(resources: fixture.resources)
fresh.cleanup_session_answers(replay, session_id: scope.fetch(:session_id),
  actors: [user], hidden_submissions: vault)
assert_equal(replacement.commitment, vault.reveal(**scope)&.commitment,
  'Atomic cleanup deleted a replacement with a different commitment')
memo = fresh.instance_variable_get(:@duck_cleanup_checked) || {}
assert(!memo.key?([scope.fetch(:session_id), user.downcase]), 'Commitment conflict was memoized as complete')
puts 'PASS accepted compact score cleanup: false-return retry, successful memo, own scope and atomic commitment guard'
