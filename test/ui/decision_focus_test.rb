require_relative '../support/ui'
require_relative '../../lib/game_surfaces'
require_relative '../../lib/game_layout'
require_relative '../support/assertions'
include GameRoomTest::Assertions

def decision_view(key, target: 'answer', index: nil)
  parts = [GameSurfaces::SurfacePart.new(id: 'status', surface: GameSurfaces::QuestionSpec.new(
    id: 'status', prompt: 'Current tile', mode: :information, value: 'Bamboo 5', read_only: true)),
    GameSurfaces::SurfacePart.new(id: 'answer', surface: GameSurfaces::QuestionSpec.new(
      id: 'answer', prompt: 'Respond', mode: :single_choice,
      options: [GameSurfaces::QuestionOption.new(id: 'pass', value: 'pass', label: 'Pass'),
        GameSurfaces::QuestionOption.new(id: 'claim', value: 'claim', label: 'Claim')], submit_on_select: true))]
  GameRoomLayout::ViewSpec.new(surface: GameSurfaces::CompositeSpec.new(parts: parts),
    decision_focus_part: target, decision_focus_key: key, decision_focus_index: index)
end

def refresh_decision(layout, spec, **options)
  layout.update(view_spec: spec, history_items: [], user_items: [], users_header: '', **options)
end

layout = GameRoomLayout::Screen.new(view_spec: decision_view(nil))
refresh_decision(layout, decision_view([1, 10], index: 1))
assert_equal([:game, 1], layout.focus_location)
assert_equal(1, layout.form.fields[layout.form.index].index)
assert(layout.decision_focus_changed?, 'New decision did not request queued focus speech')
layout.focus_game(field_index: 0)
layout.surface.fields_for_parts(['answer']).first.index = 0
refresh_decision(layout, decision_view([1, 10]))
assert_equal(0, layout.surface.fields_for_parts(['answer']).first.index, 'An unchanged decision reset the chosen option')
assert_equal([:game, 0], layout.focus_location, 'Another reply stole the manually chosen field')
assert(!layout.decision_focus_changed?, 'Same decision queued its focus twice')
refresh_decision(layout, decision_view([1, 11]))
assert_equal([:game, 1], layout.focus_location)
[:chat, :history, :users].each do |section|
  layout.form.index = layout.form.fields.index(layout.public_send(section))
  layout.chat.text = 'Unfinished ąż message'
  refresh_decision(layout, decision_view([section, 12]))
  assert_equal([section, 0], layout.focus_location)
  assert(!layout.decision_focus_changed?, 'Room focus must not queue decision speech')
  assert_equal('Unfinished ąż message', layout.chat.text)
end
layout.focus_game(field_index: 0)
refresh_decision(layout, decision_view([2, 12], target: 'missing'))
assert_equal([:game, 0], layout.focus_location)
assert(!layout.decision_focus_changed?, 'A missing part requested focus')
refresh_decision(layout, decision_view([2, 13]), phase: :finished)
assert_equal([:status, 0], layout.focus_location)
assert(!layout.decision_focus_changed?, 'Finished game tried to focus an obsolete decision')
puts 'PASS declarative decision focus: one transition per key, room text preserved, missing/finished targets ignored'

# A one-field surface needs no artificial Composite solely to announce a new
# decision. Named parts still require a matching actual composite part.
flat_surface = GameSurfaces::QuestionSpec.new(id: 'score', prompt: 'Choose a category', mode: :single_choice,
  options: [GameSurfaces::QuestionOption.new(id: 'first', value: 'first', label: 'First')])
flat = ->(key, part=nil) { GameRoomLayout::ViewSpec.new(surface: flat_surface, decision_focus_key: key, decision_focus_part: part) }
plain = GameRoomLayout::Screen.new(view_spec: flat.call(nil))
refresh_decision(plain, flat.call('third roll'))
assert(plain.decision_focus_changed?, 'A single-surface decision cannot announce its prompt')
refresh_decision(plain, flat.call('third roll'))
assert(!plain.decision_focus_changed?, 'An unchanged single-surface decision repeats its prompt')
refresh_decision(plain, flat.call('fourth roll', 'missing'))
assert(!plain.decision_focus_changed?, 'A named part silently falls back to an unrelated single surface')
puts 'PASS single-surface decision focus: one boundary, quiet refresh and no missing-part fallback'
