require "rails_helper"

RSpec.describe "Weather" do
  it "shows the forecast", vcr: { cassette_name: "weather/berlin" } do
    get weather_path(city: "Berlin")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Weather in Berlin", "12 °C, Light rain")
  end

  it "serves JSON", vcr: { cassette_name: "weather/tokyo" } do
    get weather_path(city: "Tokyo", format: :json)
    expect(response.parsed_body).to eq("city" => "Tokyo", "temp_c" => 21.0, "summary" => "Clear sky")
  end

  it "degrades gracefully on an outage", vcr: { cassette_name: "weather/outage" } do
    get weather_path(city: "Atlantis")
    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to include("Weather unavailable")
  end

  it "degrades gracefully on a timeout (WebMock)" do
    stub_request(:get, /api\.example\.test/).to_timeout
    get weather_path(city: "Nowhere", format: :json)
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to eq("error" => "weather unavailable")
  end
end
