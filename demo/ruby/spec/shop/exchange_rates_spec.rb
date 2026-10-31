# frozen_string_literal: true

RSpec.describe Shop::ExchangeRates do
  let(:url) { 'https://api.example.test/v1/rates' }
  let(:sleeper) { spy('sleeper') }
  let(:body) { { base: 'EUR', date: '2026-10-30', rates: { USD: 1.0832, GBP: 0.8571, JPY: 165.12 } }.to_json }

  subject(:client) { described_class.new(api_key: 'secret', sleeper: sleeper) }

  context 'with WebMock stubs' do
    before do
      stub_request(:get, url).with(query: { base: 'EUR' })
                             .to_return(status: 200, body: body, headers: { 'Content-Type' => 'application/json' })
    end

    it 'fetches rates for a base currency' do
      expect(client.rates('eur')).to include('USD' => 1.0832, 'GBP' => 0.8571)
    end

    it 'sends the api key and accept header' do
      client.rates
      expect(
        a_request(:get, url).with(query: hash_including('base' => 'EUR'),
                                  headers: { 'Authorization' => 'Bearer secret', 'Accept' => 'application/json' })
      ).to have_been_made.once
    end

    it 'caches responses' do
      3.times { client.rates('EUR') }
      expect(WebMock).to have_requested(:get, url).with(query: { base: 'EUR' }).once
    end

    it 'returns exact rational rates' do
      expect(client.rate('EUR', 'USD')).to eq(Rational('1.0832'))
      expect(client.rate('EUR', 'EUR')).to eq(1)
    end

    it 'converts money' do
      expect(client.convert(Shop::Money.parse('100.00 EUR'), to: 'USD')).to eq(Shop::Money.parse('108.32 USD'))
      expect(client.convert(Shop::Money.parse('0.01 EUR'), to: 'JPY')).to have_attributes(cents: 165, currency: 'JPY')
    end

    it 'raises for currencies the API does not know' do
      expect { client.rate('EUR', 'XAU') }.to raise_error(described_class::UnknownCurrency, 'no rate EUR -> XAU')
    end
  end

  describe 'failures' do
    it 'raises on 4xx without retrying' do
      stub_request(:get, url).with(query: { base: 'EUR' }).to_return(status: 401, body: 'bad key')
      expect { client.rates }.to raise_error(described_class::Error, 'rates API 401: bad key')
      expect(sleeper).not_to have_received(:call)
    end

    it 'retries 5xx with linear backoff, then succeeds' do
      stub_request(:get, url).with(query: { base: 'EUR' })
                             .to_return({ status: 503 }, { status: 502 }, { status: 200, body: body })
      expect(client.rates).to include('USD')
      expect(sleeper).to have_received(:call).with(0.2).ordered
      expect(sleeper).to have_received(:call).with(0.4).ordered
    end

    it 'gives up after the retry budget on timeouts' do
      stub_request(:get, url).with(query: { base: 'EUR' }).to_timeout
      expect { client.rates }.to raise_error(described_class::Error, /unavailable after 3 attempts/)
      expect(sleeper).to have_received(:call).twice
    end

    it 'really sleeps between attempts by default', :slow do
      stub_request(:get, url).with(query: { base: 'EUR' }).to_return({ status: 500 }, { status: 200, body: body })
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      described_class.new(retries: 1).rates
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be >= 0.2
    end

    it 'wraps invalid JSON' do
      stub_request(:get, url).with(query: { base: 'EUR' }).to_return(status: 200, body: '<html>')
      expect { client.rates }.to raise_error(described_class::Error, /invalid JSON/)
    end

    it 'rejects a response for the wrong base' do
      stub_request(:get, url).with(query: { base: 'EUR' }).to_return(status: 200, body: { base: 'USD', rates: {} }.to_json)
      expect { client.rates }.to raise_error(described_class::Error, 'unexpected base "USD"')
    end

    it 'never reaches the real network (VCR guards first, WebMock underneath)' do
      other = described_class.new(base_url: 'https://elsewhere.example.test')
      expect { other.rates }.to raise_error(VCR::Errors::UnhandledHTTPRequestError)
      VCR.turned_off do
        expect { other.rates }.to raise_error(WebMock::NetConnectNotAllowedError)
      end
    end
  end

  describe 'recorded with VCR' do
    subject(:client) { described_class.new(api_key: 'test-key') }

    it 'replays EUR rates', vcr: { cassette_name: 'exchange_rates/eur' } do
      expect(client.rates('EUR')).to include('USD' => 1.0832, 'CHF' => 0.9401)
    end

    it 'replays USD rates', vcr: { cassette_name: 'exchange_rates/usd' } do
      expect(client.convert(Shop::Money.parse('10.00 USD'), to: 'EUR')).to eq(Shop::Money.parse('9.23 EUR'))
    end

    it 'refuses requests the cassette does not contain' do
      VCR.use_cassette('exchange_rates/eur') do
        expect { client.rates('GBP') }.to raise_error(VCR::Errors::UnhandledHTTPRequestError)
      end
    end
  end
end
