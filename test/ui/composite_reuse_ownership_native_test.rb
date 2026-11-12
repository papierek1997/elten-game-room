require_relative '../support/duck_challenge_native'

def ownership_hand(side, version)
  cards = %w[A B C].map do |letter|
    id = "#{side}-#{letter}"
    GameSurfaces::Card.new(id: id, value: id, label: "#{id} version #{version}")
  end
  GameSurfaces::CardTableSpec.new(zones: [GameSurfaces::CardZoneSpec.new(
    id: 'hand', header: "#{side} version #{version}", cards: cards,
    hand_order: cards.map(&:id), hand_epoch: "#{side}-deal")])
end

def ownership_parts(values)
  GameSurfaces::CompositeSpec.new(parts: values.map do |id, spec|
    GameSurfaces::SurfacePart.new(id: id, surface: spec)
  end)
end

[:flat, :nested].each do |shape|
  make = lambda do |version|
    pair = %w[left right].map { |side| [side, ownership_hand(side, version)] }
    if shape == :nested
      ownership_parts([['pair', ownership_parts(pair)], ['extra', ownership_hand('extra', version)]])
    else
      ownership_parts(pair)
    end
  end
  driver = DuckChallengeNativeDriver.new
  layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new(surface: make.call(1)))
  original = layout.surface.fields.dup
  original.each { |field| field.index = 1 }
  previous = layout.surface.reuse_candidates.freeze
  original_candidates = previous.dup
  layout.update(view_spec: GameRoomLayout::ViewSpec.new(surface: make.call(2)),
    history_items: [], user_items: [], users_header: '')
  current = layout.surface.fields
  assert(current.map(&:object_id).uniq.size == original.size, "#{shape}: sibling parts reused one native control twice")
  assert(current.zip(original).all? { |now, before| now.equal?(before) }, "#{shape}: a distinct reusable field was unnecessarily replaced")
  assert(current.all? { |field| field.index == 1 }, "#{shape}: sibling refresh lost a hand cursor")
  expected_sides = shape == :flat ? %w[left right] : %w[left right extra]
  assert(current.map(&:header) == expected_sides.map { |side| "#{side} version 2" }, "#{shape}: one sibling replaced another's header/cards")
  actions = []
  layout.surface.on_action { |action| actions << action }
  current.each do |field|
    layout.form.index = layout.form.fields.index(field)
    layout.form.focus
    driver.frame(layout.form, driver.tap(0x0d))
    driver.frame(layout.form, [])
  end
  assert(actions.map { |action| action['card'] } == expected_sides.map { |side| "#{side}-B" }, "#{shape}: updated native fields emitted another sibling's cards")
  expected_sources = shape == :flat ? %w[left right] : %w[pair pair extra]
  assert(actions.map(&:source) == expected_sources && actions.all? { |action| action.source.instance_of?(String) }, 'Flat public Action.source contract changed')

  # The internal candidate pool is consumed, not the caller's input array.
  rebuilt = GameSurfaces.reconcile(make.call(3), previous: previous)
  assert(previous == original_candidates && previous.frozen?, 'Reconciliation mutated caller-owned candidates')
  assert(rebuilt.fields.map(&:object_id).uniq.size == original.size, 'Explicit candidate-array refresh aliased native fields')
end

[%w[right left], %w[right], %w[new left right]].each do |names|
  make = ->(sides, version) { ownership_parts(sides.map { |side| [side, ownership_hand(side, version)] }) }
  driver = DuckChallengeNativeDriver.new
  layout = GameRoomLayout::Screen.new(view_spec: GameRoomLayout::ViewSpec.new(surface: make.call(%w[left right], 1)))
  old_fields = %w[left right].zip(layout.surface.fields).to_h
  old_fields.fetch('left').index = 2
  old_fields.fetch('right').index = 1
  remembered = layout.surface.state
  next_spec = make.call(names, 2)
  expected = GameSurfaces.build(next_spec, state: remembered)
  layout.update(view_spec: GameRoomLayout::ViewSpec.new(surface: next_spec),
    history_items: [], user_items: [], users_header: '')
  fields = layout.surface.fields
  assert(fields.map(&:index) == expected.fields.map(&:index), "#{names}: refresh lost part-keyed cursors compared with a fresh build")
  names.zip(fields).each do |name, field|
    if old_fields.key?(name)
      assert(field.equal?(old_fields.fetch(name)), "#{name}: a different logical part stole the native control")
    else
      assert(old_fields.values.none? { |old| old.equal?(field) }, 'An inserted part stole another part control')
    end
  end
  actions = []
  layout.surface.on_action { |action| actions << action }
  fields.each do |field|
    layout.form.index = layout.form.fields.index(field)
    layout.form.focus
    driver.frame(layout.form, driver.tap(0x0d))
    driver.frame(layout.form, [])
  end
  expected_cards = names.zip(expected.fields).map { |name, field| "#{name}-#{%w[A B C].fetch(field.index)}" }
  assert(actions.map { |action| action['card'] } == expected_cards, 'Reordered native input selected a card from a reset or foreign cursor')
  assert(actions.map(&:source) == names, 'Reordered input lost its flat logical part source')
end

$activecontrols = []
puts 'PASS composite reuse: once-only ownership, stable part IDs through reorder/removal/insertion, independent cursors/cards, nested pools and flat sources'
