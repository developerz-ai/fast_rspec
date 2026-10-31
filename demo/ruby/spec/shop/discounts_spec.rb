# frozen_string_literal: true

RSpec.describe Shop::Discounts do
  let(:book) { build(:product, :book, sku: 'BOOK', price: Shop::Money.parse('20.00 EUR'), stock: 50) }
  let(:pen) { build(:product, sku: 'PEN', price: Shop::Money.parse('2.00 EUR'), stock: 50) }
  let(:eligible_cart) { build(:cart, products: [book, pen], quantity: 2) }

  describe Shop::Discounts::PercentOff do
    it_behaves_like 'a discount' do
      let(:discount) { build(:percent_off, percent: 10) }
      let(:expired_discount) { build(:percent_off, :expired) }
      let(:expected_amount) { '4.40 EUR' }
    end

    context 'when limited to a category' do
      it_behaves_like 'a discount' do
        let(:discount) { build(:percent_off, :books_only, percent: 25) }
        let(:expired_discount) { build(:percent_off, :books_only, :expired) }
        let(:expected_amount) { '10.00 EUR' }
      end
    end

    context 'with a coupon code' do
      let(:discount) { build(:percent_off, :coupon) }

      it 'needs the code' do
        expect(discount.applicable?(eligible_cart, codes: [])).to be(false)
      end

      it 'matches codes case-insensitively' do
        expect(discount.applicable?(eligible_cart, codes: [discount.code.downcase])).to be(true)
      end

      it 'gets distinct codes from Faker.unique' do
        codes = build_list(:percent_off, 5, :coupon).map(&:code)
        expect(codes.uniq.size).to eq(5)
      end
    end

    it 'validates the percent range' do
      expect { build(:percent_off, percent: 101) }.to raise_error(ArgumentError, /0..100/)
    end
  end

  describe Shop::Discounts::FixedOff do
    it_behaves_like 'a discount' do
      let(:discount) { build(:fixed_off) }
      let(:expired_discount) { build(:fixed_off, expires_at: Time.at(0)) }
      let(:expected_amount) { '5.00 EUR' }
    end

    it 'never exceeds the subtotal' do
      cart = build(:cart, products: [build(:product, :cheap)])
      expect(build(:fixed_off).amount_for(cart)).to eq(Shop::Money.parse('1.00 EUR'))
    end

    it 'respects a minimum subtotal' do
      discount = build(:fixed_off, min_subtotal: Shop::Money.parse('100.00 EUR'))
      expect(discount.applicable?(eligible_cart)).to be(false)
    end
  end

  describe Shop::Discounts::BuyXGetY do
    let(:item) { build(:product, sku: 'SKU-3FOR2', price: Shop::Money.parse('3.00 EUR'), stock: 20) }

    it_behaves_like 'a discount' do
      let(:discount) { build(:buy_x_get_y) }
      let(:expired_discount) { build(:buy_x_get_y, expires_at: Time.now - 60) }
      let(:eligible_cart) { build(:cart, products: [item], quantity: 7) }
      let(:expected_amount) { '6.00 EUR' }
    end

    it 'gives nothing below a full group' do
      cart = build(:cart, products: [item], quantity: 2)
      expect(build(:buy_x_get_y).amount_for(cart)).to be_zero
    end

    it 'gives nothing when the sku is absent' do
      expect(build(:buy_x_get_y).amount_for(eligible_cart)).to be_zero
    end
  end
end
