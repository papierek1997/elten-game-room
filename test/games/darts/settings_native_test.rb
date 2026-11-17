require_relative '../../support/duck_challenge_native'
require EltenTestHost.file('src/ui/controls/check_box.rb')
require_relative '../../../lib/darts/settings'
CheckBox = EltenAPI::Controls::CheckBox

class DartsNativeSettingsSound
  attr_accessor :volume
  attr_reader :closed
  def play; end
  def pause; end
  def close; @closed = true; end
end

class DartsNativeSettingsProgram
  attr_reader :sounds
  def initialize; @sounds = []; end
  def create_sound_from_asset(*)
    sound = DartsNativeSettingsSound.new
    @sounds << sound
    sound
  end
  def manage(resource); resource; end
  def release(resource); resource; end
end

driver = DuckChallengeNativeDriver.new
driver.define_singleton_method(:tick) do |form|
  snapshot([], [])
  return unless form.is_a?(GameRoomUI::Form) && form.instance_variable_get(:@wait)
  raise 'The native settings form repeated its action' if @settings_done
  @settings_done = true
  publication, private_history, list, preview, mouse_input, withdraw, = form.fields
  assert(list.instance_of?(EltenAPI::Controls::ListBox) && publication.instance_of?(EltenAPI::Controls::CheckBox),
    'Darts settings replaced native controls')
  list.index = 2
  publication.checked = true
  private_history.checked = true
  mouse_input.checked = false
  preview.press
  withdraw.press
  form.accept_button.press
end
program = DartsNativeSettingsProgram.new
withdrawn, publish_prompt = 0, 0
outcome = GameRoomDarts::Settings.new({}, program:program, withdraw:-> { withdrawn += 1; true },
  confirm_withdraw:-> { true }, confirm_publish:-> { publish_prompt += 1; true }, notify:->(_text) {}).wait
assert(outcome.values == {'locator_sound'=>'bright', 'public_rankings'=>true,
  'private_records_in_history'=>true, 'mouse_input'=>false} && outcome.publish_saved,
  'The native save did not preserve sound and publication selections')
assert(withdrawn == 1 && publish_prompt == 1, 'The native settings repeated or lost an account operation')
assert(program.sounds.length == 1 && program.sounds.first.closed, 'Native preview leaked after closing settings')
puts 'PASS native Darts settings: actual controls, saved values, separate account actions and preview cleanup'
