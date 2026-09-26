require_relative "game_room_ui"

class GameRoomPresenceScreen
  using GameRoomLocalization::Translations

  def initialize(program:, reader:)
    @program, @reader = program, reader
  end

  def run
    data = read_data
    summary = EditBox.new(GameRoomContent.utf8(_("Current room activity")),
      type: EditBox::Flags::ReadOnly | EditBox::Flags::MultiLine,
      text: summary_text(data), quiet: true)
    refresh = Button.new(GameRoomContent.utf8(_("Refresh")))
    back = Button.new(GameRoomContent.utf8(_("Back")))
    form = GameRoomUI::Form.new([summary, refresh, back], program: @program, quiet: true)
    form.cancel_button = back
    refresh.on(:press) { summary.set_text(summary_text(read_data)) }
    back.on(:press) { form.resume }
    form.wait
  end

  private

  def read_data
    @reader.call
  rescue StandardError => error
    Log.warning("Room activity read failed: #{error.class}: #{error.message}") if defined?(Log)
    nil
  end

  def summary_text(data)
    lines = if data
      [GameRoomContent.utf8(_("Public rooms: %{count}")) % { count: data.fetch("public_rooms") },
        GameRoomContent.utf8(_("Private rooms: %{count}")) % { count: data.fetch("private_rooms") },
        GameRoomContent.utf8(_("People in rooms: %{count}")) % { count: data.fetch("people") }]
    else
      [GameRoomContent.utf8(_("Room activity is unavailable. Try Refresh."))]
    end
    (lines + [
      GameRoomContent.utf8(_("These counts come from recent reports by updated clients. Reports expire after about two minutes; rooms without an updated client reporting them may be missing.")),
      GameRoomContent.utf8(_("The people count is the sum of room membership counts: it includes observers and excludes bots. A person in more than one room may be counted more than once. This is not a global online count."))
    ]).join("\n")
  end
end
