require 'tmpdir'
require_relative '../../support/game_option_form'
require_relative '../../../lib/mania_pisania/client'

class FilesTree < FakeControl
  class << self; attr_accessor :chosen, :last; end
  attr_reader :extensions, :path, :closed
  def initialize(label, path:, extensions:, quiet:)
    super()
    @extensions, @path = extensions, path
    self.class.last=self
  end
  def selected; self.class.chosen; end
  def focus; end
  def close_preview; @closed=true; end
end
GameRoomLocalization.boot(host_language:'en')
client=GameRoomTyping::Client.allocate
client.instance_variable_set(:@program,EltenGameRoom.allocate)
announcements=[]
client.define_singleton_method(:alert) { |message| announcements << message }
Dir.mktmpdir('table-picker-') do |dir|
  file=File.join(dir,'sample.uti')
  File.write(file,'# table')
  FilesTree.chosen=file
  Form.driver=lambda do |form|
    assert(form.fields.first.is_a?(FilesTree),'Table selection must use the file browser')
    assert(form.fields.none? { |field| field.is_a?(EditBox) },'A path input replaced the file browser')
    assert(form.fields.first.extensions==%w[.ctb .utb .tbl .uti],'Wrong extensions')
    form.accept_button.trigger(:press)
  end
  assert(client.send(:choose_local_braille_table)==file,'Browser selection lost its path')
  assert(FilesTree.last.closed,'File preview was not closed')
  assert(announcements.one? && announcements.first.include?('.uti'),'Accepted extensions were not announced')
end
puts 'PASS native file-browser integration: selected .uti, announced extensions, no path field, preview cleanup.'
