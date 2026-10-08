# encoding: UTF-8
require "prism"

module GameRoomTranslationExtractor
  # Development-only AST reader: no source execution, GetText objects, or gameplay-data loading.
  def self.source_files(root)
    raise ArgumentError, "source root is not a directory: #{root}" unless File.directory?(root)
    Dir.glob(["__app.rb", "{games,lib,content}/**/*.rb"], base: root).sort.reject do |path|
      (!path.start_with?('games/generated/rulebooks/') && path.split("/").any? { |part| %w[vendor generated wordlists worddata].include?(part) }) ||
        path.match?(%r{\Acontent/(?:quiz_.*_data|taboo_cards_.*_data|scrabble_words_.*_data)[.]rb\z}) ||
        path == "games/krowa_support/noun_data.rb"
    end
  end

  # Pass warnings: [] to collect {path:, line:, code:, message:}; nil reports to stderr.
  def self.extract(root, warnings: nil)
    records = {}
    source_files(root).each do |path|
      extract_source(File.read(File.join(root, path), encoding: "UTF-8"), path: path, warnings: warnings).each do |record|
        merge_record(records, **record)
      end
    end
    records.values
  end

  def self.merge_record(records, msgid:, msgid_plural:, msgctxt:, references:, comments:)
    key = [msgctxt, msgid]
    record = records[key] ||= { msgid: msgid, msgid_plural: msgid_plural, msgctxt: msgctxt, references: [], comments: [] }
    if msgid_plural && record[:msgid_plural] && record[:msgid_plural] != msgid_plural
      raise ArgumentError, "conflicting plural for #{msgid.inspect}: #{record[:references].join(', ')} and #{references.join(', ')}"
    end
    record[:msgid_plural] ||= msgid_plural
    record[:references] |= references
    record[:comments] |= comments
  end

  def self.literal(node)
    return node.unescaped if node.is_a?(Prism::StringNode)
    if node.is_a?(Prism::InterpolatedStringNode) && node.parts.all? { |part| part.is_a?(Prism::StringNode) }
      return node.parts.map(&:unescaped).join
    end
    nil
  end

  def self.constant_name(node)
    case node
    when Prism::ConstantReadNode then node.name.to_s
    when Prism::ConstantPathNode
      [constant_name(node.parent), node.name.to_s].compact.join("::")
    end
  end

  def self.message_arguments(node, scopes)
    args = node.arguments&.arguments || []
    case node.name
    when :_, :N_ then [args[0], nil, nil]
    when :n_, :Nn_ then [args[0], args[1] || node, nil]
    when :p_ then [args[1], nil, args[0] || node]
    when :np_ then [args[1], args[2] || node, args[0] || node]
    when :translate
      receiver = constant_name(node.receiver)
      local = node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode)
      return unless ["GameRoomRules", "GameRoomLocalization"].include?(receiver) || (local && scopes.include?("GameRoomRules"))

      keywords = args.last.is_a?(Prism::KeywordHashNode) ? args.last.elements : []
      return [args[0], args.last, nil] if keywords.any? { |pair| !pair.is_a?(Prism::AssocNode) || !pair.key.is_a?(Prism::SymbolNode) }
      options = keywords.each_with_object({}) do |pair, result|
        result[pair.key.unescaped] = pair.value if pair.is_a?(Prism::AssocNode) && pair.key.is_a?(Prism::SymbolNode)
      end
      [args[0], options["plural"], options["context"]].map { |argument| argument.is_a?(Prism::NilNode) ? nil : argument }
    end
  end

  def self.warning(warnings, path, node, message, code: :dynamic_message)
    item = { path: path, line: node.location.start_line, code: code, message: message }
    warnings ? warnings << item : warn("#{path}:#{item[:line]}: #{message}")
  end

  def self.unfreeze(node)
    if node.is_a?(Prism::CallNode) && node.name == :freeze && node.arguments.nil? && node.block.nil?
      node.receiver
    else
      node
    end
  end

  def self.inventory_string(node, records, path, warnings)
    value = literal(unfreeze(node))
    if value.nil?
      warning(warnings, path, node, "UI inventory requires a literal string; dynamic source was not extracted")
    else
      merge_record(records, msgid: value, msgid_plural: nil, msgctxt: nil,
        references: ["#{path}:#{node.location.start_line}"], comments: [])
    end
  end

  # Only these path-scoped UI schemas are inventories; arbitrary Ruby dataflow is not evaluated.
  def self.changelog_inventory(node, scopes, records, path, warnings)
    return unless path == "lib/game_room_changelog.rb" && scopes == ["GameRoomChangelog"] && node.is_a?(Prism::ConstantWriteNode)
    case node.name
    when :ENTRY_TEMPLATE
      inventory_string(node.value, records, path, warnings)
    when :ENTRIES
      entries = unfreeze(node.value)
      unless entries.is_a?(Prism::ArrayNode)
        return warning(warnings, path, node, "Changelog ENTRIES requires a literal array")
      end
      entries.elements.each do |entry|
        call = unfreeze(entry)
        if call.is_a?(Prism::CallNode) && call.name == :new && constant_name(call.receiver) == "Entry"
          keywords = call.arguments&.arguments&.last
          changes = keywords.elements.find { |pair| pair.is_a?(Prism::AssocNode) && pair.key.is_a?(Prism::SymbolNode) && pair.key.unescaped == "changes" } if keywords.is_a?(Prism::KeywordHashNode)
          array = unfreeze(changes&.value)
          if array.is_a?(Prism::ArrayNode)
            array.elements.each { |change| inventory_string(change, records, path, warnings) }
            next
          end
        end
        warning(warnings, path, entry, "Changelog entry requires Entry.new with a literal changes array")
      end
    end
  end

  def self.ui_inventory(node, scopes, records, path, warnings)
    return unless path == "lib/game_room_ui.rb" && scopes == ["GameRoomUI"] && node.is_a?(Prism::ConstantWriteNode)
    value = unfreeze(node.value)
    case node.name
    when :VOLUME_LABELS
      if value.is_a?(Prism::HashNode)
        value.elements.each do |pair|
          inventory_string(pair.is_a?(Prism::AssocNode) ? pair.value : pair, records, path, warnings)
        end
      else
        warning(warnings, path, node, "VOLUME_LABELS requires a literal hash of UI labels")
      end
    when :GLOBAL_TIPS
      if value.is_a?(Prism::ArrayNode)
        value.elements.each { |tip| inventory_string(tip, records, path, warnings) }
      else
        warning(warnings, path, node, "GLOBAL_TIPS requires a literal array of UI tips")
      end
    end
  end

  def self.descendants(node)
    return [] unless node
    [node] + node.compact_child_nodes.flat_map { |child| descendants(child) }
  end

  def self.penalty_inventory(node, records, path)
    return [] unless path == "games/ninety_nine.rb" && node.is_a?(Prism::DefNode) && node.name == :penalty_text
    statements = node.body.is_a?(Prism::StatementsNode) ? node.body.body : []
    assignments = statements.select do |statement|
      statement.is_a?(Prism::MultiWriteNode) && statement.rest.nil? && statement.rights.empty? &&
        statement.lefts.all? { |target| target.is_a?(Prism::LocalVariableTargetNode) } &&
        statement.lefts.map(&:name) == [:singular, :plural]
    end
    return [] unless assignments.size == 1
    assignment = assignments.first
    branch = assignment.value
    return [] unless branch.is_a?(Prism::IfNode) && branch.subsequent.is_a?(Prism::ElseNode)
    branches = [branch.statements, branch.subsequent.statements]
    return [] unless branches.all? { |body| body && body.body.size == 1 && body.body.first.is_a?(Prism::ArrayNode) }
    pairs = branches.map { |body| body.body.first }
    return [] unless pairs.all? { |pair| pair.elements.size == 2 && pair.elements.all? { |element| !literal(element).nil? } }
    nodes = descendants(node.body)
    changed = nodes.any? do |part|
      rewritten = part.type.to_s.start_with?("local_variable_") && !part.is_a?(Prism::LocalVariableReadNode) &&
        part.respond_to?(:name) && [:singular, :plural].include?(part.name) && !assignment.lefts.include?(part)
      mutated = part.is_a?(Prism::CallNode) && part.receiver.is_a?(Prism::LocalVariableReadNode) && [:singular, :plural].include?(part.receiver.name)
      rewritten || mutated
    end
    return [] if changed
    calls = nodes.select do |call|
      args = call.is_a?(Prism::CallNode) ? call.arguments&.arguments : nil
      call.is_a?(Prism::CallNode) && call.name == :n_ && args && args.size == 3 &&
        args.first(2).all? { |arg| arg.is_a?(Prism::LocalVariableReadNode) } &&
        args.first(2).map(&:name) == [:singular, :plural] && call.location.start_offset > assignment.location.end_offset
    end
    return [] if calls.empty?
    pairs.each do |pair|
      singular, plural = pair.elements.map { |element| literal(element) }
      references = [pair.location.start_line] + calls.map { |call| call.location.start_line }
      merge_record(records, msgid: singular, msgid_plural: plural, msgctxt: nil,
        references: references.map { |line| "#{path}:#{line}" }, comments: [])
    end
    calls
  end

  def self.changelog_callback(node)
    return [] unless node.is_a?(Prism::CallNode) && [:list_items, :markdown].include?(node.name) && constant_name(node.receiver) == "GameRoomChangelog"
    keywords = node.arguments&.arguments&.last
    return [] unless keywords.is_a?(Prism::KeywordHashNode)
    pair = keywords.elements.find { |item| item.is_a?(Prism::AssocNode) && item.key.is_a?(Prism::SymbolNode) && item.key.unescaped == "translator" }
    translation_callback(pair&.value)
  end

  def self.translation_callback(callback)
    return [] unless (callback.is_a?(Prism::LambdaNode) || callback.is_a?(Prism::BlockNode)) && callback.body.is_a?(Prism::StatementsNode) && callback.body.body.size == 1
    parameters = callback.parameters&.parameters&.requireds
    call = callback.body.body.first
    return [] unless parameters && parameters.size == 1 && call.is_a?(Prism::CallNode) && call.name == :_ && call.receiver.nil?
    args = call.arguments&.arguments
    args && args.size == 1 && args[0].is_a?(Prism::LocalVariableReadNode) && args[0].name == parameters.first.name ? [call] : []
  end

  def self.ui_consumers(node, path, scopes)
    return [] unless node.is_a?(Prism::CallNode)
    argument = node.arguments&.arguments&.first
    if node.name == :_ && node.arguments&.arguments&.size == 1 && argument.is_a?(Prism::CallNode) &&
        argument.name == :fetch && constant_name(argument.receiver) == "GameRoomUI::VOLUME_LABELS" && argument.arguments&.arguments&.size == 1
      return [node]
    end
    if node.name == :map && constant_name(node.receiver) == "GLOBAL_TIPS" && path == "lib/game_room_ui.rb" && scopes.include?("GameRoomUI")
      return translation_callback(node.block)
    end
    []
  end

  def self.forwarder?(node, path, scopes, method)
    (path == "lib/game_rules.rb" && scopes == ["GameRoomRules"] && method == :translate && node.name == :_) ||
      (path == "lib/game_room_localization.rb" && scopes == ["GameRoomLocalization", "Translations"] &&
        [:_, :n_, :p_, :np_].include?(method) && constant_name(node.receiver) == "GameRoomLocalization" && node.name == :translate)
  end

  def self.extract_source(source, path:, warnings: nil)
    records = {}
    resolved_calls = {}
    visit = lambda do |node, scopes, method|
      method = node.name if node.is_a?(Prism::DefNode)
      if node.is_a?(Prism::ModuleNode) || node.is_a?(Prism::ClassNode)
        scopes = scopes + [constant_name(node.constant_path)]
      end
      changelog_inventory(node, scopes, records, path, warnings)
      ui_inventory(node, scopes, records, path, warnings)
      penalty_inventory(node, records, path).each { |call| resolved_calls[call] = true }
      changelog_callback(node).each { |call| resolved_calls[call] = true }
      ui_consumers(node, path, scopes).each { |call| resolved_calls[call] = true }
      if node.is_a?(Prism::CallNode) && !resolved_calls[node] && (arguments = message_arguments(node, scopes))
        value, plural, context = arguments.map { |argument| literal(argument) }
        unresolved = value.nil? || value.empty? || arguments.any? { |argument| argument && literal(argument).nil? }
        if unresolved
          unless forwarder?(node, path, scopes, method)
            warning(warnings, path, node, "#{node.name} requires literal message/context/plural; dynamic source was not extracted")
          end
        else
          contexts = node.name == :_ && scopes.last.to_s.split("::").last == "CatHeadTail" ? ["cat_head_tail", nil] : [context]
          contexts.each do |msgctxt|
            merge_record(records, msgid: value, msgid_plural: plural, msgctxt: msgctxt,
              references: ["#{path}:#{node.location.start_line}"], comments: [])
          end
        end
      end
      node.compact_child_nodes.each { |child| visit.call(child, scopes, method) }
    end
    parsed = Prism.parse(source, filepath: path, encoding: "UTF-8")
    unless parsed.errors.empty?
      details = parsed.errors.map { |error| "#{path}:#{error.location.start_line}: parse error: #{error.message}" }
      raise ArgumentError, details.join("\n")
    end
    visit.call(parsed.value, [], nil)
    records.values
  end
end
