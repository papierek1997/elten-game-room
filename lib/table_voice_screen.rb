# encoding: UTF-8
require_relative 'tournaments/ui_dialogs'
require_relative 'table_voice_protocol'

class GameRoomTableVoiceScreen
  using GameRoomLocalization::Translations
  class ContextChanged < StandardError; end
  def initialize(program:,transport:,table:,conference:Conference)
    @program,@transport,@table,@conference=program,transport,table,conference
    @actor=Session.name.to_s.dup
  end
  def run
    current=network { @transport.table_voice(@table,force:true) }
    return unless current && same_account?
    previous=@table['voice']
    if GameRoomTableVoice.connected?(previous,@conference) && previous['head']!=current['head']
      return disconnect_native(previous)
    end
    if current['status']=='ready'
      leaving = GameRoomParticipants.same?(@actor,current['creator']) || GameRoomTableVoice.connected?(current,@conference)
      return leaving ? disconnect(current) : join(current)
    end
    values=Creation.new(program:@program,table_name:@table['name']).run
    return unless values && same_account? && switch_allowed?
    claimed=network { @transport.change_table_voice(@table,{'operation'=>'claim','previous'=>current['head']},actor:@actor) }
    return unless claimed && same_account?
    unless claimed[:accepted]
      return join(claimed[:voice]) if claimed[:voice]&.[]('status')=='ready'
      alert(_("Someone is already preparing the voice conversation. Try again shortly."))
      return
    end
    claim=claimed.fetch(:voice)
    # Clear the previous native membership before allocating a temporary
    # channel. Native create already joins its creator; joining a second time
    # can discard the channel while its asynchronous local view is still old.
    if @conference.opened? && !@conference.leave
      network { @transport.change_table_voice(@table,{'operation'=>'clear','previous'=>claim['head']},actor:@actor) }
      alert(_("The voice channel could not be created."))
      return
    end
    observed=nil
    conference_hook=@conference.on(:update) { observed=@conference.channel }
    channel=@conference.create(values[:name],values[:public],64,60,1,0,false,false,values[:password])
    unless channel.is_a?(Integer) && channel.positive?
      network { @transport.change_table_voice(@table,{'operation'=>'clear','previous'=>claim['head']},actor:@actor) }
      alert(_("The voice channel could not be created."))
      return
    end
    return unless same_account?
    created_voice=claim.slice('head','creator').merge('status'=>'ready',
      'channel_id'=>channel,'name'=>values[:name],'password'=>values[:password].to_s)
    # Confirm a new native update, not an old cached channel with a reused ID.
    # The existing native update loop owns I/O; this wait only observes it.
    ready=-> { observed && observed.id==channel && observed.name==values[:name] &&
      observed.users.any? { |person|GameRoomParticipants.same?(person.name,@actor) } }
    unless AwaitConnection.new(program:@program,ready:ready,current:method(:same_account?)).run
      return unless same_account?
      network { @transport.change_table_voice(@table,{'operation'=>'clear','previous'=>claim['head']},actor:@actor) }
      JoinFailed.new(program:@program,can_reset:false).run if same_account?
      return
    end
    return unless same_account?
    published=network do
      @transport.change_table_voice(@table,{'operation'=>'publish','previous'=>claim['head'],
        'channel_id'=>channel,'name'=>values[:name],'password'=>values[:password].to_s},actor:@actor)
    end
    return unless published && same_account?
    voice=published[:voice]
    if published[:accepted] && voice && voice['status']=='ready' &&
        voice.values_at('channel_id','name','creator')==created_voice.values_at('channel_id','name','creator')
      creation_published=true
      remember(voice)
      true
    else
      alert(_("The voice invitation was not confirmed. Try again shortly."))
    end
  rescue ContextChanged
    alert(_("The signed-in account has changed."))
  rescue StandardError => error
    raise unless GameRoomNetworkErrors.expected?(error) || GameRoomNetworkErrors.cancelled?(error)
    alert(_("The voice conversation is temporarily unavailable."))
  ensure
    @conference.remove_hook(conference_hook) if conference_hook
    cleanup_unpublished_voice(created_voice, creation_published)
  end

  private def cleanup_unpublished_voice(created_voice, creation_published)
    # Native create has already joined us, even if its :update is delayed or
    # publication loses its claim. Never leak that unpublished membership;
    # an unrelated conference (including a reused numeric ID) stays untouched.
    if created_voice && !creation_published && same_account?
      # If even the cached channel view is still delayed, retain only the
      # exact local identity so ordinary table departure can clean it later.
      remember(created_voice) unless GameRoomTableVoice.connected?(created_voice,@conference) && disconnect_native(created_voice)
    end
  end

  private
  def network(&block)
    @program.send(:run_network_task,_("Voice conversation"),ui: :none) do
      raise ContextChanged unless same_account?
      block.call
    end
  end
  def same_account?; GameRoomParticipants.same?(@actor,Session.name); end
  def alert(message); @program.send(:alert,GameRoomContent.utf8(message)); end
  def remember(voice)
    @program.send(:remember_table_voice,@table.merge('voice'=>voice)) if @program.respond_to?(:remember_table_voice,true)
  end
  def switch_allowed?(target=nil)
    channel=@conference.channel if @conference.opened?
    return true unless channel && channel.id.to_i.positive? && channel.id != target
    @program.send(:confirm,_("Leave your current conference and join this conversation?"))
  end
  def disconnect(voice)
    return false unless disconnect_native(voice)
    return unless same_account?
    return true unless GameRoomParticipants.same?(@actor,voice['creator'])
    cleared=network { @transport.change_table_voice(@table,{'operation'=>'clear','previous'=>voice['head']},actor:@actor) }
    cleared && cleared[:accepted]
  end
  def disconnect_native(voice)
    if GameRoomTableVoice.connected?(voice,@conference) && !@conference.leave
      alert(_("The voice conversation could not be disconnected."))
      return false
    end
    true
  end
  def join(voice,confirmed:false)
    return unless voice && voice['status']=='ready' && same_account?
    return unless confirmed || switch_allowed?(voice['channel_id'])
    success=@conference.join(voice.fetch('channel_id'),voice['password'].to_s.empty? ? nil : voice['password'])
    remember(voice) if success
    unless success
      can_reset=GameRoomParticipants.same?(@actor,voice['creator']) || GameRoomParticipants.same?(@actor,@table['owner'])
      reset=JoinFailed.new(program:@program,can_reset:can_reset).run
      if reset && same_account?
        network { @transport.change_table_voice(@table,{'operation'=>'clear','previous'=>voice['head']},actor:@actor) }
      end
    end
    success
  end

  class AwaitConnection < GameRoomTournaments::Dialogs::Window
    using GameRoomLocalization::Translations
    def initialize(program:,ready:,current:)
      @program,@ready,@current=program,ready,current
    end
    def run
      return true if @current.call && @ready.call
      super
    ensure
      @form.delete_timer(@deadline) if @form && @deadline
    end
    private
    def build_form
      status=readonly(_("Voice conversation"),_("Connecting to the voice conversation..."))
      back=button(_("Back"))
      make_form([status,back],cancel:back)
      @form.hub_update=-> do
        finish(false) unless @current.call
        finish(true) if !@finished && @ready.call
      end
      @deadline=FormTimer.new(5) { finish(false) }
      @form.add_timer(@deadline)
    end
  end

  class JoinFailed < GameRoomTournaments::Dialogs::Window
    using GameRoomLocalization::Translations
    def initialize(program:,can_reset:); @program,@can_reset=program,can_reset; end
    private
    def build_form
      message=readonly(_("Voice conversation"),_("The voice conversation could not be joined. It may have been closed."))
      reset=button(_("Remove this voice invitation")) { finish(true) } if @can_reset
      back=button(_("Back"))
      make_form([message,reset,back].compact,cancel:back)
    end
  end

  class Creation < GameRoomTournaments::Dialogs::Window
    using GameRoomLocalization::Translations
    def initialize(program:,table_name:)
      @program,@table_name=program,table_name
    end
    private
    def build_form
      name=EditBox.new(text(_("Channel name")),text:@table_name.to_s[0,100],quiet:true,max_length:100)
      visibility=ListBox.new([text(_("Public channel")),text(_("Hidden channel"))],header:text(_("Visibility")),quiet:true)
      visibility.index=1
      password=EditBox.new(text(_("Password (optional)")),type:EditBox::Flags::Password,text:'',quiet:true,max_length:128)
      create=button(_("Create voice conversation")) do
        next if name.text.to_s.strip.empty?
        finish({name:name.text.to_s.strip,public:visibility.index==0,password:password.text.to_s.empty? ? nil : password.text})
      end
      cancel=button(_("Cancel"))
      make_form([name,visibility,password,create,cancel],cancel:cancel)
    end
  end
end
