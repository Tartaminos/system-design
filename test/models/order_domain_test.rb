require "test_helper"

class OrderDomainTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "customer@example.com")
    @product = Product.create!(sku: "SKU-1")
    @order = @user.orders.create!
  end

  test "database foreign keys reject orphan records" do
    assert_raises(ActiveRecord::InvalidForeignKey) do
      Order.connection.transaction(requires_new: true) { Order.insert_all!([ { user_id: 999_999 } ]) }
    end

    assert_raises(ActiveRecord::InvalidForeignKey) do
      Order.connection.transaction(requires_new: true) do
        OrderItem.insert_all!([ { order_id: 999_999, product_id: @product.id, quantity: 1 } ])
      end
    end

    assert_raises(ActiveRecord::InvalidForeignKey) do
      Order.connection.transaction(requires_new: true) do
        OrderItem.insert_all!([ { order_id: @order.id, product_id: 999_999, quantity: 1 } ])
      end
    end
  end

  test "database unique index rejects duplicate product in an order" do
    @order.order_items.create!(product: @product)

    assert_raises(ActiveRecord::RecordNotUnique) do
      OrderItem.insert_all!([ { order_id: @order.id, product_id: @product.id, quantity: 1 } ])
    end
  end
end
