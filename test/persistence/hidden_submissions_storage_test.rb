require "tmpdir"
require_relative "../support/hidden_submission_files"

def assert(condition, message)
  raise message unless condition
end

MAIN = HiddenSubmissions::ProgramStorage::DEFAULT_PATH
RECOVERY = MAIN + ".recovery.json"
KEY = { session_id: 217, round_id: "1:1", user: "Alice" }.freeze

Dir.mktmpdir("game-room-hidden-217-") do |dir|
  program = HiddenSubmissionFiles.new(dir)
  vault = HiddenSubmissions::Vault.new(program.storage)
  20.times { assert(!vault.discard(**KEY), "missing envelope was removed") }
  assert(program.writes.empty?, "discard of missing envelope wrote a file")
  first = vault.prepare(**KEY, payload: { "answer" => "2" })
  count = program.writes.size
  assert(vault.prepare(**KEY, payload: { "answer" => "2" }).commitment == first.commitment, "retry changed nonce")
  assert(program.writes.size == count, "identical retry wrote a file")

  program.blocked = [MAIN]
  edited = vault.prepare(**KEY, payload: { "answer" => "3" })
  fresh = HiddenSubmissions::Vault.new(HiddenSubmissionFiles.new(dir).storage)
  assert(fresh.reveal(**KEY).commitment == edited.commitment, "restart lost the recovery snapshot")
  assert(fresh.reveal(**KEY, commitment: first.commitment).payload == { "answer" => "2" }, "recovery lost an accepted older nonce")
  assert(vault.discard(**KEY), "recovery could not persist cleanup")
  fresh = HiddenSubmissions::Vault.new(HiddenSubmissionFiles.new(dir).storage)
  assert(fresh.reveal(**KEY).nil?, "stale main file resurrected a removed answer")
  count = program.writes.size
  20.times { vault.discard(**KEY) }
  assert(program.writes.size == count, "repeated confirmed cleanup wrote again")

  program.blocked = []
  vault.prepare(**KEY, payload: { "answer" => "1" })
  assert(program.writes.last == MAIN, "recovered main file was not reused")
  before = File.binread(File.join(dir, MAIN))
  program.blocked = [MAIN, RECOVERY]
  begin
    vault.prepare(**KEY.merge(user: "Bob"), payload: { "answer" => "0" })
    raise "unsaved answer was accepted"
  rescue HiddenSubmissions::StorageError
  end
  assert(File.binread(File.join(dir, MAIN)) == before, "failed prepare altered the original")
  assert(vault.reveal(**KEY.merge(user: "Bob")).nil?, "failed prepare leaked into committed storage")
  count = program.writes.size
  20.times { assert(!vault.discard(**KEY), "unwritable cleanup claimed success") }
  assert(program.writes.size == count, "unwritable cleanup hammers the disk")
  program.blocked = []
  program.retry_now
  assert(vault.discard(**KEY), "cleanup could not retry after recovery")
  assert(Dir.children(dir).none? { |n| n.include?(".tmp-") }, "temporary files leaked")

  # Two screens of the same Program cannot overwrite each other's answers.
  stores = 2.times.map { program.storage }
  threads = stores.each_with_index.map do |store, i|
    Thread.new do
      15.times { |n| store.update { |root| Thread.pass; root["entries"]["#{i}:#{n}"] = n } }
    end
  end
  threads.each(&:value)
  assert(stores.first.read["entries"].size == 30, "concurrent updates lost entries")
end

if Gem.win_platform?
  require "fiddle/import"
  module HiddenStorageWindowsLock
    extend Fiddle::Importer
    dlload "kernel32.dll"
    extern "void* CreateFileW(void*, unsigned long, unsigned long, void*, unsigned long, unsigned long, void*)"
    extern "int CloseHandle(void*)"
  end
  Dir.mktmpdir("game-room-locked-217-") do |dir|
    program = HiddenSubmissionFiles.new(dir)
    vault = HiddenSubmissions::Vault.new(program.storage)
    first = vault.prepare(**KEY, payload: { "answer" => "0" })
    path = File.join(dir, MAIN).tr("/", "\\").encode("UTF-16LE").b + "\0\0".b
    # Allow read/write but deny FILE_SHARE_DELETE, as with a transient reader.
    handle = HiddenStorageWindowsLock.CreateFileW(path, 0x80000000, 3, nil, 3, 0x80, nil)
    assert(handle.to_i != 0 && handle.to_i != -1, "cannot create native test lock")
    begin
      begin
        program.write_json(MAIN, { "entries" => {} })
        raise "native lock did not reproduce the ELTEN replacement failure"
      rescue Errno::EACCES, Errno::EPERM
      end
      second = vault.prepare(**KEY, payload: { "answer" => "1" })
      fresh = HiddenSubmissions::Vault.new(HiddenSubmissionFiles.new(dir).storage)
      assert(fresh.reveal(**KEY).commitment == second.commitment, "native lock lost the new answer")
      assert(fresh.reveal(**KEY, commitment: first.commitment).commitment == first.commitment, "native lock lost old commitment")
      assert(vault.discard(**KEY), "native lock prevented safe cleanup")
      assert(fresh.reveal(**KEY).nil?, "native lock cleanup resurrected the main envelope")
    ensure
      HiddenStorageWindowsLock.CloseHandle(handle)
    end
  end
  puts "Native Windows replacement EACCES reproduced; prepare/reopen/discard recovered"
end
puts "Hidden submission storage regressions passed"
