class User < ApplicationRecord
  has_many :orders, dependent: :restrict_with_exception

  validates :email, presence: true, uniqueness: true
end
