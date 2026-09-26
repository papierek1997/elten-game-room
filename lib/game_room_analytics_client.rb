require "uri"

class GameRoomAnalyticsClient
  REQUEST_TIMEOUT = 5

  def initialize(client, app_uuid:, tables:, error:, cancellation_token: nil)
    @client, @error = client, error
    parameters = client.respond_to?(:api_data) ? client.method(:api_data).parameters : []
    @options = {timeout: REQUEST_TIMEOUT, cancellation_token: cancellation_token}.select do |key, _|
      parameters.any? { |kind, name| kind == :keyrest || ([:key, :keyreq].include?(kind) && name == key) }
    end.freeze
    root = "/api/v1/apps/#{URI.encode_www_form_component(app_uuid).gsub('*', '%2A')}/tables"
    @rows_paths = tables.map { |table| "#{root}/#{table}/rows" }.freeze
  end

  def api_data(method, path, params = nil)
    data = @client.api_data(method, path, params, **@options)
    rows_query = (method == "GET" && @rows_paths.include?(path)) ||
      (method == "POST" && @rows_paths.any? { |rows| path == "#{rows}/query" })
    if rows_query && !(data.is_a?(Hash) && data["rows"].is_a?(Array))
      raise @error, "Invalid analytics rows response"
    end
    data
  end
end
