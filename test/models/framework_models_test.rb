require_relative "../support/sequence_random"

require_relative "../../lib/game_random"
require_relative "../../lib/hidden_submissions"
require_relative "../support/hidden_submission_files"

def assert(condition, message)
  raise message if !condition
end

roll = GameRoomRandom::SequenceSource.new([6, 1, 4]).roll(count: 3, sides: 6)
assert(roll.values == [6, 1, 4] && roll.source == "test_sequence", "dice source returned an invalid roll")
assert(!GameRoomRandom::LocalSecureSource.new.authoritative?, "local randomness claims to be authoritative")

storage = HiddenSubmissions::MemoryStorage.new
vault = HiddenSubmissions::Vault.new(storage)
payload = {
  "country" => "Poland",
  "city" => "Poznan"
}
envelope = vault.prepare(
  session_id: 7,
  round_id: "round-1",
  user: "Alice",
  payload: payload,
  nonce: "fixed-test-nonce"
)
assert(envelope.commitment.length == 64, "hidden submission commitment has an invalid size")
assert(vault.verify(envelope), "fresh hidden submission did not verify")
retry_envelope = vault.prepare(session_id: 7, round_id: "round-1", user: "alice", payload: payload)
assert(retry_envelope.nonce == envelope.nonce && retry_envelope.commitment == envelope.commitment,
  "retrying the same submission replaced its nonce")
edited_envelope = vault.prepare(session_id: 7, round_id: "round-1", user: "Alice", payload: payload.merge("city" => "Warsaw"))
selected = vault.reveal(session_id: 7, round_id: "round-1", user: "alice", commitment: envelope.commitment)
assert(selected.payload == payload && vault.verify(selected), "editing a retry destroyed an already-accepted envelope")
assert(vault.reveal(session_id: 7, round_id: "round-1", user: "Alice", commitment: edited_envelope.commitment).payload["city"] == "Warsaw",
  "a retry accepted before the original submission cannot reveal the edited version")
assert(vault.reveal(session_id: 7, round_id: "round-1", user: "Alice", commitment: "unknown") == nil,
  "an unknown server commitment selected an unrelated answer")
restored = vault.reveal(session_id: 7, round_id: "round-1", user: "alice", commitment: envelope.commitment)
assert(restored.payload == payload, "hidden submission was not restored")
assert(
  HiddenSubmissions::Commitment.valid?(
    payload: payload,
    nonce: restored.nonce,
    commitment: restored.commitment
  ),
  "commitment verification failed"
)
tampered = payload.merge("city" => "Warsaw")
assert(
  !HiddenSubmissions::Commitment.valid?(
    payload: tampered,
    nonce: restored.nonce,
    commitment: restored.commitment
  ),
  "commitment accepted a modified answer"
)
assert(vault.discard(session_id: 7, round_id: "round-1", user: "Alice"), "hidden submission was not discarded")

# The retry history must survive the same JSON boundary used by real profiles.
program = HiddenSubmissionFiles.new
saved_vault = HiddenSubmissions::Vault.new(HiddenSubmissions::ProgramStorage.new(program))
first = saved_vault.prepare(session_id: 8, round_id: "1", user: "Bob", payload: payload)
saved_vault.prepare(session_id: 8, round_id: "1", user: "Bob", payload: tampered)
reopened_vault = HiddenSubmissions::Vault.new(HiddenSubmissions::ProgramStorage.new(program))
reopened = reopened_vault.reveal(session_id: 8, round_id: "1", user: "Bob", commitment: first.commitment)
assert(reopened.payload == payload && reopened_vault.verify(reopened), "reopening the vault lost an accepted commitment")
assert(vault.reveal(session_id: 7, round_id: "round-1", user: "Alice") == nil, "discarded submission remained available")

puts "Game framework model tests passed"
