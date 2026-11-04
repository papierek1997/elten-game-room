# encoding: UTF-8
require 'tmpdir'
require_relative '../../support/game_option_form'
require_relative '../../../lib/mania_pisania/option_fields'

class FilesTree < FakeControl
  class << self; attr_accessor :path, :last; end
  attr_reader :selected, :focus_count, :closed
  def initialize(_label, extensions:, quiet:)
    super()
    @selected = self.class.path
    @focus_count = 0
    self.class.last = self
  end
  def focus; @focus_count += 1; end
  def close_preview; @closed = true; end
end

store = {}
writes = []
app = EltenGameRoom.allocate
app.define_singleton_method(:read_json) { |path, default:| store.fetch(path, default) }
app.define_singleton_method(:write_json) do |path,value|
  store[path] = Marshal.load(Marshal.dump(value))
  writes << path
  true
end
library = GameRoomTyping::TextLibrary.new(app)
max = GameRoomTyping::TextLibrary::MAX_BYTES
boundary = 'a' * (max - 4) + 'ąć'
oversize = boundary + 'a'
assert(boundary.bytesize == max && oversize.length < max, 'UTF-8 boundary fixture is invalid')
id = library.import_text(boundary, title:'At the byte limit')
assert(library.fetch(id)['text'] == boundary, 'Exactly the byte limit must import without truncation')
library.save_progress(id, {'position'=>1,'correct_words'=>1})
before = Marshal.dump(store)

Dir.mktmpdir('mania-import-') do |directory|
  file = File.join(directory,'text.txt')
  File.binwrite(file,boundary)
  assert(library.import_file(file) == id, 'File import and pasted text must share the byte limit')
  File.binwrite(file,oversize)
  [-> { library.import_text(oversize) }, -> { library.import_file(file) }].each do |import|
    begin
      import.call
      raise 'Oversized text was accepted'
    rescue ArgumentError => error
      assert(error.message.include?(max.to_s) && error.message.include?('1000 kB'), 'Size error must explain the import limit')
    end
    assert(Marshal.dump(store) == before, 'Rejected import changed saved texts or progress')
  end

  [true,false].each do |paste_only|
    messages = []
    dialog = GameRoomTyping::TextImportDialog.new(app,library,paste_only:paste_only)
    dialog.define_singleton_method(:alert) { |message| messages << message }
    FilesTree.path = file
    Form.driver = lambda do |form|
      assert(form.fields.length == (paste_only ? 4 : 6), 'Unexpected import fields or remaining limit field')
      assert(form.fields.none? { |field| field.respond_to?(:header) && field.header == 'Import limits' }, 'Read-only limit still appears')
      input = form.fields.find { |field| field.is_a?(EditBox) && field.header == 'Paste text for typing practice' }
      title = form.fields.find { |field| field.is_a?(EditBox) && field.header == 'Title of the pasted text' }
      button = form.fields.find { |field| field.is_a?(Button) && field.label == 'Import pasted text' }
      title.set_text('Retry title')
      input.set_text(oversize)
      button.trigger(:press)
      assert(messages.size == 1 && messages.first.include?('Could not import the text:') && messages.first.include?(max.to_s), 'Paste failure did not report the size limit')
      assert(form.fields[form.index].equal?(input) && form.accept_button.equal?(button), 'Failed paste lost input focus or Enter action')
      assert(input.text == oversize && title.text == 'Retry title', 'Failed paste discarded the draft')
      assert(Marshal.dump(store) == before, 'Failed paste changed the library')
      input.set_text('A corrected text.')
      button.trigger(:press)
    end
    imported = dialog.wait
    assert(library.fetch(imported)['text'] == 'A corrected text.', 'Retry in the same paste form did not import')
    # Restore the expected saved snapshot for the next rejected import.
    before = Marshal.dump(store)
  end

  messages = []
  dialog = GameRoomTyping::TextImportDialog.new(app,library)
  dialog.define_singleton_method(:alert) { |message| messages << message }
  Form.driver = lambda do |form|
    tree = form.fields.first
    form.fields[1].trigger(:press)
    assert(messages.one? && messages.first.include?(max.to_s), 'File failure omitted its size limit')
    assert(form.fields.first.equal?(tree) && tree.selected == file && form.index == 0, 'File failure rebuilt or moved the browser')
    assert(tree.focus_count > 0, 'File failure did not return focus to the file')
    File.binwrite(file,'A corrected file.')
    form.fields[1].trigger(:press)
  end
  imported = dialog.wait
  assert(library.fetch(imported)['text'] == 'A corrected file.' && FilesTree.last.closed, 'File retry or preview cleanup failed')
end

Form.driver = lambda do |form|
  assert(form.fields.map { |f| f.class } == [ListBox,Button,Button,Button], 'Library contains a redundant information field')
  form.cancel_button.trigger(:press)
end
GameRoomTyping::TextLibraryDialog.new(app,library).wait

options = {'variant'=>'free','text'=>'pasted'}
fields = GameRoomTyping::OptionFields.new(app,options)
assert(fields.fields.length == 4, 'Table options still contain the limit control')
fields.fields[1].set_text(oversize)
begin
  fields.prepare(options)
  raise 'Table options accepted oversized text'
rescue ArgumentError => error
  assert(error.message.include?(max.to_s), 'Table-option error omitted the limit')
end
fields.fields[1].set_text('Successful table text.')
prepared = fields.prepare(options)
assert(prepared['text_title'] == 'Pasted text' && prepared['text_characters'] == 22, 'Table text retry lost its metadata')

GameRoomLocalization.boot(host_language:'pl')
begin
  library.import_text(oversize)
rescue ArgumentError => error
  assert(error.message.include?('Maksymaln') && error.message.include?(max.to_s), 'Polish size error is missing')
end
puts 'PASS Typing Mania: UTF-8 boundary, rejected file/paste, preserved drafts/progress, retry, three forms and Polish error.'
