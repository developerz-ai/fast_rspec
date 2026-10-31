class WeatherController < ApplicationController
  def show
    @city = params.fetch(:city, "Berlin")
    @forecast = WeatherClient.new.current(@city)
    respond_to do |format|
      format.html
      format.json { render json: @forecast.to_h }
    end
  rescue WeatherClient::Error
    respond_to do |format|
      format.html { render :unavailable, status: :service_unavailable }
      format.json { render json: { error: "weather unavailable" }, status: :service_unavailable }
    end
  end
end
