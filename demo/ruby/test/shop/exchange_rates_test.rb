# frozen_string_literal: true

require 'test_helper'

# Not parallelize_me!: WebMock's stub registry is process-global and reset after every test,
# so threads would see (and wipe) each other's stubs.
class ExchangeRatesTest < Minitest::Test
  URL = 'https://api.example.test/v1/rates'
  BODY = { base: 'EUR', date: '2026-10-30', rates: { USD: 1.0832, GBP: 0.8571, JPY: 165.12 } }.to_json

  def setup
    @sleeps = []
    @client = Shop::ExchangeRates.new(api_key: 'secret', sleeper: ->(s) { @sleeps << s })
  end

  def stub_rates(*responses)
    stub_request(:get, URL).with(query: { base: 'EUR' }).to_return(*responses)
  end

  def test_fetches_rates
    stub_rates(status: 200, body: BODY)

    assert_in_delta 1.0832, @client.rates('eur')['USD']
  end

  def test_sends_headers
    stub_rates(status: 200, body: BODY)
    @client.rates

    assert_requested :get, URL, query: { base: 'EUR' },
                                headers: { 'Authorization' => 'Bearer secret', 'Accept' => 'application/json' }, times: 1
  end

  def test_caches
    stub_rates(status: 200, body: BODY)
    3.times { @client.rates }

    assert_requested :get, URL, query: hash_including('base' => 'EUR'), times: 1
  end

  def test_convert
    stub_rates(status: 200, body: BODY)

    assert_equal Shop::Money.parse('108.32 USD'), @client.convert(Shop::Money.parse('100.00 EUR'), to: 'USD')
    assert_equal Rational(1), @client.rate('EUR', 'EUR')
  end

  def test_unknown_currency
    stub_rates(status: 200, body: BODY)

    assert_raises(Shop::ExchangeRates::UnknownCurrency) { @client.rate('EUR', 'XAU') }
  end

  def test_client_errors_are_not_retried
    stub_rates(status: 401, body: 'bad key')
    error = assert_raises(Shop::ExchangeRates::Error) { @client.rates }

    assert_equal 'rates API 401: bad key', error.message
    assert_empty @sleeps
  end

  def test_server_errors_are_retried_with_backoff
    stub_rates({ status: 503 }, { status: 502 }, { status: 200, body: BODY })

    assert_includes @client.rates.keys, 'USD'
    assert_equal [0.2, 0.4], @sleeps
  end

  def test_timeouts_exhaust_retries
    stub_request(:get, URL).with(query: { base: 'EUR' }).to_timeout
    error = assert_raises(Shop::ExchangeRates::Error) { @client.rates }

    assert_match(/after 3 attempts/, error.message)
    assert_equal 2, @sleeps.size
  end

  def test_real_backoff_sleep
    stub_rates({ status: 500 }, { status: 200, body: BODY })
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Shop::ExchangeRates.new(retries: 1).rates

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :>=, 0.2
  end

  def test_invalid_json
    stub_rates(status: 200, body: '<html>')

    assert_raises(Shop::ExchangeRates::Error) { @client.rates }
  end

  def test_net_connect_disabled
    other = Shop::ExchangeRates.new(base_url: 'https://elsewhere.example.test')

    assert_raises(VCR::Errors::UnhandledHTTPRequestError) { other.rates }
    VCR.turned_off { assert_raises(WebMock::NetConnectNotAllowedError) { other.rates } }
  end

  def test_vcr_eur_cassette
    VCR.use_cassette('exchange_rates/eur') do
      assert_in_delta 0.9401, Shop::ExchangeRates.new(api_key: 'test-key').rates['CHF']
    end
  end

  def test_vcr_usd_cassette
    VCR.use_cassette('exchange_rates/usd') do
      converted = Shop::ExchangeRates.new(api_key: 'test-key').convert(Shop::Money.parse('10.00 USD'), to: 'EUR')

      assert_equal Shop::Money.parse('9.23 EUR'), converted
    end
  end

  def test_vcr_rejects_unrecorded_requests
    VCR.use_cassette('exchange_rates/eur') do
      assert_raises(VCR::Errors::UnhandledHTTPRequestError) { Shop::ExchangeRates.new.rates('GBP') }
    end
  end
end
