# Strategy: `eager_load`

Queries captured from the orders study endpoint:

```sql
SELECT DISTINCT "orders"."id" AS alias_0, "orders"."id" FROM "orders" LEFT OUTER JOIN "order_items" ON "order_items"."order_id" = "orders"."id" LEFT OUTER JOIN "products" ON "products"."id" = "order_items"."product_id" ORDER BY "orders"."id" ASC LIMIT $1
```

```sql
SELECT "orders"."id" AS t0_r0, "orders"."created_at" AS t0_r1, "orders"."updated_at" AS t0_r2, "orders"."user_id" AS t0_r3, "order_items"."id" AS t1_r0, "order_items"."created_at" AS t1_r1, "order_items"."order_id" AS t1_r2, "order_items"."product_id" AS t1_r3, "order_items"."quantity" AS t1_r4, "order_items"."updated_at" AS t1_r5, "products"."id" AS t2_r0, "products"."created_at" AS t2_r1, "products"."sku" AS t2_r2, "products"."updated_at" AS t2_r3 FROM "orders" LEFT OUTER JOIN "order_items" ON "order_items"."order_id" = "orders"."id" LEFT OUTER JOIN "products" ON "products"."id" = "order_items"."product_id" WHERE "orders"."id" = $1 ORDER BY "orders"."id" ASC
```
