# frozen_string_literal: true

RSpec.describe Shop::Money do
  subject(:money) { described_class.new(cents: 1250, currency: 'EUR') }

  it_behaves_like 'a value object' do
    let(:twin) { described_class.new(cents: 1250, currency: 'EUR') }
    let(:different) { described_class.new(cents: 1250, currency: 'USD') }
  end

  describe '.parse' do
    {
      '12.50 EUR' => 1250,
      '12 EUR' => 1200,
      '-0.99 EUR' => -99,
      '  7.00 EUR ' => 700
    }.each do |text, cents|
      it "parses #{text.inspect} as #{cents} cents" do
        expect(described_class.parse(text)).to have_attributes(cents: cents, currency: 'EUR')
      end
    end

    it 'rejects garbage with a helpful message' do
      expect { described_class.parse('twelve euros') }
        .to raise_error(Shop::Money::ParseError, /cannot parse money: "twelve euros"/)
    end

    it 'rejects three decimals' do
      expect { described_class.parse('1.999 EUR') }.to raise_error(Shop::Money::ParseError)
    end
  end

  describe 'construction' do
    it 'requires integer cents' do
      expect { described_class.new(cents: 1.5, currency: 'EUR') }.to raise_error(ArgumentError, /Integer/)
    end

    it 'requires an ISO currency' do
      expect { described_class.new(cents: 1, currency: 'euro') }.to raise_error(ArgumentError, /bad currency/)
    end
  end

  describe 'arithmetic' do
    let(:other) { build(:money, cents: 250) }

    it 'adds and subtracts' do
      aggregate_failures do
        expect(money + other).to eq(build(:money, cents: 1500))
        expect(money - other).to eq(build(:money, cents: 1000))
        expect(-money).to eq(build(:money, cents: -1250))
      end
    end

    it 'refuses to mix currencies' do
      expect { money + build(:money, :usd) }.to raise_error(Shop::Money::CurrencyMismatch, 'EUR vs USD')
    end

    it 'refuses non-money operands' do
      expect { money + 5 }.to raise_error(TypeError)
    end

    it 'multiplies with half-up rounding' do
      expect(build(:money, cents: 105) * 0.5).to have_attributes(cents: 53)
      expect(build(:money, cents: -105) * 0.5).to have_attributes(cents: -53)
    end

    it 'multiplies by rationals exactly' do
      expect((build(:money, cents: 1000) * Rational(1, 3)).cents).to eq(333)
    end
  end

  describe '#allocate' do
    it 'never loses a cent' do
      parts = build(:money, cents: 1000).allocate(3)
      expect(parts.map(&:cents)).to eq([334, 333, 333])
      expect(parts.sum(&:cents)).to eq(1000)
    end

    it 'honours ratios' do
      expect(build(:money, cents: 100).allocate([1, 3]).map(&:cents)).to eq([25, 75])
    end

    it 'handles negative amounts symmetrically' do
      expect(build(:money, cents: -1000).allocate(3).map(&:cents)).to eq([-334, -333, -333])
    end

    it 'leaves trailing parts at zero when there are more parts than cents' do
      expect(build(:money, cents: 2).allocate(4).map(&:cents)).to eq([1, 1, 0, 0])
    end

    it 'rejects zero ratios' do
      expect { money.allocate([0, 0]) }.to raise_error(ArgumentError)
    end
  end

  describe 'comparison' do
    it 'orders by cents within a currency' do
      list = [build(:money, cents: 300), build(:money, cents: 100), build(:money, cents: 200)]
      expect(list.sort.map(&:cents)).to eq([100, 200, 300])
      expect(build(:money, cents: 100)).to be < money
    end

    it 'does not compare across currencies' do
      expect(money <=> build(:money, :usd)).to be_nil
    end
  end

  describe '#to_s' do
    it 'formats with two decimals and sign' do
      expect([money.to_s, build(:money, cents: -5).to_s]).to eq(['12.50 EUR', '-0.05 EUR'])
      expect(money.inspect).to eq('#<Shop::Money 12.50 EUR>')
    end
  end

  it 'round-trips through to_s and parse' do
    10.times do
      cents = Faker::Number.between(from: -100_000, to: 100_000)
      original = build(:money, cents: cents)
      expect(described_class.parse(original.to_s)).to eq(original)
    end
  end
end
