require "rails_helper"

RSpec.describe RefreshWeatherJob do
  let(:user) { create(:user, city: "Berlin") }

  it "stores the forecast summary (rspec-mocks double)" do
    client = instance_double(WeatherClient)
    forecast = WeatherClient::Forecast.new(city: "Berlin", temp_c: 12.4, summary: "Light rain")
    allow(client).to receive(:current).with("Berlin").and_return(forecast)

    described_class.perform_now(user, client: client)

    expect(user.reload.weather_summary).to eq("12 °C, Light rain")
    expect(client).to have_received(:current).once
  end

  it "uses the real client against a cassette", vcr: { cassette_name: "weather/berlin" } do
    described_class.perform_now(user)
    expect(user.reload.weather_summary).to eq("12 °C, Light rain")
  end

  it "skips users without a city" do
    user = create(:user, :without_city)
    expect_any_instance_of(WeatherClient).not_to receive(:current)
    described_class.perform_now(user)
  end

  it "retries on API errors" do
    allow_any_instance_of(WeatherClient).to receive(:current).and_raise(WeatherClient::Error, "down")
    expect { described_class.perform_now(user) }.to have_enqueued_job(described_class).on_queue("low")
  end

  it "is enqueued on the low queue" do
    expect { described_class.perform_later(user) }.to have_enqueued_job(described_class).on_queue("low")
  end
end
