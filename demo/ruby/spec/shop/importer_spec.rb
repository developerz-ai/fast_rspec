# frozen_string_literal: true

RSpec.describe Shop::Importer do
  include_context 'with a tmp dir'

  subject(:importer) { described_class.new }

  def write(name, content)
    File.join(tmpdir, name).tap { |path| File.write(path, content) }
  end

  it 'imports a CSV catalog' do
    path = write('catalog.csv', <<~CSV)
      sku,name,price,category,stock
      mug-1,Mug,8.50 EUR,kitchen,12
      tea-1,"Tea, green",3.25 EUR,food,100
    CSV
    result = importer.import(path)
    expect(result).to be_ok
    expect(result.products.map(&:sku)).to eq(%w[MUG-1 TEA-1])
    expect(result.products.last).to have_attributes(name: 'Tea, green', price: Shop::Money.parse('3.25 EUR'))
  end

  it 'collects row errors with line numbers instead of aborting' do
    path = write('bad.csv', <<~CSV)
      sku,name,price,category,stock
      ok-1,Fine,1.00 EUR,general,1
      ,No sku,1.00 EUR,general,1
      bad-2,Bad price,free,general,1
      ok-1,Duplicate,1.00 EUR,general,1
      neg-1,Negative stock,1.00 EUR,general,-3
    CSV
    result = importer.import(path)
    expect(result.products.size).to eq(1)
    expect(result.errors).to eq([
                                  'line 3: sku must be present',
                                  'line 4: cannot parse money: "free"',
                                  'line 5: duplicate sku OK-1',
                                  'line 6: stock must be >= 0'
                                ])
  end

  it 'imports JSON with defaults for missing fields' do
    path = write('catalog.json', [{ sku: 'x1', name: 'X', price: '1 EUR' }].to_json)
    expect(importer.import(path).products.first).to have_attributes(category: 'general', stock: 0)
  end

  it 'rejects unknown formats' do
    expect { importer.import(write('catalog.xml', '<x/>')) }.to raise_error(described_class::UnsupportedFormat)
  end

  it 'round-trips Faker products through CSV export' do
    products = build_list(:product, 20, :random_price)
    path = importer.export_csv(products, File.join(tmpdir, 'nested', 'out.csv'))
    expect(importer.import(path).products).to eq(products)
  end

  it 'writes atomically, leaving no temp files behind' do
    importer.export_csv(build_list(:product, 2), File.join(tmpdir, 'out.csv'))
    expect(Dir.children(tmpdir)).to eq(['out.csv'])
  end

  # Realistic: many suites write to a fixed path under the project's tmp/.
  # Serially fine; under parallel workers this needs per-worker tmp isolation.
  describe 'exporting to the project tmp dir' do
    let(:path) { File.expand_path('../../tmp/exports/catalog.csv', __dir__) }

    after { FileUtils.rm_f(path) }

    it 'writes and reads back the shared export path' do
      importer.export_csv(build_list(:product, 3), path)
      expect(File.readlines(path).size).to eq(4)
    end

    it 'overwrites a previous export' do
      importer.export_csv(build_list(:product, 5), path)
      importer.export_csv(build_list(:product, 1), path)
      expect(importer.import(path).products.size).to eq(1)
    end
  end
end
