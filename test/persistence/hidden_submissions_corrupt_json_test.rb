require_relative '../support/hidden_submission_files'
require_relative '../support/assertions'
include GameRoomTest::Assertions

identity = {session_id: 317, round_id: 'quiz:2', user: 'Alice'}
main = HiddenSubmissions::ProgramStorage::DEFAULT_PATH
recovery = main + '.recovery.json'
failures = []
checks = 0
Dir.mktmpdir('hidden-invalid-json-') do |directory|
  seed = File.join(directory, 'seed')
  program = HiddenSubmissionFiles.new(seed)
  vault = HiddenSubmissions::Vault.new(program.storage)
  first = vault.prepare(**identity, payload: {'answer' => 'żółw'})
  program.blocked = [main]
  latest = vault.prepare(**identity, payload: {'answer' => 'łęk'})
  old_bytes = File.binread(File.join(seed, main))
  latest_bytes = File.binread(File.join(seed, recovery))
  assert(latest != first && JSON.parse(latest_bytes)['storage_revision'] > JSON.parse(old_bytes)['storage_revision'],
    'Fixture did not create two real successive snapshots')
  operations = {
    current: ->(store) { store.reveal(**identity) },
    previous_commitment: ->(store) { store.reveal(**identity, commitment: first.commitment) },
    enumerate: ->(store) { store.envelopes(session_id: 317, user: 'Alice', round_prefix: 'quiz:') },
    prepare: ->(store) { store.prepare(**identity, payload: {'answer' => 'new'}) },
    discard: ->(store) { store.discard(**identity) },
    discard_confirmed: ->(store) { store.discard_confirmed(session_id: 317, receipts: [['quiz:2', 'Alice', latest.commitment]]) }
  }
  ['', '{"entries":', '{"entries":{}} trailing', "{\"entries\":\"\xff\"}".b].each_with_index do |invalid, kind|
    [main, recovery].each do |corrupt_path|
      operations.each do |name, operation|
        checks += 1
        path = File.join(directory, "case-#{checks}")
        FileUtils.mkdir_p(path)
        # Even when a valid older sidecar exists, malformed JSON is not a
        # missing file and cannot authorize choosing or replacing a secret.
        [main, recovery].each { |file| File.binwrite(File.join(path, file), file == corrupt_path ? invalid : old_bytes) }
        before = [main, recovery].to_h { |file| [file, File.binread(File.join(path, file))] }
        stored = HiddenSubmissionFiles.new(path)
        local = HiddenSubmissions::Vault.new(stored.storage)
        begin
          result = operation.call(local)
          cleanup = [:discard, :discard_confirmed].include?(name)
          failures << "#{kind}/#{corrupt_path}/#{name}: no StorageError" unless cleanup && result == false
        rescue HiddenSubmissions::StorageError
          failures << "#{kind}/#{name}: cleanup did not contain its error" if [:discard, :discard_confirmed].include?(name)
        end
        failures << "#{kind}/#{name}: attempted a write" unless stored.writes.empty?
        [main, recovery].each do |file|
          failures << "#{kind}/#{name}: changed #{file}" unless before[file] == File.binread(File.join(path, file))
        end
      end
    end
  end
  missing = HiddenSubmissions::Vault.new(HiddenSubmissionFiles.new(File.join(directory, 'missing')).storage)
  assert(missing.reveal(**identity).nil?, 'Genuinely missing storage was rejected')
  created = missing.prepare(**identity, payload: {'answer' => 'fresh'})
  assert(created == missing.reveal(**identity) && missing.verify(created), 'Missing storage cannot initialize normally')
end
assert(failures.empty?, "Invalid JSON silently changed hidden-answer storage: #{failures.inspect}")
puts "PASS hidden-answer malformed JSON: #{checks} real-file read/write/cleanup boundaries; missing storage still initializes"
