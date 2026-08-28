class Product < ApplicationRecord
  has_many :order_items, dependent: :restrict_with_exception
  has_many :orders, through: :order_items

  validates :sku, presence: true, uniqueness: true
end
