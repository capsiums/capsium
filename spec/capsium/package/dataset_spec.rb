# frozen_string_literal: true

require "spec_helper"
require_relative "package_spec_helper"

RSpec.describe Capsium::Package::Dataset do
  let(:package_dir) { Dir.mktmpdir }
  let(:data_path) { File.join(package_dir, "data", "animals.yaml") }
  let(:schema_path) { File.join(package_dir, "data", "animals_schema.yaml") }
  let(:dataset_data) do
    "---\nanimals:\n  - name: Lion\n    type: Mammal\n    habitat: Savannah\n"
  end
  let(:schema_data) do
    <<~YAML
      type: object
      properties:
        animals:
          type: array
          items:
            type: object
            properties:
              name:
                type: string
              type:
                type: string
              habitat:
                type: string
            required:
              - name
              - type
              - habitat
      required:
        - animals
    YAML
  end
  let(:config) do
    Capsium::Package::DatasetConfig.new(
      source: "data/animals.yaml",
      schema_file: "data/animals_schema.yaml",
      schema_type: "json-schema"
    )
  end
  let(:dataset) do
    described_class.new(name: "animals", config: config, package_path: package_dir)
  end

  before do
    FileUtils.mkdir_p(File.dirname(data_path))
    File.write(data_path, dataset_data)
    File.write(schema_path, schema_data)
  end

  after do
    FileUtils.rm_rf(package_dir)
  end

  describe "#load_data" do
    it "loads data correctly from YAML file" do
      data = dataset.load_data
      expect(data).to eq(YAML.load_file(data_path))
    end
  end

  describe "#validate" do
    it "validates the dataset against the schema" do
      expect { dataset.validate }.not_to raise_error
    end

    context "when data does not conform to the schema" do
      # Missing 'type' field
      let(:dataset_data) do
        "---\nanimals:\n  - name: Lion\n    habitat: Savannah\n"
      end

      it "raises a validation error" do
        expect do
          dataset.validate
        end.to raise_error(JSON::Schema::ValidationError)
      end
    end
  end

  describe "#validation_errors" do
    it "is empty for a valid dataset" do
      expect(dataset.validation_errors).to be_empty
    end

    context "when the source is missing" do
      before { FileUtils.rm_f(data_path) }

      it "reports the missing source" do
        expect(dataset.validation_errors).to include(
          "dataset source missing on disk: data/animals.yaml"
        )
      end
    end
  end

  describe "format detection" do
    it "derives the format from the source extension" do
      expect(config.format).to eq("yaml")
    end

    it "supports sqlite database files" do
      sqlite_config = Capsium::Package::DatasetConfig.new(
        database_file: "data/sales.db", table: "sales"
      )
      expect(sqlite_config.format).to eq("sqlite")
      expect(sqlite_config.sqlite?).to be(true)
    end
  end
end
