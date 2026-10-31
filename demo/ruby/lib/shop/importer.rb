# frozen_string_literal: true

require 'csv'
require 'json'
require 'fileutils'

module Shop
  # Imports products from CSV or JSON files, collecting per-row errors instead of aborting.
  class Importer
    Result = Data.define(:products, :errors) do
      def ok? = errors.empty?
    end
    UnsupportedFormat = Class.new(Shop::Error)

    HEADERS = %w[sku name price category stock].freeze

    def import(path)
      rows = case File.extname(path).downcase
             when '.csv' then CSV.read(path, headers: true).map(&:to_h)
             when '.json' then JSON.parse(File.read(path))
             else raise UnsupportedFormat, "unsupported file: #{path}"
             end
      build(rows)
    end

    # Atomic: readers never see a half-written file.
    def export_csv(products, path)
      FileUtils.mkdir_p(File.dirname(path))
      tmp = "#{path}.#{Process.pid}.#{Thread.current.object_id}.tmp"
      CSV.open(tmp, 'w') do |csv|
        csv << HEADERS
        products.each { |p| csv << [p.sku, p.name, p.price.to_s, p.category, p.stock] }
      end
      File.rename(tmp, path)
      path
    end

    private

    def build(rows)
      products = []
      errors = []
      seen = {}
      rows.each.with_index(2) do |row, line|
        product = Product.new(sku: row['sku'], name: row['name'], price: Money.parse(row['price']),
                              category: row['category'] || 'general', stock: Integer(row['stock'] || 0))
        if seen[product.sku]
          errors << "line #{line}: duplicate sku #{product.sku}"
        else
          seen[product.sku] = true
          products << product
        end
      rescue ArgumentError, TypeError, Shop::Error => e
        errors << "line #{line}: #{e.message}"
      end
      Result.new(products: products.freeze, errors: errors.freeze)
    end
  end
end
