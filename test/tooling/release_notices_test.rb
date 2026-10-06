require "json"

root = File.expand_path("../..", __dir__)
verify_notices = lambda do |read|
  notices = read.call("THIRD_PARTY_NOTICES.md").force_encoding("UTF-8")
  sections = [
    "1000 mil (Mille Bornes)", "Audio Ball", "Audio Ball — pakiet Audiodisc i zatrzymanie piłki",
    "Wcześniejsze zasoby", "Powiadomienie o nowym stole", "Cat, head, tail",
    "Dźwięki kostek Domino i Mexican Train", "Ponowne tasowanie kart",
    "Dodatkowe kroki debla i brzęczyk UNO", "Nowe dźwięki Statków", "Krowa — słownik i nagrania"
  ]
  headings = notices.lines.map(&:strip)
  sections.each do |section|
    raise "Missing or duplicated attribution section: #{section}" unless headings.count("### #{section}") == 1
  end
  manifest = JSON.parse(read.call("manifest.json"))
  manifest.fetch("required_assets").fetch("sounds").grep(/\Amille_/).each do |name|
    raise "New sound has no attribution: #{name}" unless notices.include?("Audio/#{name}.opus")
  end
  %w[CC0-1.0 CC-BY-3.0 CC-BY-4.0].each do |license|
    path = "LICENSES/#{license}.txt"
    raise "License link missing: #{path}" unless notices.include?(path)
    raise "Full license missing: #{path}" unless read.call(path).bytesize > 1000
  end
end

if ARGV.first
  require "zip"
  Zip::File.open(ARGV.fetch(0)) { |archive| verify_notices.call(->(path) { archive.read(path) }) }
else
  verify_notices.call(->(path) { File.binread(File.join(root, path)) })
end
puts "PASS release notices: prior game attributions preserved, all Mille Bornes sounds credited, full license texts included"
