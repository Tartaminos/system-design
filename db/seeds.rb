# This seed is safe to run repeatedly in development and creates a small,
# deterministic dataset for exercising the orders API.

user = User.find_or_create_by!(email: "demo@example.com")

products = [
  { sku: "SKU-001", quantity: 2 },
  { sku: "SKU-002", quantity: 1 }
].map do |attributes|
  quantity = attributes.delete(:quantity)
  [ Product.find_or_create_by!(sku: attributes.fetch(:sku)), quantity ]
end

order = user.orders.order(:id).first

unless order
  order = CreateOrder.call(
    user_id: user.id,
    items: products.map { |product, quantity| { product_id: product.id, quantity: quantity } }
  )
end

puts "Seeded user ##{user.id}, #{products.length} products and order ##{order.id}."

if ENV["ORDERS_SEED_LOAD"] == "1"
  parse_count = lambda do |name, default|
    value = Integer(ENV.fetch(name, default.to_s), 10)
    raise ArgumentError, "#{name} must be a positive integer" unless value.positive?

    value
  rescue ArgumentError
    raise ArgumentError, "#{name} must be a positive integer"
  end

  load_users = parse_count.call("ORDERS_SEED_USERS", 1_000)
  load_products = parse_count.call("ORDERS_SEED_PRODUCTS", 1_000)
  load_orders = parse_count.call("ORDERS_SEED_ORDERS", 10_000)
  load_items = parse_count.call("ORDERS_SEED_ITEMS", 50_000)

  if load_items < load_orders || load_items > load_orders * load_products
    raise ArgumentError, "ORDERS_SEED_ITEMS must be between orders and orders * products"
  end

  now = Time.current
  batch_size = 1_000
  load_email_prefix = "loadtest-user-"
  load_sku_prefix = "LOADTEST-SKU-"

  ActiveRecord::Base.transaction do
    synthetic_users = load_users.times.map do |index|
      { email: format("%s%06d@example.com", load_email_prefix, index + 1), created_at: now, updated_at: now }
    end
    User.insert_all(synthetic_users, unique_by: :index_users_on_email)
    user_ids = User.where("email LIKE ?", "#{load_email_prefix}%").order(:id).limit(load_users).pluck(:id)

    synthetic_products = load_products.times.map do |index|
      { sku: format("%s%06d", load_sku_prefix, index + 1), created_at: now, updated_at: now }
    end
    Product.insert_all(synthetic_products, unique_by: :index_products_on_sku)
    product_ids = Product.where("sku LIKE ?", "#{load_sku_prefix}%").order(:id).limit(load_products).pluck(:id)

    old_order_ids = Order.where(user_id: user_ids).pluck(:id)
    OrderItem.where(order_id: old_order_ids).delete_all if old_order_ids.any?
    Order.where(id: old_order_ids).delete_all if old_order_ids.any?

    load_orders.times.each_slice(batch_size) do |batch|
      Order.insert_all!(
        batch.map do |order_index|
          { user_id: user_ids[order_index % user_ids.length], created_at: now, updated_at: now }
        end
      )
    end

    order_ids = Order.where(user_id: user_ids).order(:id).pluck(:id)
    item_rows = []
    load_items.times do |item_index|
      order_index = item_index % load_orders
      item_number = item_index / load_orders
      item_rows << {
        order_id: order_ids[order_index],
        product_id: product_ids[(order_index + item_number) % product_ids.length],
        quantity: (item_index % 3) + 1,
        created_at: now,
        updated_at: now
      }

      if item_rows.length >= batch_size
        OrderItem.insert_all!(item_rows)
        item_rows.clear
      end
    end
    OrderItem.insert_all!(item_rows) if item_rows.any?
  end

  puts "Seeded performance load: #{load_users} users, #{load_products} products, #{load_orders} orders and #{load_items} items."
end
