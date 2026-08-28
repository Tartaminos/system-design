require "test_helper"
require "stringio"

class OrdersStudyTest < ActionDispatch::IntegrationTest
  STRATEGIES = %w[n_plus_one lazy_loading includes preload eager_load joins raw_sql].freeze

  setup do
    @user = User.create!(email: "study@example.com")
    @products = [ Product.create!(sku: "STUDY-1"), Product.create!(sku: "STUDY-2") ]
    @first_order = @user.orders.create!
    @first_order.order_items.create!(product: @products.second, quantity: 2)
    @first_order.order_items.create!(product: @products.first, quantity: 1)
    @second_order = @user.orders.create!
  end

  test "all strategies return the same serialized graph without writes" do
    before_state = [ Order.count, OrderItem.count, User.count, Product.count ]

    graphs = STRATEGIES.to_h do |strategy|
      get "/orders/study.json", params: { strategy: strategy }

      assert_response :success
      payload = response.parsed_body
      assert_equal({ "requested" => strategy, "effective" => strategy, "implemented" => true },
                   payload.fetch("strategy"))
      [ strategy, payload.fetch("orders") ]
    end

    assert_equal before_state, [ Order.count, OrderItem.count, User.count, Product.count ]
    assert graphs.values.all? { |graph| graph == graphs.fetch("n_plus_one") }
    assert graphs.fetch("n_plus_one").flat_map { |order| order.fetch("items") }.all? do |item|
      assert_equal({ "id" => item.fetch("product").fetch("id"),
                     "sku" => item.fetch("product").fetch("sku") }, item.fetch("product"))
    end
    assert_equal [ @first_order.id, @second_order.id ], graphs.fetch("raw_sql").pluck("id")
    assert_equal [ { "product_id" => @products.second.id, "quantity" => 2,
                     "product" => { "id" => @products.second.id, "sku" => "STUDY-2" } },
                   { "product_id" => @products.first.id, "quantity" => 1,
                     "product" => { "id" => @products.first.id, "sku" => "STUDY-1" } } ],
                  graphs.fetch("raw_sql").first.fetch("items")
  end

  test "limits roots to 250 in deterministic id order" do
    249.times { @user.orders.create! }

    get "/orders/study.json", params: { strategy: "raw_sql" }

    assert_response :success
    orders = response.parsed_body.fetch("orders")
    assert_equal 250, orders.size
    assert_equal @first_order.id, orders.first.fetch("id")
    assert_equal @user.orders.order(:id).offset(249).pick(:id), orders.last.fetch("id")
  end

  test "limits roots to 250 for every strategy" do
    249.times { @user.orders.create! }
    expected_ids = @user.orders.order(:id).limit(250).pluck(:id)

    STRATEGIES.each do |strategy|
      get "/orders/study.json", params: { strategy: strategy }

      assert_response :success
      assert_equal expected_ids, response.parsed_body.fetch("orders").pluck("id"), strategy
    end
  end

  test "defaults missing and whitespace-only strategies to n_plus_one" do
    [ nil, "", " \t " ].each do |strategy|
      params = strategy.nil? ? {} : { strategy: strategy }
      get "/orders/study.json", params: params

      assert_response :success
      assert_equal({ "requested" => "n_plus_one", "effective" => "n_plus_one", "implemented" => true },
                   response.parsed_body.fetch("strategy"))
    end
  end

  test "rejects strategies outside the exact allowlist without selecting orders" do
    queries = []
    subscriber = lambda do |_name, _started, _finished, _id, payload|
      queries << payload[:sql] if payload[:sql].to_s.match?(/\ASELECT\b/i)
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      get "/orders/study.json", params: { strategy: "includes " }
    end

    assert_response :unprocessable_content
    assert_equal({ "error" => "invalid_strategy" }, response.parsed_body)
    assert_empty queries
  end

  test "raw_sql uses left outer joins with one select and without payload logging" do
    instantiations = []
    selects = []
    subscriber = lambda do |_name, _started, _finished, _id, payload|
      instantiations << payload[:class_name]
    end
    sql_subscriber = lambda do |_name, _started, _finished, _id, payload|
      selects << payload[:sql] if payload[:sql].to_s.match?(/\ASELECT\b/i)
    end
    log_output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log_output)

    ActiveSupport::Notifications.subscribed(subscriber, "instantiation.active_record") do
      ActiveSupport::Notifications.subscribed(sql_subscriber, "sql.active_record") do
        get "/orders/study.json", params: { strategy: "raw_sql" }
      end
    end

    assert_response :success
    assert_empty instantiations
    assert_equal 1, selects.size
    assert_equal 2, selects.first.scan(/LEFT OUTER JOIN/i).size
    assert_includes log_output.string,
                    "[ORDERS_QUERY_STUDY] query=1 requested_strategy=raw_sql effective_strategy=raw_sql"
    assert_includes log_output.string,
                    "summary=true status=ok requested_strategy=raw_sql effective_strategy=raw_sql query_count=1"
    assert_not_includes log_output.string, "study@example.com"
    assert_not_includes log_output.string, "STUDY-1"
  ensure
    Rails.logger = original_logger if original_logger
  end
end
