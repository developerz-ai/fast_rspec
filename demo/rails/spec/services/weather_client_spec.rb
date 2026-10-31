require "rails_helper"

RSpec.describe WeatherClient do
  subject(:client) { described_class.new }

  let(:endpoint) { %r{\Ahttps://api\.example\.test/v1/current} }

  describe "with WebMock stubs" do
    it "parses a forecast" do
      stub_request(:get, "https://api.example.test/v1/current")
        .with(query: { city: "Oslo", key: "demo-key" }, headers: { "Accept" => "application/json" })
        .to_return(status: 200, body: { city: "Oslo", temp_c: -3.2, summary: "Snow" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      forecast = client.current("Oslo")

      expect(forecast).to have_attributes(city: "Oslo", temp_c: -3.2, summary: "Snow")
      expect(forecast.to_s).to eq("-3 °C, Snow")
      expect(a_request(:get, endpoint).with(query: hash_including(city: "Oslo"))).to have_been_made.once
    end

    it "raises on a server error" do
      stub_request(:get, endpoint).to_return(status: 500, body: "boom")
      expect { client.current("Oslo") }.to raise_error(WeatherClient::Error, /500/)
    end

    it "raises on a timeout" do
      stub_request(:get, endpoint).to_timeout
      expect { client.current("Oslo") }.to raise_error(WeatherClient::Error, /OpenTimeout/)
    end

    it "raises on malformed JSON" do
      stub_request(:get, endpoint).to_return(status: 200, body: "<html>")
      expect { client.current("Oslo") }.to raise_error(WeatherClient::Error, /ParserError/)
    end

    it "raises on missing fields" do
      stub_request(:get, endpoint).to_return(status: 200, body: { city: "Oslo" }.to_json)
      expect { client.current("Oslo") }.to raise_error(WeatherClient::Error, /KeyError/)
    end

    it "sends the configured API key" do
      stub = stub_request(:get, endpoint).with(query: hash_including(key: "s3cret"))
                                         .to_return(body: { city: "X", temp_c: 1, summary: "ok" }.to_json)
      described_class.new(api_key: "s3cret").current("X")
      expect(stub).to have_been_requested
    end

    it "rejects a blank city without any HTTP" do
      expect { client.current("") }.to raise_error(ArgumentError)
      expect(a_request(:any, endpoint)).not_to have_been_made
    end

    it "is slow-ish when the upstream is slow (deliberately)" do
      stub_request(:get, endpoint).to_return(lambda { |_request|
        sleep 0.2
        { status: 200, body: { city: "Slow", temp_c: 5, summary: "Fog" }.to_json }
      })
      expect(client.current("Slow").summary).to eq("Fog")
    end
  end

  describe "with VCR cassettes" do
    it "replays Berlin", vcr: { cassette_name: "weather/berlin" } do
      expect(client.current("Berlin")).to have_attributes(city: "Berlin", temp_c: 12.4, summary: "Light rain")
    end

    it "replays a multi-request cassette" do
      VCR.use_cassette("weather/two_cities") do
        expect(client.current("Berlin").summary).to eq("Light rain")
        expect(client.current("London").summary).to eq("Overcast")
      end
    end

    it "replays an outage as an error", vcr: { cassette_name: "weather/outage" } do
      expect { client.current("Atlantis") }.to raise_error(WeatherClient::Error, /503/)
    end

    it "refuses requests the cassette doesn't know" do
      VCR.use_cassette("weather/berlin") do
        expect { client.current("Paris") }.to raise_error(VCR::Errors::UnhandledHTTPRequestError)
      end
    end
  end

  it "blocks real network access" do
    VCR.turned_off do
      expect { Net::HTTP.get(URI("https://www.ruby-lang.org/")) }.to raise_error(WebMock::NetConnectNotAllowedError)
    end
  end
end
