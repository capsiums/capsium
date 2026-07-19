# frozen_string_literal: true

require "forwardable"

module Capsium
  class Package
    class Storage
      extend Forwardable

      attr_reader :path, :config, :datasets

      def_delegators :@config, :to_json, :to_hash

      def initialize(path)
        @path = path
        @dir = File.dirname(path)
        @config = if File.exist?(path)
                    StorageConfig.from_json(File.read(path))
                  else
                    StorageConfig.new
                  end
        @datasets = load_datasets
      end

      def data_sets
        @config.data_sets
      end

      def load_datasets
        data_sets.map do |name, dataset_config|
          dataset_config.to_dataset(name, @dir)
        end
      end

      def dataset(name)
        @datasets.find { |dataset| dataset.name == name }
      end

      def dataset_names
        data_sets.keys.sort
      end

      def empty?
        data_sets.empty?
      end

      def save_to_file(output_path = @path)
        File.write(output_path, to_json)
      end
    end
  end
end
