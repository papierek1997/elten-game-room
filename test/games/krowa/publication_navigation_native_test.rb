require_relative '../../support/game_option_editor_native'
NativeOptionSource.load(File.join(NativeOptionSource::ROOT, 'games/krowa_support/client.rb'))

def assert(condition, message)
  NativeOptionTest.assert(condition, message)
end

# Reuse the shared native keyboard/frame driver, not a second keyboard model.
class KrowaPublicationDriver < NativeOptionTest::Driver
  def initialize(gallery: false)
    @game = EltenGameRoom::GAME_REGISTRY.build('krowa')
    @program = NativeOptionTest::Program.new
    @raw_keys, @frames = [], 0
    client = GameRoomGames::KrowaClient.allocate
    client.instance_variable_set(:@program, @program)
    client.instance_variable_set(:@game, @game)
    client.instance_variable_set(:@profile, Struct.new(:data).new({'gallery' => {
      'kot' => {'attempts' => 7, 'at' => 1, 'words' => ['kot']},
      'żółć' => {'attempts' => 2, 'at' => 2}
    }}))
    NativeOptionUI.driver = self
    @fiber = Fiber.new do
      gallery ? client.send(:gallery_dialog) : client.send(:publication_choice, 'Publish result?')
    end
    @form = @fiber.resume
    raise 'Krowa did not enter the native form' unless @fiber.alive? && @form.instance_of?(GameRoomUI::Form)
    @fields = @form.fields.dup
    pristine
  end
end

NativeOptionTest.native_method(ListBox, :update, 'src/ui/controls/list_box.rb')
NativeOptionTest.native_method(Form, :wait, 'src/ui/form.rb')
choices = [:with_attempts, :without_attempts, nil]
labels = {
  'en' => ['Publish', 'Publish without attempt list', 'Do not publish'],
  'pl' => ['Opublikuj', 'Opublikuj bez listy prób', 'Nie publikuj']
}

%w[en pl cs es ru].each do |language|
  NativeOptionTest.language = language
  [0, 1, 2, :escape].each do |choice|
    driver = KrowaPublicationDriver.new
    list = driver.form.fields.first
    assert(driver.form.index == 0 && list.index == 0, "#{language}: initial focus must be Publish")
    assert(list.options == labels[language], "#{language}: publication labels changed") if labels.key?(language)
    if choice == :escape
      driver.press([39]); driver.press([27])
      assert(driver.finished.nil?, "#{language}: Escape did not cancel publication")
    else
      choice.times { driver.press([39]) }
      assert(list.index == choice, "#{language}: Right did not reach choice #{choice}")
      if choice > 0
        driver.press([37])
        assert(list.index == choice - 1, "#{language}: Left did not move back")
        driver.press([39])
      end
      driver.press([13])
      assert(driver.finished == choices[choice], "#{language}: Enter chose the wrong publication mode")
    end
    driver.pristine
  end

  driver = KrowaPublicationDriver.new(gallery: true)
  gallery, attempts = driver.form.fields.first(2)
  assert(gallery.options.first.start_with?('żółć:'), "#{language}: newest gallery entry moved")
  assert(gallery.options.last.start_with?('kot: 7'), "#{language}: gallery lost the attempt count")
  assert(gallery.options.map { |text| text.scan(/\d+/) } == [['2'], ['7']], "#{language}: gallery still includes word lengths")
  driver.press([40])
  assert(gallery.index == 1, "#{language}: gallery Down navigation changed")
  driver.press([9])
  assert(driver.form.fields[driver.form.index].equal?(attempts) && attempts.options == ['kot. 3'],
    "#{language}: gallery attempt list is no longer under Tab")
  driver.press([27])
  driver.finished
  driver.pristine
end

puts 'PASS Krowa native publication: default Publish, Left/Right, Enter/Escape and compact gallery with Tab histories in five languages'
