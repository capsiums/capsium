# frozen_string_literal: true

require "csv"
require "forwardable"
require "json"
require "json-schema"
require "sqlite3"
require "yaml"

module Capsium
  class Package
    # A loaded dataset. "source"/"schemaFile"/"databaseFile" are
    # package-relative paths (ARCHITECTURE.md section 5), resolved against
    # the package directory.
    class Dataset
      attr_reader :name, :config, :data, :package_path

      extend Forwardable

      def_delegators :@config, :to_json

      def initialize(name:, config:, package_path:)
        @name = name
        @config = config
        @package_path = package_path
        @data = load_data
      end

      def source_path
        File.join(@package_path, @config.backing_file)
      end

      def schema_path
        return unless @config.schema_file

        File.join(@package_path, @config.schema_file)
      end

      def load_data
        return nil unless File.file?(source_path)

        case @config.format
        when "yaml" then YAML.load_file(source_path)
        when "json" then JSON.parse(File.read(source_path))
        when "csv" then CSV.read(source_path, headers: true)
        when "tsv" then CSV.read(source_path, col_sep: "\t", headers: true)
        when "sqlite" then load_sqlite_data
        else
          raise Error, "Unsupported data file type: #{@config.format}"
        end
      end

      def validate
        return true unless @config.schema_file && @config.schema_type == "json-schema"

        JSON::Validator.validate!(load_schema, @data.to_json)
      end

      # PK column for a SQLite dataset's table: the declared PRIMARY KEY
      # column when one exists, falling back to "id" if the table has a
      # column by that name, or nil when neither is present (the reactor
      # then rejects writes with a clear error). PK detection is read
      # against the base DB; the overlay DB is a copy with the same
      # schema, so the column set is identical. Tolerates the PRAGMA
      # result shape changing between Array-of-Arrays and Array-of-Hashes
      # based on the connection's results_as_hash setting.
      def sqlite_pk_column(db = nil)
        return nil unless @config.table

        owns_db = db.nil?
        db ||= SQLite3::Database.new(source_path)
        info = db.execute("PRAGMA table_info(#{@config.table});")
        find_pk_column(info)
      ensure
        db&.close if owns_db
      end

      def find_pk_column(info)
        pk_row = info.find { |row| pragma_value(row, :pk).to_i == 1 }
        pk_row ||= info.find { |row| pragma_value(row, :name) == "id" }
        pk_row && pragma_value(pk_row, :name)
      end
      private :find_pk_column

      # All column names for the configured table, in declaration order.
      def sqlite_columns(db = nil)
        return [] unless @config.table

        owns_db = db.nil?
        db ||= SQLite3::Database.new(source_path)
        db.execute("PRAGMA table_info(#{@config.table});").map do |row|
          pragma_value(row, :name)
        end
      ensure
        db&.close if owns_db
      end

      def pragma_value(row, key)
        return row[key.to_s] if row.is_a?(Hash)
        return row[5] if key == :pk
        return row[1] if key == :name

        nil
      end
      private :pragma_value

      # File-existence and schema validations for this dataset. Returns a
      # list of human-readable problems; empty when valid.
      def validation_errors
        problems = []
        unless File.file?(source_path)
          problems << "dataset source missing on disk: #{@config.backing_file}"
        end
        problems.concat(schema_validation_errors)
        problems
      end

      # The parsed JSON schema for this dataset, or nil when none is
      # declared or the file is unreadable.
      def json_schema
        return nil unless @config.schema_file && @config.schema_type == "json-schema"
        return nil unless File.file?(schema_path)

        load_schema
      end

      # Schema validation of an arbitrary candidate document (used by
      # the reactor's writable overlay before persisting a mutation):
      # human-readable schema problems, empty when valid or when the
      # dataset has no JSON schema.
      def schema_errors_for(data)
        return [] unless @config.schema_file && @config.schema_type == "json-schema"
        return [] unless File.file?(schema_path)

        JSON::Validator.fully_validate(load_schema, JSON.parse(JSON.generate(data)))
      end

      private

      def schema_validation_errors
        return [] unless @config.schema_file
        unless File.file?(schema_path)
          return ["dataset schema missing on disk: #{@config.schema_file}"]
        end

        validate
        []
      rescue JSON::Schema::ValidationError => e
        ["dataset #{@name} fails schema validation: #{e.message}"]
      end

      def load_schema
        case File.extname(schema_path).downcase
        when ".yaml", ".yml" then YAML.load_file(schema_path)
        else JSON.parse(File.read(schema_path))
        end
      end

      def load_sqlite_data
        db = SQLite3::Database.new(source_path)
        db.results_as_hash = true
        tables = @config.table ? [@config.table] : sqlite_tables(db)
        tables.to_h do |table_name|
          [table_name, db.execute("SELECT * FROM #{table_name};")]
        end
      ensure
        db&.close
      end

      def sqlite_tables(db)
        db.execute("SELECT name FROM sqlite_master WHERE type='table';").map(&:first)
      end
    end
  end
end
