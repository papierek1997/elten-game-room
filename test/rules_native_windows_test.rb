require_relative "taboo_rules_dictionary_test"

class Form
  class << self
    attr_accessor :rules_window_driver
  end
  def wait
    raise "Unexpected rules form" unless Form.rules_window_driver
    Form.rules_window_driver.call(self)
  end
  def resume; end
end

windows = 0
%w[en pl fallback].each do |language|
  $rules_english = language != "pl"
  EltenGameRoom::GAME_REGISTRY.ids.each do |id|
    game = EltenGameRoom::GAME_REGISTRY.build(id)
    book = game.rule_book(options: game.default_options)
    authored = JSON.parse(File.read(File.join(BinaryRulesLoad::ROOT, "docs/rulebooks/#{id}.json"), encoding: "UTF-8"))
    sections = game.rule_sections.to_h { |section| [section.id.to_s, section] }
    authored.fetch("sections").each do |section|
      key = language == "pl" ? "pl" : "en"
      actual = sections.fetch(section.fetch("id"))
      raise "Mixed-language #{id}/#{key} heading" unless actual.title == section.fetch("title").fetch(key)
      raise "Mixed-language #{id}/#{key} text" unless actual.paragraphs == section.fetch("paragraphs").map { |pair| pair.fetch(key) }
    end
    document = nil
    visits = 0
    Form.rules_window_driver = lambda do |form|
      visible = form.fields - form.hidden_controls
      raise "Rules gained extra focus stops" unless visible.length == 1
      field = visible.first
      role = language == "fallback" ? " — список" : " — pole"
      raise "Mixed-encoding #{id} window" unless (field.header + role).valid_encoding?
      if document == nil
        raise "Wrong document list" unless field.options == book.documents.map(&:title)
        if visits == 3
          form.cancel_button.trigger(:press)
        else
          field.index = visits
          document = book.documents[visits]
          visits += 1
          form.accept_button.trigger(:press)
        end
      else
        if document.id == :controls
          raise "Shortcuts are not a native list" unless field.is_a?(ListBox) && field.options == document.paragraphs
          field.options.each { |tip| raise "Binary shortcut row" unless (tip + role).valid_encoding? }
          raise "Enter not available" unless form.accept_button == form.cancel_button
        else
          raise "Rules/settings split across windows" unless field.is_a?(EditBox) && field.text == document.text
          raise "Binary rule document" unless field.text.encoding == Encoding::UTF_8 && field.text.valid_encoding?
        end
        windows += 1
        document = nil
        form.cancel_button.trigger(:press)
      end
    end
    GameRoomScreens::GameRules.new(book).wait
  end
end
Form.rules_window_driver = nil
puts "PASS binary rules UI: #{windows} document windows for 24 games, EN/PL and English fallback beside a non-English host, with native dictionary compatibility"
