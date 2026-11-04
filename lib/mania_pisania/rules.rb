require_relative '../game_rules'

module GameRoomTyping
  class RuleBook < GameRoomRules::Book
    def documents
      extra, main = sections.partition { |section| section.id.to_s.start_with?('touch_') }
      ordinary = GameRoomRules::Book.new(game_id: game_id, title: title, sections: main).documents
      opening = main.find { |section| section.id == :main_0 }
      rules = ordinary.first
      ordinary[0] = GameRoomRules::Document.new(id: rules.id, title: rules.title,
        sections: rules.sections.reject { |section| section == opening }, contents: true,
        introduction: opening ? opening.paragraphs : [], compact: true)
      ordinary.map! do |document|
        next document unless document.is_a?(GameRoomRules::Document) && document.id != :rules
        GameRoomRules::Document.new(id: document.id, title: document.title,
          sections: document.sections, contents: !!document.contents_title, compact: true)
      end
      return ordinary if extra.empty?
      ordinary.insert(2, GameRoomRules::Document.new(id: :touch_typing, title: extra.first.title,
        sections: extra, contents: true, compact: true))
    end
  end
end
