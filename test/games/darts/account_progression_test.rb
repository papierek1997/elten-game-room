require_relative '../../support/ui'
require_relative '../../../games/darts'
require_relative '../../../lib/darts/rankings/screen'

def assert(value, message); raise message unless value; end

module Session
  class << self
    attr_accessor :review_account
    def name; review_account; end
  end
end

class DartsAccountPreferencesProgram
  class << self
    attr_accessor :settings
    def darts_rankings_service; Struct.new(:highest_unlocked_difficulty).new('hard'); end
  end
  self.settings = {'darts'=>{}}
  def game_room_settings; self.class.settings; end
  def update_game_room_settings; yield self.class.settings; end
end

# Load the actual application accessors, not a copied cache implementation.
path = File.expand_path('../../../__app.rb', __dir__)
source = File.read(path, encoding: 'UTF-8')
%w[darts_preferences remember_darts_unlock].each do |name|
  fragment = source[/^  def #{name}(?:\([^\n]*\))?\r?\n.*?^  end\b/m]
  raise "Application method boundary missing: #{name}" unless fragment
  DartsAccountPreferencesProgram.class_eval(fragment, path)
end

game, program = GameRoomGames::Darts.new, DartsAccountPreferencesProgram.new
choices = -> { game.personal_option_editor_definitions(program, {}, creating_table:true)
  .find { |definition| definition.key == 'difficulty' }.choices.map(&:value) }
Session.review_account = 'Alice'
assert(program.remember_darts_unlock('legendary'), 'Alice could not retain a confirmed unlock')
assert(choices.call.last == 'legendary', 'the owner cannot use the local unlock')
Session.review_account = 'Bob'
assert(choices.call == %w[easy normal hard], 'changing account leaked the previous account unlock')
screen = GameRoomDartsRankings::Screen.new(program:program, game:game,
  service:DartsAccountPreferencesProgram.darts_rankings_service)
assert(screen.send(:difficulty_choices).map(&:first) == %w[easy normal hard progressive],
  'the ranking browser leaked the previous account unlock')
assert(!program.remember_darts_unlock('legendary', account:'Alice'),
  'late Alice feedback was retained for Bob')
Session.review_account = 'aLiCe'
assert(choices.call.last == 'legendary', 'returning to the same account lost its retained unlock')
stored = DartsAccountPreferencesProgram.settings.fetch('darts')
assert(stored.fetch('unlocked_account') == 'alice', 'local progression has no canonical account owner')
assert(GameRoomDarts::Preferences.for_account({'unlocked_difficulty'=>'legendary'}, 'Alice')
  .fetch('unlocked_difficulty') == 'hard', 'an unowned legacy cache granted an account unlock')
assert(GameRoomDarts::Preferences.normalize('unlocked_account'=>'x' * 65)['unlocked_account'] == '',
  'an invalid account identity entered the progression cache')
puts 'PASS Darts progression: actual application cache, account switch/return and late feedback isolation'
