# Strategy: `raw_sql`

Query defined in `OrdersController::RAW_STUDY_SQL` and captured from the orders study endpoint:

```sql
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
  LIMIT 250
) AS orders
LEFT OUTER JOIN order_items ON order_items.order_id = orders.id
LEFT OUTER JOIN products ON products.id = order_items.product_id
ORDER BY orders.id ASC, order_items.id ASC
```
