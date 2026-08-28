class CreateOrder
  class InvalidPayload < StandardError; end
  class ReferenceNotFound < StandardError; end

  def self.call(user_id:, product_ids: nil, items: nil)
    new(user_id:, product_ids:, items:).call
  end

  def initialize(user_id:, product_ids:, items:)
    @user_id = user_id
    @product_ids = product_ids
    @items = items
  end

  def call
    parsed_items = normalized_items

    Order.transaction do
      user = User.find_by(id: @user_id) || raise(ReferenceNotFound, "User not found")
      order = user.orders.create!

      parsed_items.each do |product_id, quantity|
        product = Product.find_by(id: product_id) || raise(ReferenceNotFound, "Product not found")
        order.order_items.create!(product:, quantity:)
      end

      order
    end
  end

  private

  def normalized_items
    if @product_ids
      validate_array(@product_ids, "product_ids")
      return @product_ids.map { |product_id| [ valid_id(product_id, "product_ids"), 1 ] }
    end

    validate_array(@items, "items")
    @items.map do |entry|
      raise InvalidPayload, "items must contain objects" unless entry.is_a?(Hash)

      product_id = valid_id(entry["product_id"] || entry[:product_id], "product_id")
      quantity = entry.key?("quantity") ? entry["quantity"] : (entry.key?(:quantity) ? entry[:quantity] : 1)
      raise InvalidPayload, "quantity must be a positive integer" unless quantity.is_a?(Integer) && quantity.positive?

      [ product_id, quantity ]
    end
  end

  def validate_array(value, name)
    raise InvalidPayload, "#{name} must be a non-empty array" unless value.is_a?(Array) && value.any?
  end

  def valid_id(value, name)
    raise InvalidPayload, "#{name} must contain positive integers" unless value.is_a?(Integer) && value.positive?

    value
  end
end
