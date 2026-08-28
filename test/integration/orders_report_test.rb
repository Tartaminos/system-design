require "test_helper"

class OrdersReportTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "report@example.com")
    @product = Product.create!(sku: "REPORT-1")
    @order = @user.orders.create!
    @order.order_items.create!(product: @product, quantity: 3)
  end

  test "returns the order report" do
    get "/orders/report.json"

    assert_response :success
    payload = response.parsed_body
    order = payload.fetch("orders").find { |entry| entry.fetch("id") == @order.id }

    assert_equal @user.id, order.fetch("user").fetch("id")
    assert_equal @user.email, order.fetch("user").fetch("email")
    assert_equal({ "id" => @product.id, "sku" => @product.sku },
                 order.fetch("items").first.fetch("product"))
    assert_equal 3, order.fetch("items").first.fetch("quantity")
    assert payload.key?("generated_at")
  end

  test "supports report filters" do
    get "/orders/report.json", params: { from_id: @order.id, limit: 1 }

    assert_response :success
    assert_equal [ @order.id ], response.parsed_body.fetch("orders").pluck("id")
  end
end
