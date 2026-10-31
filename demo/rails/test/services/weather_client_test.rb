require "test_helper"

class WeatherClientTest < ActiveSupport::TestCase
  ENDPOINT = %r{\Ahttps://api\.example\.test/v1/current}

  setup { @client = WeatherClient.new }

  context "with WebMock stubs" do
    should "parse a forecast" do
      stub_request(:get, "https://api.example.test/v1/current")
        .with(query: { city: "Oslo", key: "demo-key" }, headers: { "Accept" => "application/json" })
        .to_return(status: 200, body: { city: "Oslo", temp_c: -3.2, summary: "Snow" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      forecast = @client.current("Oslo")

      assert_equal [ "Oslo", -3.2, "Snow" ], [ forecast.city, forecast.temp_c, forecast.summary ]
      assert_equal "-3 °C, Snow", forecast.to_s
      assert_requested :get, ENDPOINT, times: 1
    end

    should "raise on a server error" do
      stub_request(:get, ENDPOINT).to_return(status: 500, body: "boom")
      error = assert_raises(WeatherClient::Error) { @client.current("Oslo") }
      assert_match(/500/, error.message)
    end

    should "raise on a timeout" do
      stub_request(:get, ENDPOINT).to_timeout
      assert_raises(WeatherClient::Error) { @client.current("Oslo") }
    end

    should "raise on malformed JSON" do
      stub_request(:get, ENDPOINT).to_return(status: 200, body: "<html>")
      assert_raises(WeatherClient::Error) { @client.current("Oslo") }
    end

    should "raise on missing fields" do
      stub_request(:get, ENDPOINT).to_return(status: 200, body: { city: "Oslo" }.to_json)
      assert_raises(WeatherClient::Error) { @client.current("Oslo") }
    end

    should "send the configured API key" do
      stub_request(:get, ENDPOINT).with(query: hash_including(key: "s3cret"))
                                  .to_return(body: { city: "X", temp_c: 1, summary: "ok" }.to_json)
      WeatherClient.new(api_key: "s3cret").current("X")
      assert_requested :get, ENDPOINT, query: hash_including(key: "s3cret")
    end

    should "reject a blank city without any HTTP" do
      assert_raises(ArgumentError) { @client.current("") }
      assert_not_requested :any, ENDPOINT
    end

    should "be slow-ish when the upstream is slow (deliberately)" do
      stub_request(:get, ENDPOINT).to_return(lambda { |_request|
        sleep 0.2
        { status: 200, body: { city: "Slow", temp_c: 5, summary: "Fog" }.to_json }
      })
      assert_equal "Fog", @client.current("Slow").summary
    end
  end

  context "with VCR cassettes" do
    should "replay Berlin" do
      VCR.use_cassette("weather/berlin") do
        forecast = @client.current("Berlin")
        assert_equal [ "Berlin", 12.4, "Light rain" ], [ forecast.city, forecast.temp_c, forecast.summary ]
      end
    end

    should "replay a multi-request cassette" do
      VCR.use_cassette("weather/two_cities") do
        assert_equal "Light rain", @client.current("Berlin").summary
        assert_equal "Overcast", @client.current("London").summary
      end
    end

    should "replay an outage as an error" do
      VCR.use_cassette("weather/outage") do
        assert_raises(WeatherClient::Error) { @client.current("Atlantis") }
      end
    end

    should "refuse requests the cassette doesn't know" do
      VCR.use_cassette("weather/berlin") do
        assert_raises(VCR::Errors::UnhandledHTTPRequestError) { @client.current("Paris") }
      end
    end
  end

  test "real network access is blocked" do
    VCR.turned_off do
      assert_raises(WebMock::NetConnectNotAllowedError) { Net::HTTP.get(URI("https://www.ruby-lang.org/")) }
    end
  end
end
