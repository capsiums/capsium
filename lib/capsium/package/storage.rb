# frozen_string_literal: true

# lib/capsium/package/storage.rb
require "json"

module Capsium
  class Package
    class Storage
      attr_reader :datasets

      DATA_DIR = "data"

      def initialize(path)
        @path = path
        @dir = File.dirname(path)
        @datasets_path = File.join(@dir, DATA_DIR)
        @datasets = load_datasets || generate_datasets
      end

      def load_datasets
        return unless File.exist?(@path)

        storage_data = JSON.parse(File.read(@path))
        @datasets = storage_data["storage"]
      end

      def as_json
        { datasets: datasets.map(&:as_json) }
      end

      def to_json(*_args)
        JSON.pretty_generate(as_json)
      end

      def save_to_file(output_path = @path)
        File.open(output_path, "w") do |file|
          file.write(to_json)
        end
      end

      def generate_datasets
        datasets = []
        paths = File.join(@datasets_path, "*.{yaml,yml,json,csv,tsv,sqlite,db}")
        Dir.glob(paths).each do |file_path|
          datasets << Dataset.new(file_path, @datasets_path)
          # dataset_info[:table] = dataset.table_name if dataset.type == :sqlite
        end
        datasets
      end
    end
  end
end
