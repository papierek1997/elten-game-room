require "json"
require_relative "support/ui"
require_relative "support/elten_array_shuffle"

# ELTEN evaluates decompressed sources as binary strings, unlike Ruby's
# ordinary require. Reproduce that boundary without installing or running UI.
module BinaryRulesLoad
  ROOT = File.expand_path("..", __dir__)
  @loaded = {}

  def self.read(path)
    relative = path.delete_prefix(ROOT + "/")
    # Test/support code belongs to the checkout, not the player installer.
    # Production code/data MUST still come from the package: no disk fallback
    # for a missing runtime record, which would hide an incomplete release.
    development_source = relative.start_with?("test/", "tools/")
    @entries && !development_source ? @entries.fetch(relative.downcase).b : File.binread(path)
  end

  def self.package=(path)
    require "zip"
    require "zstd-ruby"
    require "stringio"
    require_relative "../../work/elten-3.0.1-app-dev/src/EAPI/programsigning"
    @entries = {}
    Zip::File.open(path) do |zip|
      manifest = JSON.parse(zip.read("__manifest.json")).fetch("payload")
      data = Programs::ProgramSigning.decode_package(zip.read(manifest.fetch("entry"))).fetch(:code_file)
      io = StringIO.new(data)
      magic = "Elten3AppPackage"
      raise "Invalid code header" unless io.read(magic.bytesize) == magic
      u32 = -> { io.read(4).unpack1("V") }
      @metadata = JSON.parse(Zstd.decompress(io.read(u32.call)))
      until io.eof?
        type = io.read(1).unpack1("C")
        name = type == 3 ? "locale/#{io.read(2)}.mo" : io.read(io.read(2).unpack1("v"))
        payload = io.read(u32.call)
        @entries[name.downcase] = type == 2 ? payload : Zstd.decompress(payload).b
      end
    end
  end

  def self.load(path)
    path = File.expand_path(path)
    return false if @loaded[path]
    @loaded[path] = true
    # Do not force UTF-8 here: that was precisely what hid the build-209 bug.
    TOPLEVEL_BINDING.eval(read(path), path, 1)
    true
  end

  def self.catalog
    bytes = read(File.join(ROOT, "locale/PL.mo"))
    count, originals, translations = bytes.byteslice(8, 12).unpack("V3")
    count.times.to_h do |index|
      length, offset = bytes.byteslice(originals + index * 8, 8).unpack("V2")
      source = bytes.byteslice(offset, length).force_encoding("UTF-8")
      length, offset = bytes.byteslice(translations + index * 8, 8).unpack("V2")
      [source, bytes.byteslice(offset, length).force_encoding("UTF-8")]
    end
  end

  module Requires
    def require_relative(name)
      origin = caller_locations(1, 1).first.path
      if origin.start_with?(BinaryRulesLoad::ROOT + "/")
        path = File.expand_path(name, File.dirname(origin))
        path += ".rb" unless path.end_with?(".rb")
        return BinaryRulesLoad.load(path) if path.start_with?(BinaryRulesLoad::ROOT + "/")
      end
      require File.expand_path(name, File.dirname(origin))
    end
    private :require_relative
  end
end

BinaryRulesLoad.package = ARGV.first if ARGV.first
RULES_CATALOG = BinaryRulesLoad.catalog
def _(text)
  utf8 = text.to_s.dup.force_encoding("UTF-8")
  RULES_CATALOG.fetch(utf8, utf8)
end

def n_(singular, plural, count)
  _(count.to_i == 1 ? singular : plural)
end

class Program
  def self.server_app(**_options); end
end

Kernel.prepend(BinaryRulesLoad::Requires)
BinaryRulesLoad.load(File.join(BinaryRulesLoad::ROOT, "__app.rb"))
registry = EltenGameRoom::GAME_REGISTRY
GameRoomBotNames::NAMES.each do |token, name|
  raise "Invalid bot name encoding" unless name.encoding == Encoding::UTF_8 && name.valid_encoding?
  participant = GameRoomParticipants.bot_id(12, 1, name_token: token)
  raise "Binary named computer lookup failed" unless GameRoomParticipants.bot?(participant) && GameRoomParticipants.display_name(participant) == name
  activity = TableActivityRepository.new(server_tables: {})
  { "bot_added" => "Dodano", "bot_removed" => "Usunięto" }.each do |kind, verb|
    entry = TableActivityRepository::Entry.new(kind: kind, subject: participant, actor: "Alice", owner: "Alice", game: "uno")
    text = activity.text_for(entry, game_name: ->(_id) { "UNO" })
    raise "Binary bot announcement lost name or Polish translation" unless text == "#{verb} #{name}.".force_encoding("UTF-8") && text.valid_encoding?
    global = activity.text_for(entry, game_name: ->(_id) { "UNO" }, global: true)
    raise "Binary lobby bot announcement lost name" unless global.valid_encoding? && global.include?(name) && !global.include?("komputer")
  end
end
raise "Lost games during binary loading" unless registry.ids.length == 28
raise "Quiz Party was not loaded from binary sources" unless registry.ids.include?("quiz")
%w[quiz.general.en quiz.wikidata.pl quiz.witcher.pl quiz.witcher.g.pl quiz.witcher.b.pl].each do |id|
  pack = GameRoomContent.registry.pack(id)
  raise "Question data loaded eagerly" if pack.verified?
end
%w[scrabble.words.en.v1 scrabble.words.pl-pl.v1 taboo.general.en.v1 taboo.general.pl-pl.v1].each do |id|
  raise "New language data loaded eagerly: #{id}" if GameRoomContent.registry.pack(id).verified?
end
registry.ids.each do |id|
  game = registry.build(id)
  documents = game.rule_book(options: game.default_options).documents
  raise "Wrong rules documents: #{id}" unless documents.length == 3
  documents.each do |document|
    raise "Wrong title encoding: #{id}" unless document.title.encoding == Encoding::UTF_8 && document.title.valid_encoding?
    raise "Wrong text encoding: #{id}" unless document.text.encoding == Encoding::UTF_8 && document.text.valid_encoding?
  end
end
GameRoomContent::MonopolyBoards.choices.each do |choice|
  board = GameRoomContent::MonopolyBoards.build(choice.value)
  raise "Binary currency in #{choice.value}" unless board[:currency].encoding == Encoding::UTF_8
  raise "Binary symbol in #{choice.value}" unless board[:currency_symbol].encoding == Encoding::UTF_8
  board[:squares].each do |square|
    raise "Binary field name in #{choice.value}" unless square[:name].encoding == Encoding::UTF_8
  end
end
%w[quiz.general.en quiz.wikidata.pl quiz.witcher.pl quiz.witcher.g.pl quiz.witcher.b.pl].each do |id|
  pack = GameRoomContent.registry.pack(id)
  questions = pack.data.fetch("questions")
  raise "Binary lazy Quiz data failed to verify" unless pack.verified? && pack.entry_count == questions.length
  raise "Binary Quiz prompt" unless questions.all? { |q| q["prompt"].encoding == Encoding::UTF_8 && q["prompt"].valid_encoding? }
end
metadata = BinaryRulesLoad.instance_variable_get(:@metadata) || JSON.parse(File.read(File.join(BinaryRulesLoad::ROOT, "manifest.json")))
raise "Runtime build differs from package manifest" unless EltenGameRoom::GAME_ROOM_BUILD_ID.to_s == metadata.fetch("build_id").to_s
raise "Runtime version differs from package manifest" unless EltenGameRoom::GAME_ROOM_VERSION == metadata.fetch("version")
raise "Wrong target ELTEN runtime" unless metadata.fetch('EltenAPIVersion') == '3.0.3'
current_changelog = GameRoomChangelog::ENTRIES.find { |entry| entry.build == EltenGameRoom::GAME_ROOM_BUILD_ID }
raise "Binary changelog version differs" unless current_changelog && current_changelog.version == EltenGameRoom::GAME_ROOM_VERSION
current_changelog.changes.each do |change|
  translation = RULES_CATALOG[change.dup.force_encoding("UTF-8")]
  raise "Untranslated binary changelog" unless translation && !translation.empty? && translation.valid_encoding?
end
raise "Missing binary invitation receipt handler" unless defined?(GameRoomInvitationReceipts::HistoryWriter) &&
  EltenGameRoom.respond_to?(:notification_received)
activity_repo = TableActivityRepository.new(server_tables: {})
{"invited" => "Alice zaprosił gracza Bob.", "invitation_rejected" => "Bob odrzucił zaproszenie gracza Alice."}.each do |kind, expected|
  entry = TableActivityRepository::Entry.new(kind: kind, actor: "Alice", subject: "Bob", owner: "Alice", game: "makao")
  text = activity_repo.text_for(entry, game_name: ->(_id) { "Makao" })
  raise "Wrong binary invitation history translation" unless text == expected && text.encoding == Encoding::UTF_8
end

# Smoke-check the release's new hooks from decoded binary sources, not a
# second ordinary require of the checkout. No network or host UI is used.
raise "Missing binary save engine" unless defined?(SavedGames) && SavedGames::FORMAT == 1
raise "Missing binary saved games menu" unless EltenGameRoom::MAIN_OPTIONS.include?(_("Saved games"))
raise "Wrong number of saveable games" unless registry.ids.count { |id| registry.build(id).supports_saved_games? } == 24
%w[reversi checkers chess].each do |id|
  game = registry.build(id)
  session = { "__players" => %w[Alice Bob], "options" => JSON.generate(game.default_options) }
  replay = game.replay(session, [], SavedGames::ReplayRepository.new)
  raise "Missing binary material counter: #{id}" unless game.remaining_piece_counts(replay).length == 2
  raise "Invalid binary settings summary: #{id}" unless game.table_options_announcement(game.default_options).valid_encoding?
end
monopoly = registry.build("monopoly")
state = monopoly.send(:initial_state, %w[Alice Bob], monopoly.default_options)
state.update(phase: :property_decision, current_player: "Bob")
state[:positions]["Bob"] = 1
state[:cash]["Bob"] = state[:board][1][:price] - 1
purchase = GameRoomGames::Replay.new(players: %w[Alice Bob], current_player: "Bob", state: state)
raise "Binary purchase refusal misses non-owner" unless monopoly.automatic_action_allowed?(purchase, "Bob", table_owner: "Alice")
raise "Binary purchase requires Enter" unless monopoly.automatic_action(purchase, "Bob")["action"] == "decline"

# Check the invitation fix from the decoded package, including the application
# entry point, not just an ordinary require of the checkout's helper class.
invitation_gateway = Object.new
invitation_gateway.define_singleton_method(:list) { |*_arguments, **_keywords| [] }
collector = InvitationNotifications.new(client: :binary_client, app_uuid: "binary-test", gateway: invitation_gateway)
opened_notice = Struct.new(:id, :app_uuid, :revoked, :type, :metadata).new(
  42, "binary-test", true, "game_room.invitation", {
    "invitation_id" => 7, "table_id" => 12, "live_session_id" => "binary-session",
    "sender" => "Alice", "expires_at" => Time.now.to_i + 300
  })
raise "Binary invitations revived read notices" unless collector.pending(recipient: "Bob").empty?
invitation_app = EltenGameRoom.allocate
invitation_app.instance_variable_set(:@invitation_notifications, collector)
binary_transport = Object.new
binary_transport.define_singleton_method(:start) { true }
invitation_app.instance_variable_set(:@transport, binary_transport)
invitation_app.define_singleton_method(:initialize_services) {}
invitation_app.define_singleton_method(:check_server_table_access) {}
invitation_app.define_singleton_method(:run_network_task) { |*_args, **_kwargs, &operation| operation.call }
invitation_app.define_singleton_method(:load_pending_invitations) do
  collector.pending(recipient: "Bob").map { |row| { invitation: Struct.new(:id).new(row["__id"]) } }
end
invitation_app.define_singleton_method(:select_notification_invitation_action) { :accept }
invitation_app.define_singleton_method(:accept_pending_invitation) do |pending, notification_id:|
  raise "Binary acceptance lost clicked invite" unless pending.id == 7 && notification_id == 42 && collector.pending(recipient: "Bob").length == 1
  { "__id" => 12 }
end
opened_table = nil
invitation_app.define_singleton_method(:run_program_interface) do |row|
  raise "Binary invitation context leaked" unless collector.pending(recipient: "Bob").empty?
  opened_table = row
end
invitation_app.define_singleton_method(:alert) { |message| raise "Binary invitation rejected: #{message}" }
invitation_app.notification_action(:open_invitation, opened_notice)
raise "Binary invitation did not open" unless opened_table && opened_table["__id"] == 12

# Real server session IDs are opaque URL-safe strings, not UUIDs. Exercise
# both new-table presentation and the widget's initial label from this package.
module Session
  def self.name; "Viewer"; end
end
binary_notice_now = 1_789_637_771
binary_notice_uuid = "468f59c5-c9d7-47cd-80f1-1a6fbfd1aa80"
binary_receiver = GameRoomTableWatch::Receiver.new(user: "Viewer", games: ["ninety_nine"],
  uuid: binary_notice_uuid, clock: -> { binary_notice_now })
binary_receiver.games = ["ninety_nine"]
binary_notice = Struct.new(:id, :app_uuid, :type, :sender, :metadata).new(73,
  binary_notice_uuid, GameRoomTableWatch::TYPE, "Łucja", {
    "format" => 1, "game" => "ninety_nine", "table_id" => 91,
    "live_session_id" => "cP44FMhoJwxaQ80Rm02_JY0K9QxAsveo",
    "created_at" => binary_notice_now, "expires_at" => binary_notice_now + 300
  })
def binary_notice.presentation(**options); options; end
EltenGameRoom.instance_variable_set(:@table_watch_receiver, binary_receiver)
EltenGameRoom.define_singleton_method(:normalized_settings) { { "invitation_sounds" => false } }
raise "Binary receiver rejected server ID" unless binary_receiver.visible?(binary_notice)
binary_presentation = EltenGameRoom.map_notification(binary_notice)
raise "Binary notice lost translated text" unless binary_presentation[:title] == "Łucja, 99" && binary_presentation[:body] == "Nowy stół"
raise "Binary notice lost action" unless binary_presentation[:action] == :open_new_table
binary_widget_worker = Object.new
binary_widget_worker.define_singleton_method(:closed?) { false }
binary_widget = GameRoomWidget::TableList.new(loader: -> { [] }, opener: ->(_) {},
  labeler: ->(_) { "" }, id_for: ->(_) { 0 }, worker: binary_widget_worker)
raise "Binary widget falsely reports no tables before loading" unless binary_widget.empty_label == "Wczytywanie stołów Game Roomu"
raise "Missing widget failure translation" unless _("Game Room tables could not be loaded. Press R to retry.") == "Nie udało się wczytać stołów Game Roomu. Naciśnij R, aby spróbować ponownie."

# Exercise translated UI strings through the same binary-source boundary.
# No host window is opened: only the modal list construction is captured.
help_dialog = nil
Form.class_eval do
  alias_method :binary_help_original_wait, :wait
  define_method(:wait) { help_dialog = self }
end
parent_field = ListBox.new(["karta"], header: "Ręka", index: 0)
parent = GameRoomUI::Form.new([parent_field], quiet: true)
parent.show_game_room_help
raise "Binary F1 is not a translated list" unless help_dialog.fields.first.header == "Skróty klawiszowe"
raise "Binary F1 is not read-only text" unless help_dialog.fields.first.is_a?(EditBox) && (help_dialog.fields.first.flags & EditBox::Flags::ReadOnly) != 0
raise "Binary F1 volume tips are untranslated" unless help_dialog.fields.first.text.split("\n").any? { |tip| tip.start_with?("F2 zmniejsza") }
help_dialog.fields.first.text.split("\n").each do |tip|
  raise "Binary help encoding" unless tip.encoding == Encoding::UTF_8 && tip.valid_encoding?
end
Form.class_eval do
  alias_method :wait, :binary_help_original_wait
  remove_method :binary_help_original_wait
end
scrabble = registry.build('scrabble')
{ 'pl-PL' => 'żółw', 'en' => 'qi' }.each do |language, sample|
  options = scrabble.normalize_options(GameRoomContent::LANGUAGE_OPTION_KEY => language)
  state = scrabble.initial_state(%w[Alice Bob], options)
  raise "Binary Scrabble dictionary: #{language}" unless scrabble.dictionary(state).include?(sample)
  tiles = scrabble.tiles(state)
  raise 'Binary Scrabble distribution' unless tiles.length == 100 && tiles.all? { |tile| tile[:letter].encoding == Encoding::UTF_8 }
  tile_ids = sample.chars.map { |letter| tiles.index { |tile| tile[:letter] == letter } }
  state.merge!(phase: :playing, current_player: 'Alice', turn: 1, revision: 1, racks: { 'Alice' => tile_ids, 'Bob' => [] })
  replay = GameRoomGames::Replay.new(players: state[:players], current_player: 'Alice', state: state, history: [])
  surface = GameSurfaces.build(scrabble.surface_spec(replay, 'Alice'))
  surface.fields.first.set_logical_position(7,7)
  tile_ids.each_with_index do |tile, index|
    surface.fields.first.set_logical_position(7 + index, 7)
    available = surface.state['order'] - surface.state['draft'].map(&:first)
    choice = available.index(tile)
    surface.define_singleton_method(:choose) { |_prompt, _labels, multiple: false| choice }
    surface.fields.first.trigger(:select)
  end
  raise 'Binary word draft lost letters' unless surface.state['draft'].length == sample.length
  placements = surface.handle_command('word_submit')['placements']
  raise 'Binary word is not a legal placement' unless scrabble.preview(state, placements).error.nil?
  surface.handle_command('word_cancel')
  2.times { surface.handle_command('word_sort') }
  shortcuts = scrabble.game_shortcuts(replay, 'Alice')
  raise 'Binary Backspace binding' unless shortcuts.any? { |key| key.key == 'backspace' && key.action_name == 'word_remove' }
  raise 'Binary obsolete modes' if shortcuts.any? { |key| %w[h v n].include?(key.key) }
end
taboo = registry.build('taboo')
%w[pl-PL en].each do |language|
  options = taboo.normalize_options(GameRoomContent::LANGUAGE_OPTION_KEY => language)
  pack = taboo.selected_content_pack(options)
  cards = pack.data
  raise 'Binary Taboo card count' unless cards.length == 500 && pack.verified?
  cards.each do |card|
    raise 'Binary Taboo forbidden words' unless card['forbidden'].length == 5
    raise 'Binary Taboo UTF-8' unless ([card['word']] + card['forbidden']).all? { |text| text.encoding == Encoding::UTF_8 && text.valid_encoding? }
  end
end
# A rulebook alone does not exercise table headers, physical tile names or
# move descriptions. Run the translated views before and after real events,
# all through the ASCII-8BIT source boundary used by the real installer.
binary_random = Object.new
generator = Random.new(227)
binary_random.define_singleton_method(:roll) do |count:, sides:|
  Struct.new(:values).new(Array.new(count) { generator.rand(sides) + 1 })
end
%w[rummy domino mexican_train scrabble taboo biblios].each do |id|
  game = registry.build(id)
  players = id == 'taboo' ? %w[Łucja Bob Carol Dave] : %w[Łucja Bob]
  session = { '__players' => players, 'options' => JSON.generate(game.default_options) }
  repository = SavedGames::ReplayRepository.new
  events = []
  replay = game.replay(session, events, repository)
  surfaces = {}
  now = 1_800_000_000
  9.times do |step|
    (players + ['Observer']).each do |viewer|
      spec = game.game_view_spec(replay, viewer)
      surface = surfaces[viewer]
      surfaces[viewer] = surface ? surface.update_spec(spec.surface) : GameSurfaces.build(spec.surface)
      game.game_shortcuts(replay, viewer)
      events.last(1).each do |event|
        Array(game.describe_event_for_display(event, repository, replay, viewer)).each do |message|
          raise "Invalid binary move text: #{id}" unless message.valid_encoding?
          'Ruch: ' + message + ' — koniec.'
        end
      end
    end
    break if step == 8 || replay.finished?
    context = GameRoomGames::ActionContext.new(now: now, random_source: binary_random)
    actor = players.first
    action = game.automatic_action(replay, actor, context: context)
    unless action
      actor = replay.current_player
      action = case id
      when 'rummy'
        replay.state[:drawn] ? { 'action' => 'discard', 'card' => game.hand(replay.state, actor).last } : { 'action' => 'draw' }
      when 'scrabble' then { 'action' => 'pass' }
      when 'taboo'
        case replay.state[:phase]
        when :ready then { 'action' => 'start', 'token' => game.token(replay.state) }
        when :describing then { 'action' => 'correct', 'token' => game.token(replay.state) }
        when :review
          actor = players.first
          { 'action' => 'approve', 'token' => game.token(replay.state) }
        end
      else game.legal_actions(replay, actor, context: context).first
      end
    end
    raise "No binary smoke action: #{id}/#{step}" unless action
    status, plan = game.action_for(action, replay, actor, context: context)
    raise "Binary action rejected: #{id}/#{action}/#{status}" unless status == :ok
    plan.events.each do |command|
      events << { 'id' => events.length + 1, 'actor' => actor, 'action' => command.action, 'value' => command.value }
    end
    replay = game.replay(session, events, repository)
    raise "Binary replay rejected events: #{id}" unless replay.accepted_events.length == events.length
    now += id == 'taboo' && step == 4 ? 100 : 4
  end
end
puts "Binary program loading, invitations, opaque-ID table notices, widget loading, #{registry.ids.length} rule books, six original 2.0 screen/move simulations, 19 Monopoly boards, two Scrabble dictionaries/drafts and 1000 Taboo cards passed"
