require "test_helper"

class OrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "customer@example.com")
    @products = [ Product.create!(sku: "SKU-1"), Product.create!(sku: "SKU-2") ]
  end

  test "creates an order from product ids" do
    assert_difference("Order.count", 1) do
      post orders_path, params: { user_id: @user.id, product_ids: @products.map(&:id) }, as: :json
    end

    assert_response :created
    assert_equal({ "order_id" => Order.last.id }, JSON.parse(response.body))
    assert_equal [ 1, 1 ], Order.last.order_items.order(:id).pluck(:quantity)
  end

  test "creates an order from item quantities" do
    post orders_path, params: { user_id: @user.id, items: [ { product_id: @products.first.id, quantity: 3 } ] }, as: :json

    assert_response :created
    assert_equal 3, Order.last.order_items.first.quantity
  end

  test "defaults item quantity to one" do
    post orders_path, params: { user_id: @user.id, items: [ { product_id: @products.first.id } ] }, as: :json

    assert_response :created
    assert_equal 1, Order.last.order_items.first.quantity
  end

  test "rolls back when a product is missing" do
    assert_no_difference("Order.count") do
      post orders_path, params: { user_id: @user.id, product_ids: [ @products.first.id, 999_999 ] }, as: :json
    end

    assert_response :not_found
    assert_equal 0, OrderItem.count
  end

  test "rolls back when a later item violates uniqueness" do
    assert_no_difference([ "Order.count", "OrderItem.count" ]) do
      post orders_path, params: { user_id: @user.id,
                                  items: [ { product_id: @products.first.id },
                                           { product_id: @products.first.id } ] }, as: :json
    end

    assert_response :unprocessable_entity
    assert_equal [ "Product has already been taken" ], JSON.parse(response.body)["error"]
  end

  test "returns not found for an unknown user" do
    assert_no_difference("Order.count") do
      post orders_path, params: { user_id: 999_999, product_ids: [ @products.first.id ] }, as: :json
    end

    assert_response :not_found
    assert_equal({ "error" => "User not found" }, JSON.parse(response.body))
  end

  test "returns an order" do
    order = @user.orders.create!
    order.order_items.create!(product: @products.first)

    get order_path(order)

    assert_response :success
    assert_equal({ "id" => order.id, "user_id" => @user.id,
                   "items" => [ { "product_id" => @products.first.id, "quantity" => 1 } ] }, JSON.parse(response.body))
  end

  test "returns all orders" do
    first_order = @user.orders.create!
    first_order.order_items.create!(product: @products.first, quantity: 2)
    second_order = @user.orders.create!
    second_order.order_items.create!(product: @products.second)

    get orders_path

    assert_response :success
    assert_equal [ first_order.id, second_order.id ], JSON.parse(response.body).map { |entry| entry["id"] }
    assert_equal 2, JSON.parse(response.body).first.dig("items", 0, "quantity")
  end

  test "returns not found for an unknown order" do
    get order_path(999_999)

    assert_response :not_found
    assert JSON.parse(response.body).fetch("error").present?
  end

  test "rejects an invalid payload" do
    post orders_path, params: { user_id: @user.id, product_ids: [] }, as: :json

    assert_response :bad_request
    assert JSON.parse(response.body).key?("error")
  end

  test "rejects malformed JSON" do
    post orders_path, params: '{"user_id":', headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :bad_request
    assert JSON.parse(response.body).fetch("error").present?
  end

  [
    { user_id: 0, product_ids: [ 1 ] },
    { user_id: 1, product_ids: [ "1" ] },
    { user_id: 1, items: [ { product_id: 1, quantity: 0 } ] },
    { user_id: 1, product_ids: [ 1 ], items: [ { product_id: 1 } ] },
    { user_id: 1 }
  ].each_with_index do |payload, index|
    test "rejects malformed payload ##{index + 1}" do
      post orders_path, params: payload, as: :json

      assert_response :bad_request
      assert JSON.parse(response.body).fetch("error").present?
    end
  end

  test "returns internal server error for an unexpected failure" do
    original_find_by = Product.method(:find_by)
    Product.define_singleton_method(:find_by) { |*| raise "unexpected failure" }

    begin
      post orders_path, params: { user_id: @user.id, product_ids: [ @products.first.id ] }, as: :json
    ensure
      Product.define_singleton_method(:find_by, original_find_by)
    end

    assert_response :internal_server_error
    assert_equal({ "error" => "Internal server error" }, JSON.parse(response.body))
  end
end
