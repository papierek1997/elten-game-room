require_relative '../../support/rules_native_navigation'
require_relative '../../support/authored_rulebooks'

assert(File.expand_path(EditBox.instance_method(:readupdate).source_location.first) ==
  EltenTestHost.file('src/ui/controls/edit_box.rb'), 'Help must use the real host EditBox')

# Native EditBox rendering/navigation with a scripted document-picker driver.
# This does not publish proposals or acknowledge the first-use policy.
%w[pl en cs es ru].each do |language|
  GameRoomTestLocalization.use_language(language)
  book = EltenGameRoom::GAME_REGISTRY.build('krowa').rule_book
  rules, controls = book.documents
  vocabulary = rules.sections.find { |section| section.id == :vocabulary }
  assert(vocabulary.paragraphs.join.include?('https://elten.link/forum/thread/28245'),
    "#{language}: proposal instructions are missing from Adding your own words")
  %w[Ctrl+B Ctrl+Shift+B].each do |key|
    assert(vocabulary.paragraphs.any? { |text| text.downcase.include?(key.downcase) }, "#{language}: missing proposal action #{key}")
    assert(controls.paragraphs.one? { |text| text.start_with?(key + ':') }, "#{language}: missing shortcut row #{key}")
  end
  expected = GameRoomTest::Rulebooks.sections('krowa', language).find { |section| section['id'] == 'vocabulary' }
  assert(vocabulary.paragraphs == expected.fetch('paragraphs').map { |pair| pair.fetch(language) },
    "#{language}: generated proposal policy differs from the authored text")

  visits = 0
  current = nil
  selected = 0
  Form.driver = lambda do |form|
    field = form.fields.first
    if current.nil?
      assert(field.index == selected, "#{language}: return lost the selected help document")
      if visits < 2
        selected = visits
        field.index = selected
        current = book.documents[selected]
        visits += 1
        form.accept_button.trigger(:press)
      else
        form.cancel_button.trigger(:press)
      end
    elsif current.id == :controls
      assert(field.options == controls.paragraphs, "#{language}: shortcuts are not separate native list rows")
      form.cancel_button.trigger(:press)
      current = nil
    else
      check_document(field, current, "Krowa/#{language}/proposals")
      assert(field.text.valid_encoding?, "#{language}: native policy text has invalid encoding")
      form.cancel_button.trigger(:press)
      current = nil
    end
  end
  GameRoomScreens::GameRules.new(book).wait
  assert(visits == 2, "#{language}: rules or shortcuts could not be opened")
end
Form.driver = nil
puts 'PASS Krowa proposal help: five complete editions, native headings/contents jumps, shortcut rows and return selection'
