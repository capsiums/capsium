# frozen_string_literal: true

require "json"
require "yaml"
require "csv"
require "sqlite3"
require "shale"
require "json-schema"
require_relative "dataset_config"

module Capsium
  class Package
    class Dataset
      attr_reader :config, :data, :data_path

      extend Forwardable

      def_delegators :@config, :to_json

      def initialize(config:, data_path: nil)
        @config = config
        @data_path = data_path || config.source
        @data = load_data
      end

      def load_data
        case @config.format
        when "yaml" then YAML.load_file(@data_path)
        when "json" then JSON.parse(File.read(@data_path))
        when "csv" then CSV.read(@data_path, headers: true)
        when "tsv" then CSV.read(@data_path, col_sep: "\t", headers: true)
        when "sqlite" then load_sqlite_data
        else
          raise "Unsupported data file type: #{@config.format}"
        end
      end

      def validate
        return unless @config.schema

        schema_path = File.join(File.dirname(@data_path), @config.schema)
        schema = YAML.load_file(schema_path) if @config.format == "yaml"
        schema = JSON.parse(File.read(schema_path)) if @config.format == "json"

        case @config.format
        when "yaml" then YAML.load_file(@data_path)
        when "json" then JSON.parse(File.read(@data_path))
        else
          raise "Validation is only supported for YAML and JSON formats"
        end

        JSON::Validator.validate!(schema, @data.to_json)
      end

      def save_to_file(output_path)
        File.write(output_path, to_json)
      end

      private

      def load_sqlite_data
        db = SQLite3::Database.new(@data_path)
        tables = db.execute("SELECT name FROM sqlite_master WHERE type='table';")
        data = {}
        tables.each do |table|
          table_name = table.first
          data[table_name] = db.execute("SELECT * FROM #{table_name};")
        end
        data
      end
    end
  end
end
