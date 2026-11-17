require 'json'
require_relative '../../../tools/darts/export-ranking-migration'

def assert(value, message)
  raise message unless value
end

path = File.expand_path('../../../docs/DARTS_RANKINGS_MIGRATION_V2.json', __dir__)
actual = JSON.parse(File.read(path, encoding:'UTF-8'))
expected = GameRoomDartsRankingMigration.document
assert(actual == expected, 'documented Darts ranking migration differs from its source contract')

legacy = actual.fetch('expected_current_tables')
target = actual.fetch('target_tables')
public_name = GameRoomDartsRankings::Schema::TABLE
personal_name = GameRoomDartsRankings::Schema::PERSONAL_TABLE
assert(legacy.dig(public_name, 'columns', 'records_json') == 'string:4096' &&
  legacy.dig(personal_name, 'columns', 'records_json') == 'string:4096',
  'migration no longer recognizes the deployed version-one Darts tables')
assert(target == GameRoomDartsRankings::Schema::TABLES &&
  target.dig(public_name, 'columns', 'records_json') == 'string:8192' &&
  target.dig(personal_name, 'columns', 'unlocked_level') == 'integer',
  'migration target differs from the runtime Darts declarations')
compatibility = actual.fetch('data_compatibility')
assert(compatibility['rewrite_existing_rows'] == false && compatibility['legacy_records_version'] == 1 &&
  compatibility['current_records_version'] == 2 && compatibility['legacy_unlocked_difficulty'] == 'hard',
  'migration requires an undocumented rewrite or lost version-one compatibility')
assert(compatibility['maximum_record_document_bytes'] <= compatibility['records_json_limit_bytes'],
  'declared Darts ranking document does not fit the migrated column')
assert(actual.fetch('destructive') == false &&
  actual.dig('rollback', 'schema') == 'keep the widened additive schema',
  'migration permits table recreation, data reset or an unsafe schema shrink')

puts 'PASS Darts ranking migration: exact legacy precondition, additive target, no row rewrite and forward-safe rollback'
