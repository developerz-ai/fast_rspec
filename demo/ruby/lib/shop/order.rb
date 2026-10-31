# frozen_string_literal: true

require 'json'
require 'time'

module Shop
  class Order
    InvalidTransition = Class.new(Shop::Error)
    EmptyCart = Class.new(Shop::Error)

    TRANSITIONS = {
      pending: %i[paid cancelled],
      paid: %i[shipped refunded],
      shipped: %i[delivered],
      delivered: [],
      cancelled: [],
      refunded: []
    }.freeze

    IDS = Counter.new

    attr_reader :id, :lines, :quote, :status, :placed_at, :history

    def self.place(cart, pricing: Pricing.new, codes: [], ids: IDS, now: Time.now)
      raise EmptyCart, 'cannot place an empty cart' if cart.empty?

      new(id: ids.next_id('ORD'), lines: cart.items.dup.freeze, quote: pricing.quote(cart, codes: codes), placed_at: now)
    end

    def initialize(id:, lines:, quote:, placed_at:)
      @id = id
      @lines = lines
      @quote = quote
      @placed_at = placed_at
      @status = :pending
      @history = [:pending]
    end

    def total = quote.total

    TRANSITIONS.each_value.flat_map(&:itself).uniq.each do |target|
      verb = { paid: :pay, cancelled: :cancel, shipped: :ship, refunded: :refund, delivered: :deliver }.fetch(target)
      define_method(:"#{verb}!") { transition_to(target) }
      define_method(:"#{target}?") { status == target }
    end

    def pending? = status == :pending
    def can?(target) = TRANSITIONS.fetch(status).include?(target)
    def final? = TRANSITIONS.fetch(status).empty?

    def to_h
      {
        id: id, status: status.to_s, placed_at: placed_at.utc.iso8601,
        lines: lines.map { |l| { sku: l.sku, quantity: l.quantity, total: l.total.to_s } },
        subtotal: quote.subtotal.to_s, discount: quote.discount.to_s, tax: quote.tax.to_s, total: total.to_s
      }
    end

    def to_json(*) = to_h.to_json(*)

    private

    def transition_to(target)
      raise InvalidTransition, "#{id}: #{status} -> #{target}" unless can?(target)

      @status = target
      @history << target
      self
    end
  end
end
