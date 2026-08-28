# Strategy: `n_plus_one`

Queries captured from the orders study endpoint:

```sql
SELECT "orders".* FROM "orders" ORDER BY "orders"."id" ASC LIMIT $1
```

```sql
SELECT "order_items".* FROM "order_items" WHERE "order_items"."order_id" = $1
```

```sql
SELECT "products".* FROM "products" WHERE "products"."id" = $1 LIMIT $2
```

```sql
SELECT "products".* FROM "products" WHERE "products"."id" = $1 LIMIT $2
```
