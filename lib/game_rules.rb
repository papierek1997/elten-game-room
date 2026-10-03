require_relative "game_content"
require_relative "context_help"

require_relative "game_room_localization"

module GameRoomRules
  using GameRoomLocalization::Translations
  REQUIRED_SECTION_IDS = [:controls].freeze
  CTRL_F1_KEY = 0x70

  module ShortcutFormEvents
    private

    def keyevents
      events = super
      if key_first_pressed?(GameRoomRules::CTRL_F1_KEY)
        events << [:key_f1, :f1]
      end
      events
    end
  end

  class Section
    attr_reader :id, :title, :paragraphs

    def initialize(id:, title:, paragraphs:)
      @id = id.to_sym
      @title = GameRoomContent.utf8(title).strip
      @paragraphs = paragraphs.to_a.map { |paragraph| GameRoomContent.utf8(paragraph).strip }.reject(&:empty?).freeze
      raise ArgumentError, "a rule section requires an id" if @id.to_s.empty?
      raise ArgumentError, "a rule section requires a title" if @title.empty?
      raise ArgumentError, "a rule section requires content" if @paragraphs.empty?
    end

    def text
      paragraphs.join("\r\n\r\n")
    end
  end

  class Document < Section
    attr_reader :sections, :contents_title

    def initialize(id:, title:, sections:, contents: false)
      @sections = sections.to_a.dup.freeze
      @contents_title = GameRoomContent.utf8(_("Contents")) if contents
      paragraphs = @sections.map { |section| "#{section.title}\r\n#{section.text}" }
      paragraphs.unshift([@contents_title, *@sections.map(&:title)].join("\r\n")) if contents
      super(id: id, title: title, paragraphs: paragraphs)
    end
  end

  class Book
    attr_reader :game_id, :title, :sections

    def initialize(game_id:, title:, sections:)
      @game_id = game_id.to_s.strip
      @title = title.to_s.strip
      @sections = sections.to_a.freeze
      raise ArgumentError, "a rule book requires a game id" if @game_id.empty?
      raise ArgumentError, "a rule book requires a title" if @title.empty?
      if @sections.any? { |section| !section.is_a?(Section) }
        raise ArgumentError, "a rule book may contain only rule sections"
      end

      ids = @sections.map(&:id)
      raise ArgumentError, "rule section ids must be unique" if ids.uniq.length != ids.length
      missing = REQUIRED_SECTION_IDS - ids
      if !missing.empty?
        raise ArgumentError, "missing rule sections: #{missing.join(", ")}"
      end
      raise ArgumentError, "a rule book requires game rules" if (ids - [:controls, :current_options]).empty?
    end

    # Sections are headings in a document, not separate places in the UI.
    # Keep the two documents independent so rules never repeat key bindings.
    def documents
      result = [
        Document.new(id: :rules, title: _("Rules"), sections: sections.reject { |section| [:controls, :current_options].include?(section.id) }, contents: true),
        Section.new(id: :controls, title: _("In-game keyboard shortcuts"), paragraphs: sections.find { |section| section.id == :controls }.paragraphs)
      ]
      current = sections.find { |section| section.id == :current_options }
      result << Document.new(id: current.id, title: current.title, sections: [current]) if current
      result
    end

    def with_current_options(summary)
      text = summary.to_s.strip
      return self if text.empty?

      current = Section.new(
        id: :current_options,
        title: _("Current table options"),
        paragraphs: [text]
      )
      self.class.new(game_id: game_id, title: title, sections: [current] + sections.reject { |section| section.id == :current_options })
    end
  end

  def self.translate(text)
    source = GameRoomContent.utf8(text)
    GameRoomContent.utf8(_(source))
  end

  def self.bind_ctrl_f1(form, fields, &handler)
    raise ArgumentError, "Ctrl+F1 requires an action" if handler == nil

    form.extend(ShortcutFormEvents)
    tip = GameRoomContextHelp.shortcut_tip("Ctrl+F1", _("Game rules"))
    fields.to_a.each do |field|
      field.add_tip(tip) if field.respond_to?(:add_tip)
    end
    GameRoomContextHelp.exclude_from_game_help(fields, [tip])
    form.on(:key_f1) do |parameters|
      next if !ctrl_f1_event?(parameters)

      EltenAPI::KeyboardState.clear_current_frame if defined?(EltenAPI::KeyboardState)
      handler.call
    end
  end

  def self.ctrl_f1_event?(parameters)
    shift, main_modifier, option = parameters.to_a
    shift != true && main_modifier == true && option != true
  end
end
