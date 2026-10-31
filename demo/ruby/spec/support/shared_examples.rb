# frozen_string_literal: true

# Host must define `subject`, `twin` (equal but distinct object) and `different`.
RSpec.shared_examples 'a value object' do
  it 'is frozen' do
    expect(subject).to be_frozen
  end

  it 'is equal to a twin with the same attributes' do
    expect(subject).to eq(twin)
    expect(subject).to eql(twin)
    expect(subject).not_to equal(twin)
  end

  it 'hashes like its twin, so it dedups in a Set/Hash' do
    expect([subject, twin, different].uniq).to contain_exactly(subject, different)
  end

  it 'is not equal to a different value' do
    expect(subject).not_to eq(different)
  end
end

# Host must define `discount`, `expired_discount`, `eligible_cart` and `expected_amount`.
RSpec.shared_examples 'a discount' do
  it 'applies to an eligible cart with the expected amount' do
    expect(discount.applicable?(eligible_cart, codes: Array(discount.code))).to be(true)
    expect(discount.amount_for(eligible_cart)).to eq(Shop::Money.parse(expected_amount))
  end

  it 'never applies to an empty cart' do
    expect(discount.applicable?(Shop::Cart.new, codes: Array(discount.code))).to be(false)
  end

  it 'stops applying once expired' do
    expect(expired_discount.applicable?(eligible_cart, codes: Array(expired_discount.code))).to be(false)
  end
end

RSpec.shared_context 'with a tmp dir' do
  around do |example|
    Dir.mktmpdir('shop-spec') do |dir|
      @tmpdir = dir
      example.run
    end
  end

  let(:tmpdir) { @tmpdir }
end
