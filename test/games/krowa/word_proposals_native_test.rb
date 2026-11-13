require_relative '../../support/game_option_editor_native'
NativeOptionSource.load(File.join(NativeOptionSource::ROOT, 'games/krowa_support/client.rb'))
require_relative '../../support/krowa_word_proposals'
require_relative '../../support/native_tasks'
assert(File.expand_path(Form.instance_method(:wait).source_location.first) == EltenTestHost.file('src/ui/form.rb'),
  'The proposal test must use the native host form lifecycle')

class KrowaProposalDriver < NativeOptionTest::Driver
  attr_reader :root, :service, :delivered, :answer, :screen, :layout, :network

  def initialize(real_tasks: false)
    @raw_keys, @frames, @delivered = [], 0, []
    NativeOptionUI.driver = self
    @program = KrowaTestProgram.new
    @network = KrowaProposalFixture::Client.new
    @service = KrowaProposalFixture.service(program: @program, client: @network)
    # Isolate native controls/input here; the companion service test exercises
    # the actual forum adapter and uncertain writes without live publication.
    unless real_tasks
      service.define_singleton_method(:task) { |&block| block.call(nil) }
      delivered = @delivered
      service.define_singleton_method(:deliver) { |word, **_options| delivered << word; 1 }
    end
    run = KrowaTestGame.new
    run.automatic
    @game = run.game
    replay = run.replay
    @layout = GameRoomLayout::Screen.new(view_spec: game.game_view_spec(replay, 'Alice'),
      history_items: [], user_items: [], users_header: 'Users')
    @root = layout.form
    @root.cancel_button = layout.back_button
    layout.back_button.on(:press) { @root.resume }
    @answer = layout.surface.fields.first
    layout.session_id = run.session['__id']
    layout.begin_bindings
    client = GameRoomGames::KrowaClient.allocate
    client.define_singleton_method(:word_proposals) { @proposal_fixture }
    client.instance_variable_set(:@proposal_fixture, service)
    @screen = GameScreen.allocate
    {game: game, game_client: client, session: run.session, repository: run.repository, layout: layout}.each do |name, value|
      screen.instance_variable_set("@#{name}", value)
    end
    screen.define_singleton_method(:event_presentation_busy?) { false }
    wait = GameScreen::WaitState.new(replay: replay, session: run.session, actor: 'Alice')
    screen.send(:bind_wait_shortcuts, wait, layout, -> { raise 'Proposal moved the game cursor' })
    NativeOptionUI.driver = self
    @fiber = Fiber.new { root.wait }
    @form = @fiber.resume
    press([])
  end

  def press(keys, characters = '')
    outcome = @fiber.resume([keys, characters])
    @form = outcome if @fiber.alive?
    if @fiber.alive?
      outcome = @fiber.resume([[], ''])
      @form = outcome if @fiber.alive?
    end
  end

  def unknown(word, status = :unknown_noun)
    answer.set_text(word)
    action = layout.surface.submission_action.with_source('answer')
    screen.send(:confirm_surface_action, layout.surface, action, session_id: layout.session_id, status: status)
  end

  def close
    @closing = true
    @fiber.resume([[], '']) if @fiber.alive?
    !@fiber.alive?
  end

  def tick(owner)
    unless owner.is_a?(GameRoomUI::Form)
      Thread.pass
      return
    end
    if @closing && owner.equal?(@root) && owner.instance_variable_get(:@wait)
      @closing = false
      owner.resume
    else
      super
    end
  end
end

NativeOptionTest.language = 'en'
driver = KrowaProposalDriver.new
begin
  driver.answer.set_text('zmywarka')
  driver.press([17, 16, 66])
  assert(driver.form.equal?(driver.root) && driver.delivered.empty?, 'Missing rejected word fell back to the current draft')
  driver.press([17, 66])
  assert(!driver.form.equal?(driver.root), 'Ctrl+B did not open the first-use rules')
  assert(driver.form.fields.first.text.include?('Power Games group'), 'Rules omit group membership')
  assert(driver.form.fields.first.text.include?('diminutives'), 'Rules omit prohibited words')
  assert(driver.delivered.empty?, 'First-use notice sent before acceptance')
  driver.press([27])
  assert(driver.form.equal?(driver.root) && driver.answer.text == 'zmywarka', 'Escape changed the draft or failed to return')
  driver.press([17, 66])
  assert(!driver.form.equal?(driver.root), 'Cancelled rules were remembered as accepted')
  driver.press([9])
  driver.press([13])
  assert(driver.form.equal?(driver.root), 'Rules acceptance did not return to the game')
  assert(driver.delivered == ['zmywarka'] && driver.answer.text == 'zmywarka', 'Ctrl+B changed or submitted the game answer')
  assert(NativeOptionUI.spoken.count { |message| message == 'Word proposal posted: zmywarka.' } == 1, 'Submission confirmation was not spoken exactly once')
  assert(driver.root.fields[driver.root.index].equal?(driver.answer), 'Returning from rules changed focus')
  driver.unknown('bankomat')
  assert(driver.answer.text.empty?, 'Rejected answer did not exercise native draft clearing')
  driver.press([17, 66])
  assert(driver.delivered == ['zmywarka'], 'An empty current answer sent the rejected word')
  driver.press([17, 16, 66])
  assert(driver.delivered.last == 'bankomat', 'Ctrl+Shift+B lost the cleared unknown word')
  assert(driver.form.equal?(driver.root), 'Accepted rules reappeared')
  driver.unknown('la', :wrong_length)
  driver.press([17, 16, 66])
  assert(driver.delivered.last == 'bankomat', 'Wrong-length rejection replaced the unknown word')
  driver.answer.set_text('kofta')
  driver.layout.chat.set_text('Private chat text')
  driver.root.index = driver.root.fields.index(driver.layout.chat)
  driver.root.focus
  driver.press([17, 66])
  assert(driver.delivered.last == 'kofta', 'Shortcut sent chat text instead of the answer')
  assert(driver.layout.chat.text == 'Private chat text' && driver.answer.text == 'kofta', 'Proposal altered an unsent draft')
  driver.answer.set_text('kot')
  previous_posts = driver.delivered.dup
  driver.press([17, 66])
  assert(driver.delivered == previous_posts, 'A word already in the shared dictionary was posted')
  assert(driver.screen.instance_variable_get(:@selected_surface_action).nil?, 'Forum proposal entered the move pipeline')
  before = driver.delivered.dup
  driver.press([66])
  assert(driver.delivered == before, 'Plain B posted a proposal')
ensure
  closed = driver.close
end
raise 'Native proposal forms did not close' unless closed
{'pl' => 'Zasady zgłaszania słów', 'cs' => 'Pravidla navrhování slov',
  'es' => 'Normas para proponer palabras', 'ru' => 'Правила отправки слов'}.each do |language, header|
  NativeOptionTest.language = language
  translated = KrowaProposalDriver.new
  begin
    translated.answer.set_text('żurawinka')
    translated.press([17, 66])
    assert(translated.form.fields.first.header == header, "#{language}: rules header was not translated")
    assert(translated.form.fields.first.text.valid_encoding?, "#{language}: rules text is not valid Unicode")
    translated.press([9])
    translated.press([13])
    assert(translated.form.equal?(translated.root) && translated.delivered == ['żurawinka'], "#{language}: rules did not send and return")
    assert(translated.answer.text == 'żurawinka', "#{language}: proposal changed Polish text")
  ensure
    translated_closed = translated.close
  end
  raise "#{language}: test form did not close" unless translated_closed
end
NativeOptionTest.language = 'en'
managed = KrowaProposalDriver.new(real_tasks: true)
begin
  managed.answer.set_text('zmywarka')
  managed.press([17, 66])
  managed.press([9])
  managed.press([13])
  assert(managed.network.posts.map(&:text) == ['zmywarka'], 'Managed native submission did not post the word')
  assert(managed.network.calls.all? { |call| call[4] != Thread.current && call[3][:cancellation_token] }, 'Forum I/O bypassed the managed worker or cancellation token')
  assert(managed.answer.text == 'zmywarka' && managed.form.equal?(managed.root), 'Managed send changed the draft or failed to return')
ensure
  managed_closed = managed.close
end
raise 'Managed test form did not close' unless managed_closed
puts 'PASS native Krowa proposal keys: rules/cancel/accept/return, cleared rejection capture, exact press modifiers, retained answer/chat and focus'
