require "test_helper"

class WeatherTest < ActionDispatch::IntegrationTest
  test "shows the forecast" do
    VCR.use_cassette("weather/berlin") { get weather_path(city: "Berlin") }
    assert_response :success
    assert_select "h1", "Weather in Berlin"
    assert_select "#forecast", "12 °C, Light rain"
  end

  test "serves JSON" do
    VCR.use_cassette("weather/tokyo") { get weather_path(city: "Tokyo", format: :json) }
    assert_equal({ "city" => "Tokyo", "temp_c" => 21.0, "summary" => "Clear sky" }, response.parsed_body)
  end

  test "degrades gracefully on an outage" do
    VCR.use_cassette("weather/outage") { get weather_path(city: "Atlantis") }
    assert_response :service_unavailable
    assert_select "h1", "Weather unavailable"
  end

  test "degrades gracefully on a timeout (WebMock)" do
    stub_request(:get, /api\.example\.test/).to_timeout
    get weather_path(city: "Nowhere", format: :json)
    assert_response :service_unavailable
    assert_equal({ "error" => "weather unavailable" }, response.parsed_body)
  end
end
