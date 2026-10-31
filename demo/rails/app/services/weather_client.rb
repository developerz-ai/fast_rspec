require "net/http"

# Tiny JSON client for a (fake) third-party weather API. Tests never hit the network:
# WebMock stubs it, or VCR replays hand-written cassettes for api.example.test.
class WeatherClient
  class Error < StandardError; end

  Forecast = Data.define(:city, :temp_c, :summary) do
    def to_s = "#{temp_c.round} °C, #{summary}"
  end

  DEFAULT_URL = "https://api.example.test"

  def initialize(base_url: ENV.fetch("WEATHER_API_URL", DEFAULT_URL), api_key: ENV.fetch("WEATHER_API_KEY", "demo-key"), timeout: 2)
    @base_url = base_url
    @api_key = api_key
    @timeout = timeout
  end

  def current(city)
    raise ArgumentError, "city is required" if city.blank?

    uri = URI.join(@base_url, "/v1/current")
    uri.query = URI.encode_www_form(city: city, key: @api_key)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                   open_timeout: @timeout, read_timeout: @timeout) do |http|
      http.get(uri.request_uri, "Accept" => "application/json")
    end
    raise Error, "weather API returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    Forecast.new(city: data.fetch("city"), temp_c: Float(data.fetch("temp_c")), summary: data.fetch("summary"))
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, JSON::ParserError, KeyError => e
    raise Error, "weather API failed: #{e.class}"
  end
end
