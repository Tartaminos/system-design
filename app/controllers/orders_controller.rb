class OrdersController < ApplicationController
  STUDY_STRATEGIES = %w[n_plus_one lazy_loading includes preload eager_load joins raw_sql].freeze
  DEFAULT_STUDY_STRATEGY = "n_plus_one"
  STUDY_LIMIT = 250

  RAW_STUDY_SQL = <<~SQL.freeze
    SELECT
      orders.id AS order_id,
      orders.user_id AS order_user_id,
      order_items.id AS order_item_id,
      order_items.product_id AS order_item_product_id,
      order_items.quantity AS order_item_quantity,
      products.id AS product_id,
      products.sku AS product_sku
    FROM (
      SELECT id, user_id
      FROM orders
      ORDER BY id ASC
      LIMIT #{STUDY_LIMIT}
    ) AS orders
    LEFT OUTER JOIN order_items ON order_items.order_id = orders.id
    LEFT OUTER JOIN products ON products.id = order_items.product_id
    ORDER BY orders.id ASC, order_items.id ASC
  SQL

  rescue_from StandardError, with: :render_internal_server_error
  rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_bad_request
  rescue_from CreateOrder::InvalidPayload, with: :render_bad_request
  rescue_from CreateOrder::ReferenceNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable_entity

  def create
    order = CreateOrder.call(**create_order_params)
    render json: { order_id: order.id }, status: :created
  end

  def study
    strategy = study_strategy
    unless STUDY_STRATEGIES.include?(strategy)
      render json: { error: "invalid_strategy" }, status: :unprocessable_content
      return
    end

    orders = measure_study_queries(strategy) { study_orders(strategy) }
    render json: {
      strategy: { requested: strategy, effective: strategy, implemented: true },
      orders:
    }
  end

  def report
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    orders = Order.where("orders.id >= ?", params.fetch(:from_id, 1))
                  .order(created_at: :desc)
                  .limit(params.fetch(:limit, 250))

    render json: {
      generated_at: Time.current,
      orders: orders.map do |order|
        {
          id: order.id,
          created_at: order.created_at,
          user: {
            id: order.user.id,
            email: order.user.email
          },
          items: order.order_items.map do |order_item|
            {
              product: {
                id: order_item.product.id,
                sku: order_item.product.sku
              },
              quantity: order_item.quantity
            }
          end
        }
      end
    }
  ensure
    duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000
    Rails.logger.info("[ORDERS_REPORT] duration_ms=#{format('%.3f', duration_ms)}")
  end

  def show
    render json: serialize_order(Order.includes(:order_items).find(params[:id]))
  end

  def index
    orders = Order.includes(:order_items).order(:id)
    render json: orders.map { |order| serialize_order(order) }
  end

  private

  def create_order_params
    payload = params.permit(:user_id, product_ids: [], items: %i[product_id quantity]).to_h
    user_id = payload["user_id"]
    product_ids = payload["product_ids"]
    items = payload["items"]

    unless user_id.is_a?(Integer) && user_id.positive? && ((product_ids && !items) || (!product_ids && items))
      raise CreateOrder::InvalidPayload, "user_id and exactly one item format are required"
    end

    { user_id:, product_ids:, items: }
  end

  def serialize_order(order)
    {
      id: order.id,
      user_id: order.user_id,
      items: order.order_items.map { |item| { product_id: item.product_id, quantity: item.quantity } }
    }
  end

  def study_strategy
    requested = params[:strategy]
    return DEFAULT_STUDY_STRATEGY if requested.nil? || (requested.is_a?(String) && requested.match?(/\A[[:space:]]*\z/))

    requested
  end

  def study_orders(strategy)
    case strategy
    when "n_plus_one", "lazy_loading"
      serialize_study_orders(Order.order(:id).limit(STUDY_LIMIT))
    when "includes"
      serialize_study_orders(Order.order(:id).limit(STUDY_LIMIT).includes(order_items: :product))
    when "preload"
      serialize_study_orders(Order.order(:id).limit(STUDY_LIMIT).preload(order_items: :product))
    when "eager_load"
      serialize_study_orders(Order.order(:id).limit(STUDY_LIMIT).eager_load(order_items: :product))
    when "joins"
      serialize_study_orders(Order.joins(:user).order(:id).limit(STUDY_LIMIT).includes(order_items: :product))
    when "raw_sql"
      raw_study_orders
    end
  end

  def serialize_study_orders(orders)
    orders.map do |order|
      {
        id: order.id,
        user_id: order.user_id,
        items: order.order_items.map do |order_item|
          product = order_item.product
          {
            product_id: order_item.product_id,
            quantity: order_item.quantity,
            product: { id: product&.id, sku: product&.sku }
          }
        end
      }
    end
  end

  def raw_study_orders
    orders = {}

    ApplicationRecord.connection.select_all(RAW_STUDY_SQL).each do |row|
      order = orders[row.fetch("order_id").to_i] ||= {
        "id" => row.fetch("order_id").to_i,
        "user_id" => row.fetch("order_user_id").to_i,
        "items" => []
      }
      next if row["order_item_id"].nil?

      order["items"] << {
        "product_id" => row.fetch("order_item_product_id").to_i,
        "quantity" => row.fetch("order_item_quantity").to_i,
        "product" => {
          "id" => row["product_id"]&.to_i,
          "sku" => row["product_sku"]
        }
      }
    end

    orders.values
  end

  def measure_study_queries(strategy)
    origin_thread = Thread.current
    origin_fiber = Fiber.current
    query_count = 0
    db_duration_ms = 0.0
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    callback = lambda do |_name, sql_started_at, sql_finished_at, _id, payload|
      next unless Thread.current.equal?(origin_thread) && Fiber.current.equal?(origin_fiber)
      next if payload[:cached]
      next if payload[:name].to_s.match?(/SCHEMA|SchemaMigration|TRANSACTION/)
      next unless payload[:sql].to_s.match?(/\ASELECT\b/i)

      query_count += 1
      db_duration_ms += (sql_finished_at - sql_started_at) * 1_000
      Rails.logger.info("[ORDERS_QUERY_STUDY] query=#{query_count} " \
                        "requested_strategy=#{strategy} effective_strategy=#{strategy} " \
                        "duration_ms=#{format('%.3f', (sql_finished_at - sql_started_at) * 1_000)}")
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", monotonic: true) do
      yield
    end
  ensure
    total_duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1_000
    Rails.logger.info("[ORDERS_QUERY_STUDY] summary=true status=#{$! ? 'error' : 'ok'} " \
                      "requested_strategy=#{strategy} effective_strategy=#{strategy} " \
                      "query_count=#{query_count} " \
                      "db_duration_ms=#{format('%.3f', db_duration_ms)} " \
                      "total_duration_ms=#{format('%.3f', total_duration_ms)}")
  end

  def render_bad_request(error)
    render_error(error.message, :bad_request)
  end

  def render_not_found(error)
    render_error(error.message, :not_found)
  end

  def render_unprocessable_entity(error)
    render_error(error.record.errors.full_messages, :unprocessable_entity)
  end

  def render_internal_server_error(_error)
    render_error("Internal server error", :internal_server_error)
  end

  def render_error(message, status)
    render json: { error: message }, status:
  end
end
