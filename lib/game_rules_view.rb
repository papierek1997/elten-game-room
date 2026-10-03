require_relative "game_rules"

module GameRoomRules
  class View < EditBox
    def initialize(header, document:)
      super(GameRoomContent.utf8(header), type: Flags::ReadOnly | Flags::MultiLine,
        text: document.text, quiet: true, detect_text_links: false)
      add_document_elements(document)
      append_text_links
    end

    def readupdate
      if key_pressed?(:key_enter) && (heading = @contents_targets[active_link])
        @index = @check = heading.from
        espeech(text_range(heading.from, heading.to))
        return
      end
      super
    end

    def tips
      previous_flags = @flags
      @flags |= Flags::MarkDown
      super
    ensure
      @flags = previous_flags
    end

    private

    def add_document_elements(document)
      offset = 0
      links = []
      if document.contents_title
        add_element(document.contents_title, offset, Element::Header, 1)
        offset += document.contents_title.length + 1
        document.sections.each_with_index do |section, index|
          links << add_element(section.title, offset, Element::Link, [0, "#rule-section-#{index}"])
          offset += section.title.delete("\r").length + 1
        end
        offset += 1
      end
      headings = document.sections.map do |section|
        heading = add_element(section.title, offset, Element::Header, 2)
        offset += "#{section.title}\n#{section.text}".delete("\r").length + 2
        heading
      end
      @contents_targets = links.zip(headings).to_h
    end

    def add_element(text, offset, type, parameter)
      element = Element.new(offset, offset + text.delete("\r").length - 1, type, parameter)
      @elements << element
      element
    end

    def active_link
      links = @elements.select { |element| [Element::Link, Element::Frame].include?(element.type) }
      links.reverse.find { |element| element.from <= @index && element.to >= @index } ||
        links.reverse.find { |element| element.from >= line_beginning && element.to <= line_ending }
    end
  end
end
