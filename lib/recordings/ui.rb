require_relative '../game_room_ui'
require_relative '../realtime/progress'
require_relative '../game_sound_output'
require_relative 'delivery'
require_relative 'player'
require_relative 'controls'

module GameRoomRecordings
  class PlayerForm < GameRoomUI::Form
    attr_accessor :refresh_perspectives

    def initialize(*args,**options)
      @ui_thread=Thread.current
      super
    end

    def update
      super
      # Progress can advance playback while this form is covered. Native
      # controls belong only to this form's active UI update, not that worker.
      refresh_perspectives&.call if Thread.current.equal?(@ui_thread) &&
        !game_room_background_help? && $activecontrols.to_a.include?(self)
    end
  end

  class UI
    using GameRoomLocalization::Translations

    def initialize(program,delivery:nil)
      @program=program
      @library=program.recording_library
      @delivery=delivery
    end
    def text(value); GameRoomContent.utf8(value); end
    def task(title,&operation); @program.recording_task(text(title),&operation); end

    def library
      selected=nil
      loop do
        rows=task(_('Loading histories and replays')) { @library.list }
        return unless rows
        index=rows.index { |row| row['filename']==selected } || 0
        actions=[[:import,_('Import file'),'i'],[:messages,_('Import from messages'),'m'],[:refresh,_('Refresh'),'r']]
        unless rows.empty?
          actions=[[:open,_('Open'),'o'],[:details,_('Details'),'d'],[:rename,_('Rename'),'n'],
            [:export,_('Export file'),'e'],[:send,_('Send to player'),'s'],[:delete,_('Delete'),:del]]+actions
        end
        action,index=select(_('Histories and replays'),rows.map { |row| label(row) },actions:actions,index:index,
          empty:_('No saved histories or replays. Use Ctrl+I to import a file.'))
        return if action==:back
        row=rows[index]
        selected=row && row['filename']
        case action
        when :import
          path=get_file(text(_('Import history or replay')),path:Dirs.documents)
          task(_('Importing history or replay')) { @library.import(EltenPath.normalize(path)) } if path
        when :messages then import_messages
        when :refresh then next
        when :open
          bytes=task(_('Opening history or replay')) { @library.read(row.fetch('filename')) } if row
          open_bytes(bytes,File.extname(row['filename']).downcase) if bytes
        when :details then show_text(_('Recording details'),details(row)) if row
        when :rename
          title=input_text(text(_('Recording name')),text:row['title']) if row
          task(_('Renaming recording')) { @library.rename(row['filename'],text(title)) } if title && !title.strip.empty?
        when :export
          directory=get_file(text(_('Export history or replay')),path:Dirs.documents,save:true) if row
          if directory
            result=task(_('Exporting recording')) { @library.export(row['filename'],EltenPath.normalize(directory)) }
            alert(text(_('The recording has been exported.'))) if result
          end
        when :delete
          if row && confirm(text(_('Delete this recording file from the library? Exported copies will remain.')))
            task(_('Deleting recording')) { @library.delete(row['filename']) }
          end
        when :send
          send_recording(row) if row
        end
      end
    end

    def open_bytes(bytes,extension)
      if extension=='.txt'
        meta=Document.text_metadata(bytes)
        show_text(meta['title'],bytes.dup.force_encoding(Encoding::UTF_8))
      else
        value=task(_('Opening history or replay')) { Prepared.load(bytes) }
        play(value) if value
      end
    rescue Invalid
      alert(text(_('This history or replay is damaged or unsupported.')))
    end

    def send_recording(row)
      user=input_user(text(_('Send recording to player')))
      return unless user.is_a?(String) && !user.empty?
      result=task(_('Sending recording')) { (@delivery || Delivery.new(@library)).send_file(row['filename'],recipient:user) }
      return unless result
      alert(text(result[:removed] ? _('The recording has been sent.') :
        _('The recording was sent, but the sent message could not be removed. Your library file is unchanged.')))
    end

    def import_messages
      delivery=@delivery || Delivery.new(@library)
      rows=task(_('Loading recording messages')) { delivery.incoming }
      return unless rows
      if rows.empty?
        alert(text(_('There are no recording messages to import.')))
        return
      end
      action,index=select(_('Recording messages'),rows.map { |ref|
        text(_('%{sender}; %{name}; %{date}')) % {sender:ref['sender'],name:ref['description'],date:Time.at(ref['date']).strftime('%Y-%m-%d %H:%M')}
      })
      return unless action==:open
      ref=rows[index]
      choice,option=select(ref['description'],[_('Play or view'),_('Add to library')])
      return unless choice==:open
      packet=task(_('Downloading recording')) { delivery.receive(ref) }
      return unless packet
      if option.zero?
        open_bytes(packet[:bytes],packet[:extension])
      else
        name=task(_('Importing history or replay')) { @library.import_bytes(packet[:bytes],extension:packet[:extension]) }
        return unless name
        alert(text(_('The recording has been added to the library.')))
        if confirm(text(_('Delete the message containing this recording from your messages?')))
          removed=task(_('Deleting recording message')) { delivery.remove_received(ref) }
          alert(text(_('The message has been deleted.'))) if removed
        end
      end
    end

    def play(value)
      progress=nil
      output=GameRoomSoundOutput.new(@program,audio_game:true,covered:-> { progress&.covered? })
      player=Player.new(value,renderer:->(clock) {
        audio=@program.recording_audio(value['metadata'],clock:clock)
        audio.background_provider=-> { progress&.covered? } if audio.respond_to?(:background_provider=)
        audio
      })
      form=player_form(player)
      progress=GameRoomRealtime::Progress.new(program:@program,clock:-> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
        key:[:recording,value['metadata']['id']]) { |_background| output.tick;player.tick }
      progress.attach(form)
      form.wait
    ensure
      progress&.close
      player&.close
      output&.close
    end

    private

    def player_form(player)
      controls=Controls.new(player,position_text:method(:position_text),speaker:->(message) {speak(text(message))})
      field=Button.new(text(_('Replay player')))
      perspectives=controls.information.perspectives
      perspective=ListBox.new(perspectives.map { |_,name| text(name) },header:text(_('Listening perspective')),
        index:controls.information.perspective_index,quiet:true)
      speed=ListBox.new(Player::SPEEDS.map { |rate| "#{rate}×" },header:text(_('Playback speed')),index:Player::SPEEDS.index(1.0),quiet:true)
      close=Button.new(text(_('Close')))
      form=PlayerForm.new([field,perspective,speed,close],program:@program,quiet:true)
      form.cancel_button=close
      form.refresh_perspectives=-> do
        current=controls.information.perspectives
        unless current==perspectives
          perspectives=current
          perspective.update_options(current.map { |_,name| text(name) },keys:current.map(&:first))
        end
        index=controls.information.perspective_index
        perspective.index=index unless perspective.index==index
      end
      activate=->(action) do
        EltenAPI::KeyboardState.clear_current_frame if defined?(EltenAPI::KeyboardState)
        controls.perform(action)
        form.refresh_perspectives.call
      end
      field.on(:press) do
        code=field.send(:key_pressed?,:key_enter) ? 0x0D : 0x20
        next if %i[shift control option command].any? { |modifier| field.send(:keyboard_modifier_held_when_pressed?,code,modifier) }
        activate.call(player.playing ? :pause : :play)
      end
      {left:0x25,right:0x27}.each do |key,code|
        field.on("key_#{key}".to_sym) do
          next if %i[shift control option command].any? { |modifier| field.send(:keyboard_modifier_held_when_pressed?,code,modifier) }
          row=controls.operations.find { |entry| entry[2]==key }
          activate.call(row[0]) if row
        end
      end
      field.bind_context do |menu|
        controls.operations.each do |action,label,key|
          shortcut=controls.context_key(key)
          label="#{text(label)} (#{text(controls.key_label(key))})" if shortcut==''
          menu.option(text(label),nil,shortcut) { activate.call(action) }
        end
      end
      GameRoomContextHelp.replace([field],[])
      field.game_room_context_help_provider=-> do
        controls.operations.map { |_,label,key| GameRoomContextHelp.shortcut_tip(text(controls.key_label(key)),text(label)) }
      end
      perspective.on(:move) { player.seat=perspectives[perspective.index][0] }
      speed.on(:move) { player.speed=Player::SPEEDS[speed.index] }
      close.on(:press) { form.resume }
      form
    end

    def label(row)
      title=row['kind']=='damaged' ? text(_('Damaged history or replay'))+': '+row['title'] : row['title']
      [title,row['players'].join(', '),Time.at(row['recorded_at']).strftime('%Y-%m-%d %H:%M')].reject(&:empty?).join('; ')
    end

    def details(row)
      lines=[row['title'],row['players'].join(', '),Time.at(row['recorded_at']).strftime('%Y-%m-%d %H:%M')]
      lines << text(_('Duration: %{time}'))%{time:time_text(row['duration_ms'])} if row['duration_ms']
      lines << text(_('The recording starts after the beginning of the match.')) if row['complete_start']==false
      lines << text(_('The recording does not include the end of the match.')) if row['kind']=='audio' && row['complete_end']==false
      lines.join("\n")
    end

    def time_text(milliseconds)
      seconds=milliseconds.to_i/1000
      format('%02d:%02d:%02d',seconds/3600,seconds/60%60,seconds%60)
    end

    def position_text(player)
      text(_('Position: %{position} of %{duration}.')) % {
        position:time_text(player.position),duration:time_text(player.duration)}
    end

    def show_text(title,value)
      field=GameRoomUI::HelpText.new(text(title),type:EditBox::Flags::MultiLine|EditBox::Flags::ReadOnly,text:text(value))
      close=Button.new(text(_('Close')))
      form=GameRoomUI::Form.new([field,close],program:@program,quiet:true)
      form.accept_button=form.cancel_button=close
      close.on(:press) { form.resume }
      form.wait
    end

    def select(title,labels,actions:[],index:0,empty:nil)
      list=ListBox.new(labels.map { |label| text(label) },header:text(title),index:labels.empty? ? 0 : index.clamp(0,labels.size-1),quiet:true,
        empty_label:empty && text(empty))
      open=Button.new(text(_('Open')))
      close=Button.new(text(_('Back')))
      form=GameRoomUI::Form.new([list,open,close],program:@program,quiet:true)
      form.accept_button,form.cancel_button=open,close
      form.hide(open);form.hide(close)
      result=:back
      finish=->(action) {result=action;form.resume}
      open.on(:press) { finish.call(:open) unless labels.empty? }
      close.on(:press) {form.resume}
      list.bind_context { |menu| actions.each { |action,label,key| menu.option(text(label),nil,key) {finish.call(action)} } }
      GameRoomContextHelp.replace([list],actions.map { |_,label,key| GameRoomContextHelp.shortcut_tip(key==:del ? 'Delete' : "Ctrl+#{key.upcase}",text(label)) })
      form.wait
      [result,list.index.to_i]
    end
  end
end
