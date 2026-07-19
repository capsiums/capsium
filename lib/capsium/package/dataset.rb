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
