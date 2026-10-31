# frozen_string_literal: true

require 'test_helper'

class ImporterTest < Minitest::Test
  def setup
    @importer = Shop::Importer.new
  end

  def test_imports_csv
    with_tmpdir do |dir|
      path = File.join(dir, 'catalog.csv')
      File.write(path, "sku,name,price,category,stock\nmug-1,Mug,8.50 EUR,kitchen,12\ntea-1,\"Tea, green\",3.25 EUR,food,100\n")
      result = @importer.import(path)

      assert_predicate result, :ok?
      assert_equal %w[MUG-1 TEA-1], result.products.map(&:sku)
      assert_equal 'Tea, green', result.products.last.name
    end
  end

  def test_collects_row_errors
    with_tmpdir do |dir|
      path = File.join(dir, 'bad.csv')
      File.write(path, <<~CSV)
        sku,name,price,category,stock
        ok-1,Fine,1.00 EUR,general,1
        ,No sku,1.00 EUR,general,1
        ok-1,Duplicate,1.00 EUR,general,1
      CSV
      result = @importer.import(path)

      assert_equal 1, result.products.size
      assert_equal ['line 3: sku must be present', 'line 4: duplicate sku OK-1'], result.errors
    end
  end

  def test_imports_json
    with_tmpdir do |dir|
      path = File.join(dir, 'catalog.json')
      File.write(path, [{ sku: 'x1', name: 'X', price: '1 EUR' }].to_json)

      assert_equal 'general', @importer.import(path).products.first.category
    end
  end

  def test_unsupported_format
    with_tmpdir do |dir|
      path = File.join(dir, 'catalog.xml').tap { |p| File.write(p, '<x/>') }

      assert_raises(Shop::Importer::UnsupportedFormat) { @importer.import(path) }
    end
  end

  def test_round_trips_faker_products
    with_tmpdir do |dir|
      products = build_list(:product, 20, :random_price)
      path = @importer.export_csv(products, File.join(dir, 'nested', 'out.csv'))

      assert_equal products, @importer.import(path).products
      assert_equal ['out.csv'], Dir.children(File.dirname(path))
    end
  end

  def test_shared_project_tmp_export
    path = project_tmp('exports', 'catalog-minitest.csv')
    @importer.export_csv(build_list(:product, 3), path)

    assert_equal 4, File.readlines(path).size
  ensure
    FileUtils.rm_f(path)
  end

  def test_progress_output
    with_tmpdir do |dir|
      path = @importer.export_csv(build_list(:product, 2), File.join(dir, 'out.csv'))

      assert_output(/imported 2 products/) { puts "imported #{@importer.import(path).products.size} products" }
    end
  end
end
