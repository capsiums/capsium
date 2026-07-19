# frozen_string_literal: true

require "json"
require "lutaml/model"

module Capsium
  class Package
    # A single dataset entry (ARCHITECTURE.md section 5). Paths are
    # package-relative POSIX paths. Kinds: schema-backed file (via
    # "source") or SQLite ("databaseFile" + "table").
    class DatasetConfig < Lutaml::Model::Serializable
      FORMATS = {
        ".yaml" => "yaml", ".yml" => "yaml", ".json" => "json",
        ".csv" => "csv", ".tsv" => "tsv",
        ".sqlite" => "sqlite", ".db" => "sqlite"
      }.freeze
      SCHEMA_TYPES = %w[json-schema].freeze

      attribute :source, :string
      attribute :schema_file, :string
      attribute :schema_type, :string, values: SCHEMA_TYPES
      attribute :database_file, :string
      attribute :table, :string

      json do
        map :source, to: :source
        map "schemaFile", to: :schema_file
        map "schemaType", to: :schema_type
        map "databaseFile", to: :database_file
        map :table, to: :table
      end

      def format
        FORMATS.fetch(File.extname(backing_file).downcase) do
          raise Error, "Unsupported data file type: #{File.extname(backing_file)}"
        end
      end

      def sqlite?
        !database_file.nil?
      end

      def backing_file
        database_file || source.to_s
      end

      def to_dataset(name, package_path)
        Dataset.new(name: name, config: self, package_path: package_path)
      end
    end

    # The "storage" object holding the dataSets map.
    class StorageData < Lutaml::Model::Serializable
      attribute :data_sets, :hash, default: {}

      json do
        map "dataSets", with: { from: :data_sets_from_json, to: :data_sets_to_json }
      end

      def data_sets_from_json(model, value)
        model.data_sets = (value || {}).to_h do |name, attributes|
          [name, DatasetConfig.from_json(JSON.generate(attributes))]
        end
      end

      def data_sets_to_json(model, doc)
        doc["dataSets"] = model.data_sets.sort.to_h do |name, dataset|
          [name, JSON.parse(dataset.to_json)]
        end
      end
    end

    # Canonical storage.json model. The legacy gem form
    # ({"datasets": [{name, source, format, schema}]}) is accepted on read
    # and normalized; writers emit only the canonical form.
    class StorageConfig < Lutaml::Model::Serializable
      attribute :storage, StorageData

      json do
        map :storage, to: :storage
      end

      def self.from_json(json)
        doc = JSON.parse(json)
        doc["storage"] ||= { "dataSets" => legacy_data_sets(doc.delete("datasets")) }
        super(JSON.generate(doc))
      end

      def self.legacy_data_sets(datasets)
        (datasets || []).to_h do |item|
          entry = { "source" => item["source"] }
          if item["schema"]
            entry["schemaFile"] = item["schema"]
            entry["schemaType"] = "json-schema"
          end
          [item["name"], entry]
        end
      end
      private_class_method :legacy_data_sets

      def data_sets
        storage ? storage.data_sets : {}
      end
    end
  end
end
