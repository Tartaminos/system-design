# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "time"

namespace :db do
  desc "Copy application data from SQLite into the configured PostgreSQL database"
  task sqlite_to_postgres: :environment do
    source = ENV.fetch("SQLITE_SOURCE", Rails.root.join("storage/development.sqlite3").to_s)
    abort "SQLite source does not exist: #{source}" unless File.file?(source)

    sqlite = ENV.fetch("SQLITE3_BIN", "sqlite3")
    sqlite_available = begin
      Open3.capture3(sqlite, "--version").last.success?
    rescue Errno::ENOENT
      false
    end
    sqlite_command = if sqlite_available
      ->(query) { Open3.capture3(sqlite, "-readonly", "-json", source, query) }
    else
      # Keep sqlite3 out of the application bundle while allowing a host that has
      # the gem installed to run this one-time conversion without the CLI package.
      ruby_reader = <<~'RUBY'
        require "json"
        require "sqlite3"
        database, query = ARGV
        db = SQLite3::Database.new(database, readonly: true)
        rows = db.execute2(query)
        puts JSON.generate(rows.drop(1).map { |row| rows.first.zip(row).to_h })
      RUBY
      ->(query) { Bundler.with_unbundled_env { Open3.capture3(RbConfig.ruby, "-e", ruby_reader, source, query) } }
    end

    define_singleton_method(:sqlite_json) do |query|
      stdout, stderr, status = sqlite_command.call(query)
      abort "sqlite3 failed: #{stderr}" unless status.success?

      JSON.parse(stdout)
    end

    define_singleton_method(:checksum) do |rows|
      normalized = rows.map do |row|
        row.sort.to_h do |key, value|
          normalized_value = if value.is_a?(Time)
            value.utc.strftime("%Y-%m-%d %H:%M:%S.%6N")
          elsif value.to_s.match?(/\A\d{4}-\d\d-\d\d \d\d:\d\d:\d\d(?:\.\d+)?(?: UTC)?\z/)
            timestamp = value.to_s.delete_suffix(" UTC")
            timestamp.include?(".") ? timestamp.ljust(26, "0") : "#{timestamp}.000000"
          else
            value
          end
          [ key, normalized_value ]
        end
      end
      Digest::SHA256.hexdigest(normalized.map { |row| JSON.generate(row) }.sort.join("\n"))
    end
    table_rows = sqlite_json(<<~SQL)
      SELECT name FROM sqlite_master
      WHERE type = 'table'
        AND name NOT LIKE 'sqlite_%'
        AND name NOT IN ('schema_migrations', 'ar_internal_metadata')
      ORDER BY name
    SQL
    source_tables = table_rows.map { |row| row.fetch("name") }
    copy_order = %w[users products orders order_items]
    tables = (copy_order & source_tables) + (source_tables - copy_order)
    connection = ActiveRecord::Base.connection

    connection.transaction do
    tables.each do |table|
      abort "Refusing to copy into non-empty table #{table}" if connection.select_value("SELECT 1 FROM #{connection.quote_table_name(table)} LIMIT 1")
    end

    source_checksums = {}
    tables.each do |table|
      columns = sqlite_json("PRAGMA table_info(#{connection.quote_table_name(table)})").map { |row| row.fetch("name") }
      rows = sqlite_json("SELECT * FROM #{connection.quote_table_name(table)} ORDER BY rowid")
      source_checksums[table] = checksum(rows)

      rows.each_slice(ENV.fetch("MIGRATION_BATCH_SIZE", 1_000).to_i) do |batch|
        records = batch.map { |row| columns.to_h { |column| [ column, row[column] ] } }
        next if records.empty?

        quoted_columns = columns.map { |column| connection.quote_column_name(column) }.join(", ")
        values = records.map do |record|
          "(#{columns.map { |column| connection.quote(record.fetch(column)) }.join(", ")})"
        end.join(", ")
        connection.execute("INSERT INTO #{connection.quote_table_name(table)} (#{quoted_columns}) VALUES #{values}")
      end
    end

    tables.each do |table|
      id_column = connection.columns(table).find { |column| column.name == "id" }
      next unless id_column

      max_id = connection.select_value("SELECT MAX(id) FROM #{connection.quote_table_name(table)}")
      next unless max_id

      sequence = connection.select_value("SELECT pg_get_serial_sequence(#{connection.quote(table)}, 'id')")
      connection.execute("SELECT setval(#{connection.quote(sequence)}, #{max_id.to_i}, true)") if sequence
    end

    tables.each do |table|
      columns = connection.columns(table).map(&:name)
      rows = connection.select_all("SELECT #{columns.map { |column| connection.quote_column_name(column) }.join(', ')} FROM #{connection.quote_table_name(table)} ORDER BY #{connection.quote_column_name(columns.first)}")
      checksum = checksum(rows)
      count = connection.select_value("SELECT COUNT(*) FROM #{connection.quote_table_name(table)}")
      raise "Checksum mismatch for #{table}: #{source_checksums.fetch(table)} != #{checksum}" unless checksum == source_checksums.fetch(table)

      puts "#{table}: #{count} rows, checksum #{checksum}"
    end
    end

    puts "SQLite to PostgreSQL migration completed from #{source}"
  end
end
