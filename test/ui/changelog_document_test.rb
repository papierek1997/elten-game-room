require_relative "../support/rules_native_navigation"

entries = GameRoomChangelog.available_entries(EltenGameRoom::GAME_ROOM_BUILD_ID)
%w[pl en cs es ru fallback].each do |language|
  GameRoomTestLocalization.use_language(language)
  text = GameRoomChangelog.markdown(entries, translator: GameRoomLocalization.method(:translate))
  program = Object.new
  visited = false
  Form.driver = lambda do |form|
    visited = true
    assert(form.game_room_program.equal?(program), "#{language}: missing common form lifecycle")
    assert(form.accept_button.nil? && form.cancel_button == form.fields.last, "#{language}: wrong close bindings")
    field = form.fields.first
    assert(field.is_a?(EditBox), "#{language}: changelog is still a list")
    assert(field.flags & EditBox::Flags::ReadOnly != 0 && field.flags & EditBox::Flags::MarkDown != 0,
      "#{language}: changelog lost read-only or Markdown support")
    headings = elements(field, EditBox::Element::Header)
    titles = entries.map do |entry|
      GameRoomChangelog.list_items([entry], translator: GameRoomLocalization.method(:translate)).first
    end
    assert(headings.map { |h| field.text_range(h.from, h.to) } == titles, "#{language}: wrong release headings or Unicode offsets")
    displayed = field.text_range(0, field.text_len - 1)
    entries.each do |entry|
      entry.changes.each do |change|
        assert(displayed.include?(GameRoomLocalization.translate(change)), "#{language}: a release note was lost")
      end
    end
    field.extend(NativeRuleInput)
    field.index = headings.first.from
    field.press(72)
    assert(field.index == headings[1].from, "#{language}: H does not move to the next release")
    field.press(72, reverse: true)
    assert(field.index == headings.first.from, "#{language}: Shift+H does not move back")
    form.cancel_button.trigger(:press)
  end
  GameRoomScreens::Changelog.new(text.b, program: program).wait
  assert(visited, "#{language}: the document was never opened")
end
Form.driver = nil
puts "PASS changelog document: all builds, all interface languages, binary text, native headings and navigation"
