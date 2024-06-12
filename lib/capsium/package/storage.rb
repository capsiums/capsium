# frozen_string_literal: true

# lib/capsium/package/storage.rb
require "json"
require "shale"
require_relative "dataset"
require_relative "storage_config"

module Capsium
  class Package
    class Storage
      extend Forwardable
      attr_reader :config

      def_delegators :@config, :to_json

      attr_reader :datasets

      def initialize(path)
        @path = path
        @dir = File.dirname(path)
        @datasets_path = File.join(@dir, DATA_DIR)
        @config = if File.exist?(path)
                    StorageConfig.from_json(File.read(path))
                  else
                    StorageConfig.new(datasets: generate_datasets)
                  end
        @datasets = load_datasets || generate_datasets
      end

      def load_datasets
        if File.exist?(@path)
          storage_data = StorageConfig.from_json(File.read(@path))
          storage_data.datasets.map do |dataset_config|
            dataset_config.to_dataset(@datasets_path)
          end
        end
      end

      def save_to_file(output_path = @path)
        storage_config = StorageConfig.new(datasets: @datasets.map do |dataset|
                                                       DatasetConfig.from_dataset(dataset)
                                                     end)
        File.write(output_path, storage_config.to_json)
      end

      def generate_datasets
        paths = File.join(@datasets_path, "*.{yaml,yml,json,csv,tsv,sqlite,db}")
        Dir.glob(paths).map do |file_path|
          Dataset.new(config: DatasetConfig.new(
            name: File.basename(file_path,
                                ".*"), source: file_path, format: detect_format(file_path)
          ))
        end
      end

      private

      def detect_format(file_path)
        case File.extname(file_path).downcase
        when ".yaml", ".yml"
          "yaml"
        when ".json"
          "json"
        when ".csv"
          "csv"
        when ".tsv"
          "tsv"
        when ".sqlite", ".db"
          "sqlite"
        else
          raise "Unsupported data file type: #{File.extname(file_path)}"
        end
      end
    end
  end
end
