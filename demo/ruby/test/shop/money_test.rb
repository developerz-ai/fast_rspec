# frozen_string_literal: true

require 'test_helper'

describe Shop::Money do
  parallelize_me!

  let(:money) { Shop::Money.new(cents: 1250, currency: 'EUR') }

  subject { money }

  describe '.parse' do
    { '12.50 EUR' => 1250, '12 EUR' => 1200, '-0.99 EUR' => -99, '  7.00 EUR ' => 700 }.each do |text, cents|
      it "parses #{text.inspect}" do
        _(Shop::Money.parse(text).cents).must_equal cents
      end
    end

    it 'rejects garbage' do
      err = _ { Shop::Money.parse('twelve euros') }.must_raise Shop::Money::ParseError
      _(err.message).must_match(/cannot parse money/)
    end
  end

  describe 'value semantics' do
    it 'is frozen' do
      _(subject).must_be :frozen?
    end

    it 'equals a twin and dedups' do
      twin = Shop::Money.new(cents: 1250, currency: 'EUR')
      _(subject).must_equal twin
      _([subject, twin].uniq.size).must_equal 1
    end

    it 'validates construction' do
      _ { Shop::Money.new(cents: 1.5, currency: 'EUR') }.must_raise ArgumentError
      _ { Shop::Money.new(cents: 1, currency: 'eur') }.must_raise ArgumentError
    end
  end

  describe 'arithmetic' do
    let(:other) { build(:money, cents: 250) }

    it 'adds' do
      _(money + other).must_equal build(:money, cents: 1500)
    end

    it 'subtracts and negates' do
      _((money - other).cents).must_equal 1000
      _((-money).cents).must_equal(-1250)
    end

    it 'refuses mixed currencies' do
      _ { money + build(:money, :usd) }.must_raise Shop::Money::CurrencyMismatch
    end

    it 'rounds half up when multiplying' do
      _((build(:money, cents: 105) * 0.5).cents).must_equal 53
      _((build(:money, cents: -105) * 0.5).cents).must_equal(-53)
    end
  end

  describe '#allocate' do
    it 'never loses a cent' do
      _(build(:money, cents: 1000).allocate(3).map(&:cents)).must_equal [334, 333, 333]
    end

    it 'honours ratios' do
      _(build(:money, cents: 100).allocate([1, 3]).map(&:cents)).must_equal [25, 75]
    end

    it 'is symmetric for negatives' do
      _(build(:money, cents: -1000).allocate(3).map(&:cents)).must_equal [-334, -333, -333]
    end
  end

  it 'compares within a currency only' do
    _(build(:money, cents: 100)).must_be :<, money
    _(money <=> build(:money, :usd)).must_be_nil
  end

  it 'formats' do
    _(build(:money, cents: -5).to_s).must_equal '-0.05 EUR'
    _(money.inspect).must_equal '#<Shop::Money 12.50 EUR>'
  end

  it 'round-trips random amounts' do
    10.times do
      original = build(:money, cents: Faker::Number.between(from: -100_000, to: 100_000))
      _(Shop::Money.parse(original.to_s)).must_equal original
    end
  end
end
