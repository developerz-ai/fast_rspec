# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module Shop
  # Client for the (fictional) rates API at api.example.test.
  #   GET /v1/rates?base=EUR  -> {"base":"EUR","date":"2026-10-30","rates":{"USD":1.0832,...}}
  class ExchangeRates
    Error = Class.new(Shop::Error)
    UnknownCurrency = Class.new(Error)
    ServerError = Class.new(Error)
    private_constant :ServerError

    DEFAULT_URL = 'https://api.example.test'
    RETRYABLE = [Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET].freeze

    attr_reader :base_url

    def initialize(base_url: DEFAULT_URL, api_key: nil, cache: Cache.new(ttl: 300), retries: 2, backoff: 0.2,
                   sleeper: ->(seconds) { sleep(seconds) })
      @base_url = base_url
      @api_key = api_key
      @cache = cache
      @retries = retries
      @backoff = backoff
      @sleeper = sleeper
    end

    def rates(base = 'EUR')
      base = base.upcase
      @cache.fetch("rates:#{base}") { fetch_rates(base) }
    end

    def rate(from, to)
      return 1r if from == to

      value = rates(from)[to] or raise UnknownCurrency, "no rate #{from} -> #{to}"
      Rational(value.to_s)
    end

    def convert(money, to:)
      Money.new(cents: (money.cents * rate(money.currency, to)).round(half: :up), currency: to)
    end

    private

    def fetch_rates(base)
      body = JSON.parse(get('/v1/rates', base: base))
      raise Error, "unexpected base #{body['base'].inspect}" unless body['base'] == base

      body.fetch('rates').freeze
    rescue JSON::ParserError => e
      raise Error, "invalid JSON from rates API: #{e.message}"
    end

    def get(path, params)
      uri = URI.join(base_url, path)
      uri.query = URI.encode_www_form(params)
      attempts = 0
      begin
        attempts += 1
        response = request(uri)
        raise ServerError, "rates API #{response.code}" if response.is_a?(Net::HTTPServerError)
        raise Error, "rates API #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

        response.body
      rescue ServerError, *RETRYABLE => e
        raise Error, "rates API unavailable after #{attempts} attempts (#{e.message})" if attempts > @retries

        @sleeper.call(@backoff * attempts)
        retry
      end
    end

    def request(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 2, read_timeout: 2) do |http|
        req = Net::HTTP::Get.new(uri)
        req['Accept'] = 'application/json'
        req['Authorization'] = "Bearer #{@api_key}" if @api_key
        http.request(req)
      end
    end
  end
end
