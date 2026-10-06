require "zlib"
require_relative "saved_game_archive"

# One complete private resource per archive; the list contains only its small
# manifest. All calls belong in Tasks.run. No local copy/fallback is written.
class AccountSavedGames < GameRoomSavedGameArchive
  PREFIX = "game-save-".freeze
  MAX_BYTES = 16 * 1024 * 1024

  def initialize(program, owner:, resources: nil)
    super(program, owner: owner)
    unless resources || (defined?(EltenLink::Apps) && EltenLink::Apps.respond_to?(:private_resources))
      raise ArgumentError, "Account game saves require ELTEN 3.0.4 or newer"
    end
    @resources = resources || EltenLink::Apps.private_resources(EltenLink::Client.new, program.server_app_uuid)
  end

  def list
    resources.filter_map { |resource| manifest(resource) }.sort_by { |row| -row["saved_at"] }
  end

  def fetch(id)
    row = list.find { |item| item["id"] == id.to_s }
    row && read_archive(row)
  end

  def persist(row)
    json = JSON.generate(row)
    raise IOError, "The saved game is too large" if json.bytesize > MAX_BYTES
    data = Zlib::Deflate.deflate(json)
    raise IOError, "The saved game is too large" if data.bytesize > MAX_BYTES
    resources # Refresh the quota and usage together before uploading.
    limit = @resources.max_private_resources_bytes_per_user.to_i
    raise IOError, "There is not enough private storage for this game" if limit <= 0 || @resources.used_size.to_i + data.bytesize > limit
    name = "#{PREFIX}#{row.fetch('id')}.json.deflate"
    meta = row.slice("id", "owner", "game", "saved_at", "players").merge(
      "format" => 1, "bytes" => json.bytesize, "sha256" => Digest::SHA256.hexdigest(json))
    encoded = JSON.generate(meta)
    raise IOError, "The saved game manifest is too large" if encoded.bytesize > 1024
    begin
      stored = @resources.upload(name, data, meta: encoded, timeout: 15)
    rescue StandardError => error
      # A lost reply can follow a successful upload. Reconcile the immutable
      # UUID, never blindly create a second archive or close an unverified table.
      stored = resources.find { |item| item.resource == name && item.meta == encoded }
      raise error unless stored
    end
    verified = manifest(stored)
    raise IOError, "The server did not confirm the saved game" unless verified && read_archive(verified) == row
    row
  end

  def delete(id)
    row = list.find { |item| item["id"] == id.to_s }
    return false unless row
    begin
      @resources.delete(row.fetch("__resource_id"), timeout: 15)
    rescue StandardError => error
      # A lost acknowledgement is not a reason to delete anything else or to
      # report success without checking that this exact archive disappeared.
      raise error if list.any? { |item| item["id"] == id.to_s }
      return true
    end
    raise IOError, "The saved game removal was not confirmed" if list.any? { |item| item["id"] == id.to_s }
    true
  end

  private

  def resources
    @resources.list(timeout: 15)
  end

  def manifest(resource)
    return nil unless resource.resource.to_s.start_with?(PREFIX)
    row = JSON.parse(resource.meta.to_s)
    return nil unless row.is_a?(Hash) && row["format"] == 1 &&
      row["id"].to_s.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/) &&
      resource.resource == "#{PREFIX}#{row['id']}.json.deflate" &&
      GameRoomParticipants.same?(row["owner"], @owner) &&
      GameRoomParticipants.same?(resource.uploader, @owner) &&
      row["game"].is_a?(String) && row["saved_at"].is_a?(Integer) && row["saved_at"].positive? &&
      GameRoomTableControl.valid_players?(row["players"]) &&
      row["bytes"].is_a?(Integer) && row["bytes"].between?(1, MAX_BYTES) &&
      row["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/) && resource.filesize.to_i.between?(1, MAX_BYTES)
    row.merge("__resource_id" => resource.id)
  rescue JSON::ParserError
    nil
  end

  def read_archive(manifest)
    compressed = @resources.download(manifest.fetch("__resource_id"), timeout: 15)
    raise IOError, "Invalid saved game download" unless compressed.is_a?(String) && compressed.bytesize <= MAX_BYTES
    inflater, json = Zlib::Inflate.new, String.new(encoding: Encoding::BINARY)
    begin
      inflater.inflate(compressed) do |chunk|
        raise IOError, "Saved game decompression limit exceeded" if json.bytesize + chunk.bytesize > manifest.fetch("bytes")
        json << chunk
      end
      raise IOError, "Incomplete saved game" unless inflater.finished? && inflater.total_in == compressed.bytesize && json.bytesize == manifest["bytes"]
    ensure
      inflater.close
    end
    raise IOError, "Saved game checksum mismatch" unless Digest::SHA256.hexdigest(json) == manifest["sha256"]
    row = JSON.parse(json.force_encoding(Encoding::UTF_8))
    raise IOError, "Saved game manifest mismatch" unless row.is_a?(Hash) &&
      row.slice("id", "owner", "game", "saved_at", "players") == manifest.slice("id", "owner", "game", "saved_at", "players") &&
      row["checksum"] == checksum(row)
    row
  rescue JSON::ParserError, Zlib::Error
    raise IOError, "Invalid saved game data"
  end
end
