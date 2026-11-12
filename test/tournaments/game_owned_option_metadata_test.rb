require 'digest'
require_relative '../../games/catalog'
require_relative '../../lib/tournaments/publication'
require_relative '../support/assertions'
include GameRoomTest::Assertions
GameRoomLocalization.boot(settings: {'interface_language' => 'en', 'known_languages' => ['en']})
T = GameRoomTournaments
registry = GameRoomGames::CATALOG
validate = lambda do |id, options, source = registry|
  game = source.build(id)
  count = game.tournament_capabilities(options: options).fetch(:player_counts).find { |value| value >= 2 }
  raise 'The fixture has no playable tournament composition' unless count
  settings = {'players_per_match' => count, 'game_options' => options}
  before = Marshal.dump(options)
  T::Publication.send(:validate_game, id, settings, source)
  assert_equal(before, Marshal.dump(options), 'Metadata validation mutated caller-owned input')
  settings.fetch('game_options')
end

%w[tic_tac_toe tysiac categories mania_pisania blackjack blackjack_dice farkle].each do |id|
  game = registry.build(id)
  created = game.new_game_options(game.table_creation_options({}))
  assert_equal(created, validate.call(id, created))
  old = game.default_options
  assert_equal(old, validate.call(id, old), 'An older explicit publication was upgraded')
  assert_equal(:invalid_options, assert_raises(T::Publication::Invalid) do
    validate.call(id, created.merge('foreign_probe' => 1))
  end.code)
  numeric = game.effective_option_definitions(created).find { |definition| definition.kind.to_s == 'integer' }
  next unless numeric
  assert_equal(:invalid_options, assert_raises(T::Publication::Invalid) do
    validate.call(id, created.merge(numeric.key.to_s => created.fetch(numeric.key.to_s, numeric.default).to_s))
  end.code)
end
[0, true, '1'].each do |value|
  assert_equal(:invalid_options, assert_raises(T::Publication::Invalid) do
    validate.call('tic_tac_toe', registry.build('tic_tac_toe').default_options.merge('random_start' => value))
  end.code)
end
typing = registry.build('mania_pisania')
descriptor = GameRoomTyping::TextSelection.describe('local:' + Digest::SHA256.hexdigest('Local text'),
  {'title' => 'Local metadata test', 'text' => 'Local text'})
local = typing.table_creation_options({}).merge('text' => 'pasted').merge(descriptor)
assert_equal(local, validate.call(typing.id, local))
assert_raises(T::Publication::Invalid) {validate.call(typing.id, local.merge('text_sha256' => 'bad'))}

# Never discover allowed metadata by passing its untrusted keys back to a
# permissive normalizer. Only previously validated declared controls may seed
# game-owned prototype creation, including conditional current-game metadata.
class MetadataPrototypeGame < GameRoomGames::Base
  attr_reader :prototype_inputs
  def initialize; @prototype_inputs = []; end
  def id; 'metadata_probe'; end
  def default_options; {'counter' => 3}; end
  def option_definitions
    [GameRoomGames::OptionDefinition.new(key: 'counter', label: 'Counter', kind: :integer, default: 3)]
  end
  def normalize_options(values); default_options.merge(values); end
  def table_creation_options(values = {})
    @prototype_inputs << values.dup
    super
  end
  def new_game_options(values)
    @prototype_inputs << values.dup
    normalize_options(values).merge('engine_version' => 2)
  end
end
game = MetadataPrototypeGame.new
source = Struct.new(:game) {def build(id); game if game.id == id; end}.new(game)
valid = {'counter' => 3, 'engine_version' => 2}
assert_equal(valid, validate.call(game.id, valid, source))
assert(game.prototype_inputs.all? { |values| !values.key?('foreign_probe') })
game.prototype_inputs.clear
assert_raises(T::Publication::Invalid) {validate.call(game.id, valid.merge('foreign_probe' => 1), source)}
assert(game.prototype_inputs.all? { |values| !values.key?('foreign_probe') }, 'Untrusted metadata seeded its own schema')
game.prototype_inputs.clear
assert_raises(T::Publication::Invalid) {validate.call(game.id, {'counter' => '3', 'engine_version' => 2}, source)}
assert_equal([], game.prototype_inputs, 'Prototype generation preceded strict declared-control validation')
puts 'PASS game-owned tournament metadata: current/old canonical options, strict controls, private text descriptor, no foreign-key self-authorization'
