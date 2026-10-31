require "test_helper"

class RefreshWeatherJobTest < ActiveJob::TestCase
  setup { @user = create(:user, city: "Berlin") }

  test "stores the forecast summary (Minitest::Mock)" do
    client = Minitest::Mock.new
    client.expect(:current, WeatherClient::Forecast.new(city: "Berlin", temp_c: 12.4, summary: "Light rain"), [ "Berlin" ])

    RefreshWeatherJob.perform_now(@user, client: client)

    assert_equal "12 °C, Light rain", @user.reload.weather_summary
    client.verify
  end

  test "uses the real client against a cassette" do
    VCR.use_cassette("weather/berlin") { RefreshWeatherJob.perform_now(@user) }
    assert_equal "12 °C, Light rain", @user.reload.weather_summary
  end

  test "skips users without a city" do
    user = create(:user, :without_city)
    WeatherClient.stub(:new, -> { flunk "should not build a client" }) do
      RefreshWeatherJob.perform_now(user)
    end
    assert_nil user.reload.weather_summary
  end

  test "retries on API errors" do
    failing = Object.new
    def failing.current(_city) = raise(WeatherClient::Error, "down")
    WeatherClient.stub(:new, failing) do
      assert_enqueued_with(job: RefreshWeatherJob, queue: "low") { RefreshWeatherJob.perform_now(@user) }
    end
  end

  test "is enqueued on the low queue" do
    assert_enqueued_with(job: RefreshWeatherJob, queue: "low") { RefreshWeatherJob.perform_later(@user) }
  end
end
