require "shale"

module Capsium
  class Package
    class DatasetConfig < Shale::Mapper
      attribute :name, Shale::Type::String
      attribute :source, Shale::Type::String
      attribute :format, Shale::Type::String
      attribute :schema, Shale::Type::String

      def to_dataset(data_path)
        Dataset.new(config: self, data_path: File.join(File.dirname(data_path), source))
      end

      def self.from_dataset(dataset)
        new(
          name: dataset.config.name,
          source: dataset.config.source,
          format: dataset.config.format,
          schema: dataset.config.schema,
        )
      end
    end
  end
end
