require 'prism'
require 'json'

module GameRoomQuality
  ROOT = File.expand_path('../..', __dir__)
  BASELINE = File.expand_path('../fixtures/quality_baseline.json', __dir__)
  EXCLUDED = %r{\A(?:content/|lib/vendor/|games/krowa_support/noun_data\.rb|games/generated/)}
  MODEL_UI_CALLS = %i[loop_update speak speech_wait alert input_text selector].freeze
  # These are presentation adapters, not replay/action models. Keep every
  # other check active for them, including syntax and runtime dependencies.
  UI_ADAPTERS = %w[games/krowa_support/client.rb games/krowa_support/leaderboards.rb].freeze
  module_function

  def walk(node, &block)
    yield node
    node.compact_child_nodes.each { |child| walk(child, &block) }
  end

  def inspect_source(path, source)
    parsed = Prism.parse(source)
    failures = parsed.errors.map { |error| {rule: 'syntax', file: path, line: error.location.start_line, detail: error.message} }
    walk(parsed.value) do |node|
      rule = detail = nil
      if node.is_a?(Prism::DefNode) && node.location.end_line - node.location.start_line + 1 > 80
        rule, detail = 'long_method', "#{node.name}:#{node.location.end_line - node.location.start_line + 1}"
      elsif path.start_with?('games/') && !UI_ADAPTERS.include?(path) && node.is_a?(Prism::CallNode) && MODEL_UI_CALLS.include?(node.name)
        rule, detail = 'model_ui', node.location.slice
      elsif node.is_a?(Prism::CallNode) && [:shuffle, :shuffle!].include?(node.name) &&
          !%w[GameRoomRandom GameRoomDominoTiles].include?(node.receiver&.location&.slice)
        rule, detail = 'host_shuffle', node.location.slice
      end
      failures << {rule: rule, file: path, line: node.location.start_line, detail: detail} if rule
    end
    source.lines.each_with_index do |line, index|
      if line.match?(%r{require_relative\s+["'].*(?:/test/|/tools/)})
        failures << {rule: 'runtime_dependency', file: path, line: index + 1, detail: line.strip}
      end
    end
    failures
  end

  def findings(root: ROOT)
    paths = Dir.chdir(root) { ['__app.rb', *Dir['{games,lib}/**/*.rb']].reject { |path| path.match?(EXCLUDED) }.sort }
    paths.flat_map { |path| inspect_source(path, File.read(File.join(root, path), encoding: 'UTF-8')) }
  end

  def key(finding)
    # Line movement alone does not hide or introduce debt. A longer method or
    # a new dependency is a new finding and must be addressed explicitly.
    [finding.fetch(:file), finding.fetch(:rule), finding.fetch(:detail)].join('|')
  end

  def new_findings(findings, baseline)
    remaining = baseline.dup
    findings.reject do |finding|
      identity = key(finding)
      if finding[:rule] == 'long_method'
        prefix, length = identity.rpartition(':').values_at(0, 2)
        identity = remaining.keys.select do |candidate|
          previous, size = candidate.rpartition(':').values_at(0, 2)
          previous == prefix && size.to_i >= length.to_i && remaining[candidate] > 0
        end.min_by { |candidate| candidate.rpartition(':').last.to_i } || identity
      end
      count = remaining.fetch(identity, 0)
      remaining[identity] = count - 1 if count > 0
      count > 0
    end
  end
end
