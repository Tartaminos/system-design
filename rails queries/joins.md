# Strategy: `joins`

Queries captured from the orders study endpoint:

```sql
SELECT "orders".* FROM "orders" INNER JOIN "users" ON "users"."id" = "orders"."user_id" ORDER BY "orders"."id" ASC LIMIT $1
```

```sql
SELECT "order_items".* FROM "order_items" WHERE "order_items"."order_id" = $1
```

```sql
SELECT "products".* FROM "products" WHERE "products"."id" IN ($1, $2)
```
