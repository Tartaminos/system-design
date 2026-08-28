class CreateOrderDomain < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.timestamps
    end
    add_index :users, :email, unique: true

    create_table :products do |t|
      t.string :sku, null: false
      t.timestamps
    end
    add_index :products, :sku, unique: true

    create_table :orders do |t|
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end

    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 1
      t.timestamps
    end
    add_index :order_items, %i[order_id product_id], unique: true
  end
end
