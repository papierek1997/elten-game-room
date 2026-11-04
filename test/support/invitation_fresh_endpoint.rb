require_relative "ui"
require_relative "native_live_sessions"
class Program
  def self.server_app(**_options); end
  def self.app_runtime; nil; end
  def self.server_app_uuid; "test-app"; end
end
require_relative "../../__app"

Notice = Struct.new(:id, :app_uuid, :revoked, :type, :metadata, :sender, keyword_init: true)
class DurableNoticeGateway
  attr_accessor :error
  attr_reader :rows
  def initialize; @rows = Hash.new { |hash, user| hash[user] = [] }; end
  def list(user, **_arguments)
    raise error if error
    @rows[user].reject(&:revoked)
  end
  def revoke(user, id); @rows[user].find { |row| row.id == id }.revoked = true; end
  def revoke_many(user, ids); ids.each { |id| revoke(user, id) }; end
  def send(user, metadata, type: "game_room.invitation", sender: metadata["sender"] || Session.name)
    notice = Notice.new(id: @rows.values.flatten.length + 1, app_uuid: "test-app", revoked: false, type: type, metadata: metadata, sender: sender)
    @rows[user] << notice
    notice
  end
end

class InvitationAppDriver < EltenGameRoom
  # These headless invitation fixtures have no installed Runtime/filesystem.
  # Real startup preparation is covered by local_directories_test and live UI.
  def prepare_local_directories; end
  attr_reader :alerts, :errors, :sent
  def initialize(broker, user, gateway, fresh: false)
    # Native startup publishes local preferences before notification actions.
    self.class.remember_settings({}) unless self.class.instance_variable_get(:@normalized_settings)
    @alerts, @errors, @sent = [], [], []
    @user, @gateway = user, gateway
    program = ProgramDouble.new(broker.endpoint(user, fresh: fresh))
    @transport = GameRoomTransport.new(program)
    @lobby = LobbyRepository.new(program, transport: @transport, server_tables: {})
    @games = GameRepository.new(program, transport: @transport, server_tables: {})
    @table_activity = TableActivityRepository.new(server_tables: {}, transport: @transport)
    @invitation_notifications = InvitationNotifications.new(client: user, app_uuid: "test-app", gateway: gateway)
    @invitations = InvitationRepository.new(transport: @transport,
      notification_source: ->(recipient, now) { @invitation_notifications.pending(recipient: recipient, now: now) },
      response_sender: ->(row, _response) { InvitationRepository.resolve_sent(row) })
  end
  def run_network_task(*_arguments, **_keywords)
    yield
  rescue StandardError => error
    raise unless GameRoomNetworkErrors.expected?(error)
    @errors << error
    nil
  end
  def send_notification(user, type:, metadata:, expires_in:, key:)
    @sent << [type, metadata, expires_in]
    @gateway.send(user, metadata, type: type, sender: Session.name)
  end
  def alert(text); @alerts << text; end
  def announce_joined_room(_row); end
  def confirm(_text); true; end
  def play_game_sound(_name); end
  def transport; @transport; end
end
