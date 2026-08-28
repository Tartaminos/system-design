class OrderItem < ApplicationRecord
  belongs_to :order
  belongs_to :product

  validates :order, :product, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :product_id, uniqueness: { scope: :order_id }
end
