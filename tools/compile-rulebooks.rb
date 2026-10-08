require 'json'
require 'fileutils'
require 'optparse'

module GameRoomRulebookCompiler
  ROOT = File.expand_path('..', __dir__)
  module_function

  def render(book, entry, input_name, localized_books = {})
    sections = book.fetch('sections').map do |section|
      id = section.fetch('id')
      raise "Invalid section ID: #{id}" unless id.match?(/\A[a-z0-9_]+\z/)
      strings = [section.fetch('title'), *section.fetch('paragraphs')].map { |pair| pair.fetch('en') }
      raise "Empty rule text in #{input_name}" if strings.any? { |text| text.strip.empty? }
      "          rule_section(:#{id}, " + strings.map { |text| "GameRoomRules.translate(#{text.dump})" }.join(",\n            ") + ')'
    end
    sections.insert(sections.length - 1, '          board_profile_rules') if book['preserve_board_profiles']
    localized_method = if localized_books.empty?
      ''
    else
      branches = localized_books.sort.map do |language, localized|
        ids = localized.fetch('sections').map { |section| section.fetch('id') }
        raise "Invalid localized chapters in #{input_name}/#{language}" unless ids.uniq == ids && ids.last == 'controls'
        lines = localized.fetch('sections').map do |section|
          id = section.fetch('id')
          raise "Invalid section ID: #{id}" unless id.match?(/\A[a-z0-9_]+\z/)
          strings = [section.fetch('title'), *section.fetch('paragraphs')].map { |pair| pair.fetch(language) }
          raise "Empty localized rule text in #{input_name}" if strings.any? { |text| !text.is_a?(String) || text.strip.empty? }
          "            rule_section(:#{id}, " + strings.map(&:dump).join(",\n              ") + ')'
        end
        "        when #{language.dump}\n          [\n#{lines.join(",\n")}\n          ]"
      end
      "\n      def localized_rule_sections\n        case GameRoomLocalization.primary_language\n#{branches.join("\n")}\n        end\n      end\n"
    end
    text = <<~RUBY
      # Generated from tools/data/rulebooks/#{input_name}; run tools/compile-rulebooks.rb.
      module GameRoomGames
        #{entry.fetch('kind')} #{entry.fetch('class')}
          module GeneratedRulebook
            private

            def generated_rule_sections
              [
      #{sections.join(",\n")}
              ]
            end
          end
          include GeneratedRulebook
        end
      end
    RUBY
    text.sub("    end\n    include GeneratedRulebook\n", "#{localized_method}    end\n    include GeneratedRulebook\n")
  end

  def outputs(root)
    manifest = JSON.parse(File.read(File.join(root, 'tools/rulebook_sources.json'), encoding: 'UTF-8'))
    inputs = Dir.glob('*.json', base: File.join(root, 'tools/data/rulebooks')).sort
    raise 'Rulebook source manifest is incomplete' unless inputs == manifest.keys.sort
    localized = Hash.new { |books, name| books[name] = {} }
    Dir.glob('*/*.json', base: File.join(root, 'tools/data/rulebooks')).sort.each do |relative|
      language, name = relative.split('/')
      raise "Invalid localized rulebook: #{relative}" unless language.match?(/\A[A-Z]{2}\z/) && manifest.key?(name)
      book = JSON.parse(File.read(File.join(root, 'tools/data/rulebooks', relative), encoding: 'UTF-8'))
      raise "Source mismatch: #{relative}" unless book.fetch('source') == manifest.fetch(name).fetch('source')
      localized[name][language.downcase] = book
    end
    inputs.each_with_object({}) do |name, generated|
      entry = manifest.fetch(name)
      book = JSON.parse(File.read(File.join(root, 'tools/data/rulebooks', name), encoding: 'UTF-8'))
      raise "Source mismatch: #{name}" unless book.fetch('source') == entry.fetch('source')
      output = entry.fetch('output')
      raise "Unsafe rulebook output: #{output}" unless output.match?(%r{\Agames/generated/rulebooks/[a-z0-9_]+\.rb\z})
      raise ArgumentError, "Rulebooks share an output: #{output}" if generated.key?(output)
      raise 'Invalid game class' unless entry.fetch('class').match?(/\A[A-Z][A-Za-z0-9]*\z/)
      raise 'Invalid game container' unless %w[class module].include?(entry.fetch('kind'))
      generated[output] = render(book, entry, name, localized[name])
    end
  end

  def run(root: ROOT, check: false)
    changed = []
    outputs(root).each do |relative, text|
      path = File.join(root, relative)
      next if File.file?(path) && File.binread(path) == text.b
      changed << relative
      next if check
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, text)
    end
    changed
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |parser|
    parser.on('--check') { options[:check] = true }
    parser.on('--root DIRECTORY') { |value| options[:root] = File.expand_path(value) }
  end.parse!
  abort 'Unexpected arguments' unless ARGV.empty?
  changed = GameRoomRulebookCompiler.run(**options)
  abort "Stale generated rulebooks: #{changed.join(', ')}" if options[:check] && !changed.empty?
  puts "Rulebooks: #{changed.length} #{options[:check] ? 'stale' : 'updated'}; maintained models were not modified."
end
