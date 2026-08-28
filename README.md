# System Design Orders API

Rails API implementing the order data model and contracts from the system design.

## Database setup

The application uses PostgreSQL. The primary, Solid Cache, Solid Queue and Solid
Cable connections can each use a separate URL through `DB_PRIMARY_URL`,
`DB_CACHE_URL`, `DB_QUEUE_URL` and `DB_CABLE_URL`. `DATABASE_URL` is accepted as
the primary URL. Without URLs, local development defaults to PostgreSQL on
`DB_HOST`/`DB_PORT` (localhost:5432), using `DB_USERNAME` or the current OS user
and the database names in `config/database.yml`.

Create the local databases (or point the URL variables at databases that already
exist), then prepare the schema:

```bash
createdb system_design_development
createdb system_design_development_cache
createdb system_design_development_queue
createdb system_design_development_cable
bin/rails db:prepare
bin/rails db:seed
```

The former SQLite source at `storage/development.sqlite3` is intentionally kept.
Install the SQLite command-line client only on the machine performing the one-time
conversion, then migrate into the PostgreSQL database selected by the normal Rails
configuration. The task refuses to write into a non-empty destination, copies rows
in foreign-key order, preserves IDs and timestamps, resets ID sequences, and checks
counts/checksums:

```bash
DATABASE_URL=postgresql://localhost:5432/system_design_development?user="$USER" \
  bin/rails db:prepare
DATABASE_URL=postgresql://localhost:5432/system_design_development?user="$USER" \
  bin/rails db:sqlite_to_postgres
```

Use `SQLITE_SOURCE=/path/to/source.sqlite3` for another source and
`MIGRATION_BATCH_SIZE=500` to tune batch size. `DATABASE_URL` is the destination;
do not point it at the SQLite file.

The seed creates a demo user, two products, and one order. It is idempotent.

To add the larger performance dataset, opt in explicitly:

```bash
ORDERS_SEED_LOAD=1 bin/rails db:seed
```

The default load contains 1,000 users, 1,000 products, 10,000 orders and
50,000 order items. Override the volume with `ORDERS_SEED_USERS`,
`ORDERS_SEED_PRODUCTS`, `ORDERS_SEED_ORDERS` and `ORDERS_SEED_ITEMS`.

To inspect the test database instead:

```bash
RAILS_ENV=test bin/rails db:prepare
RAILS_ENV=test bin/rails db:seed
```

Run the API with `bin/rails server` and the test suite with `bin/rails test`.
Production deployments require `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`
and `DB_NAME` (plus the optional per-role URLs/names); keep the password in the
deployment secret store. Kamal no longer persists a database inside the container.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...
