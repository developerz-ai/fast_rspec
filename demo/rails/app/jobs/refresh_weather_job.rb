class RefreshWeatherJob < ApplicationJob
  queue_as :low

  retry_on WeatherClient::Error, wait: 30.seconds, attempts: 3

  def perform(user, client: nil)
    return if user.city.blank?

    client ||= WeatherClient.new
    user.update!(weather_summary: client.current(user.city).to_s)
  end
end
