# frozen_string_literal: true

require "fileutils"
require "json"
require "sqlite3"

module Capsium
  class Reactor
    class Overlay
      # SQLite copy-on-write operations mixed into Overlay. Kept in a
      # separate module so the JSON-collection path and the SQLite path
      # don't share private helpers (different invariants, different
      # failure modes). The Overlay class handles the dataset-kind
      # branch; this module owns the SQLite-specific mechanics.
      #
      # The overlay's @root and data_root are inherited from the
      # including Overlay instance.
      module SqliteOps
        private

        def sqlite_overlay_path(dataset)
          File.join(data_root, "#{dataset.name}.db")
        end

        def sqlite_overlay?(dataset)
          File.file?(sqlite_overlay_path(dataset))
        end

        # Returns the overlay DB path, copying from the base on first
        # call. Idempotent. Raises UnsupportedDatasetError when the base
        # database is missing.
        def ensure_sqlite_overlay(dataset)
          path = sqlite_overlay_path(dataset)
          return path if File.file?(path)

          base = dataset.source_path
          unless File.file?(base)
            raise UnsupportedDatasetError,
                  "dataset #{dataset.name} base database missing"
          end

          FileUtils.mkdir_p(data_root)
          FileUtils.cp(base, path)
          path
        end

        def sqlite_dataset_data(dataset)
          return dataset.data unless sqlite_overlay?(dataset)

          with_sqlite(dataset) do |db|
            { dataset.config.table => db.execute("SELECT * FROM #{dataset.config.table};") }
          end
        end

        def sqlite_collection(dataset)
          with_sqlite(dataset) do |db|
            db.execute("SELECT * FROM #{dataset.config.table};")
          end
        end

        def sqlite_item(dataset, id)
          with_sqlite(dataset) do |db|
            pk = sqlite_pk!(dataset, db)
            row = db.execute(
              "SELECT * FROM #{dataset.config.table} WHERE #{pk} = ?;", id
            ).first
            unless row
              raise ItemNotFoundError,
                    "no item #{id} in dataset #{dataset.name}"
            end

            row
          end
        end

        def sqlite_append_item(dataset, item)
          require_hash!(dataset, item)

          with_sqlite(dataset) do |db|
            pk = sqlite_pk!(dataset, db)
            reject_duplicate!(dataset, db, pk, item)
            cols, values = sqlite_insert_columns(dataset, db, pk, item)
            sqlite_insert(dataset, db, cols, values)
            (item.key?(pk) ? item[pk] : db.last_insert_row_id).to_s
          end
        end

        def sqlite_replace_item(dataset, id, item)
          require_hash!(dataset, item)

          with_sqlite(dataset) do |db|
            pk = sqlite_pk!(dataset, db)
            require_existing!(dataset, db, pk, id)
            reject_pk_mismatch!(dataset, pk, id, item)
            reject_unknown_columns!(dataset, db, item)
            assignments, values = sqlite_update_columns(db, pk, item)
            sqlite_update(dataset, db, pk, id, assignments, values) if assignments
            db.execute(
              "SELECT * FROM #{dataset.config.table} WHERE #{pk} = ?;", id
            ).first
          end
        end

        def sqlite_delete_item(dataset, id)
          with_sqlite(dataset) do |db|
            pk = sqlite_pk!(dataset, db)
            db.execute(
              "DELETE FROM #{dataset.config.table} WHERE #{pk} = ?;", id
            )
            if db.changes.zero?
              raise ItemNotFoundError,
                    "no item #{id} in dataset #{dataset.name}"
            end

            nil
          end
        end

        def sqlite_query(dataset, query)
          with_sqlite(dataset) do |db|
            sql_spec = query.to_sql
            rows = sqlite_select(dataset, db, sql_spec)
            total = sqlite_count(dataset, db, sql_spec)
            {
              items: rows,
              total: total,
              etag: DataApi::CollectionQuery.etag_for(rows, total)
            }
          end
        end

        def sqlite_select(dataset, db, spec)
          sql = "SELECT * FROM #{dataset.config.table}"
          sql += " WHERE #{spec[:where].join(' AND ')}" unless spec[:where].empty?
          sql += " ORDER BY #{spec[:order]}" if spec[:order]
          sql += " LIMIT #{spec[:limit].to_i} OFFSET #{spec[:offset].to_i}"
          db.execute(sql, spec[:params])
        end

        def sqlite_count(dataset, db, spec)
          sql = "SELECT COUNT(*) FROM #{dataset.config.table}"
          sql += " WHERE #{spec[:where].join(' AND ')}" unless spec[:where].empty?
          row = db.execute(sql, spec[:params]).first
          row.is_a?(Hash) ? row.values.first.to_i : row.first.to_i
        end
        private :sqlite_select, :sqlite_count

        def with_sqlite(dataset)
          path = if sqlite_overlay?(dataset)
                   sqlite_overlay_path(dataset)
                 else
                   ensure_sqlite_overlay(dataset)
                 end
          db = SQLite3::Database.new(path)
          db.results_as_hash = true
          yield db
        ensure
          db&.close
        end

        def sqlite_pk!(dataset, db)
          pk = dataset.sqlite_pk_column(db)
          return pk if pk

          raise UnsupportedDatasetError,
                "dataset #{dataset.name} has no primary key column; " \
                "cannot address items"
        end

        def sqlite_columns(dataset, db)
          dataset.sqlite_columns(db)
        end

        def require_hash!(dataset, item)
          return if item.is_a?(Hash)

          raise UnsupportedDatasetError,
                "dataset #{dataset.name} item body must be a JSON object"
        end

        def reject_unknown_columns!(dataset, db, item)
          columns = sqlite_columns(dataset, db)
          unknown = item.keys.map(&:to_s) - columns
          return if unknown.empty?

          raise UnsupportedDatasetError,
                "dataset #{dataset.name} columns not in table: #{unknown.join(', ')}"
        end

        def reject_duplicate!(dataset, db, pk, item)
          return unless item.key?(pk)

          existing = db.execute(
            "SELECT 1 FROM #{dataset.config.table} WHERE #{pk} = ? LIMIT 1;",
            item[pk]
          ).any?
          return unless existing

          raise ConflictError,
                "item id #{item[pk]} already exists in #{dataset.name}"
        end

        def require_existing!(dataset, db, pk, id)
          existing = db.execute(
            "SELECT 1 FROM #{dataset.config.table} WHERE #{pk} = ? LIMIT 1;", id
          ).any?
          return if existing

          raise ItemNotFoundError,
                "no item #{id} in dataset #{dataset.name}"
        end

        def reject_pk_mismatch!(dataset, pk, id, item)
          return unless item.key?(pk) && item[pk].to_s != id.to_s

          raise ConflictError,
                "body #{pk} #{item[pk]} does not match #{id} " \
                "in dataset #{dataset.name}"
        end

        def sqlite_insert_columns(dataset, db, pk, item)
          columns = sqlite_columns(dataset, db)
          provided = item.keys.map(&:to_s)
          cols = (columns & provided) - [pk]
          cols << pk if item.key?(pk)
          values = cols.map { |c| item[c] }
          [cols, values]
        end

        def sqlite_update_columns(_db, pk, item)
          provided = item.keys.map(&:to_s) - [pk]
          values = provided.map { |c| item[c] }
          assignments = provided.map { |c| "#{c} = ?" }.join(", ")
          [assignments, values]
        end

        def sqlite_insert(dataset, db, cols, values)
          placeholders = cols.map { "?" }.join(", ")
          db.execute(
            "INSERT INTO #{dataset.config.table} " \
            "(#{cols.join(', ')}) VALUES (#{placeholders});",
            values
          )
        end

        def sqlite_update(dataset, db, pk, id, assignments, values)
          db.execute(
            "UPDATE #{dataset.config.table} SET #{assignments} " \
            "WHERE #{pk} = ?;",
            values + [id]
          )
        end
      end
    end
  end
end
