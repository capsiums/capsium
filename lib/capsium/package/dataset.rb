# frozen_string_literal: true

# lib/capsium/package/dataset.rb
require "json"
require "yaml"
require "csv"
require "sqlite3"

module Capsium
  class Package
    class Dataset < Shale::Mapper
      # {
      #   "datasets": [
      #     {
      #       "name": "animals",
      #       "source": "data/animals.yaml",
      #       "format": "yaml",
      #       "schema": "data/animals_schema.yaml"
      #     }
      #   ]
      # }
      attr_reader :name, :path, :type, :data

      def initialize(path, data_path)
        @path = path
        @name = File.basename(@path, ".*")
        @type = detect_type
        @data_path = data_path
        @data = load_data
      end

      def detect_type
        case File.extname(@path).downcase
        when /.ya?ml/ then :yaml
        when ".json" then :json
        when ".csv" then :csv
        when ".tsv" then :tsv
        when ".sqlite", ".db" then :sqlite
        else
          raise "Unsupported data file type: #{File.extname(@path)}"
        end
      end

      def load_data
        case @type
        when :yaml then YAML.load_file(@path)
        when :json then JSON.parse(File.read(@path))
        when :csv then CSV.read(@path, headers: true)
        when :tsv then CSV.read(@path, col_sep: "\t", headers: true)
        when :sqlite then load_sqlite_data
        else
          raise "Unsupported data file type: #{@type}"
        end
      end

      def as_json
        {
          name: name,
          source: relative_path(path),
          format: type.to_s
        }
      end

      def to_json(*_args)
        JSON.pretty_generate(as_json)
      end

      def relative_path(path)
        Pathname.new(path).relative_path_from(@data_path).to_s
      end

      private

      def load_sqlite_data
        db = SQLite3::Database.new(@path)
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
