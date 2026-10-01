class GameRoomTableHistoryExporter
  def initialize(clock: -> { Time.now })
    @clock = clock
  end

  def write(directory, entries)
    content = content_for(entries)
    basename = @clock.call.strftime("Table_history_%Y-%m-%d_%H-%M")
    index = 0
    loop do
      suffix = index == 0 ? "" : "-#{index + 1}"
      path = File.join(directory, "#{basename}#{suffix}.txt")
      begin
        File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::BINARY) do |file|
          file.write(content)
        end
        return path
      rescue Errno::EEXIST
        index += 1
      end
    end
  end

  private

  def content_for(entries)
    lines = entries.to_a.filter_map do |entry|
      text = entry.respond_to?(:text) ? entry.text : entry
      normalized = text.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        .gsub(/\r\n?/, "\n").sub(/\n+\z/, "")
      normalized unless normalized.empty?
    end
    return "" if lines.empty?

    (lines.join("\n") + "\n").gsub("\n", "\r\n")
  end
end
