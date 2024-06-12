# frozen_string_literal: true

require "spec_helper"
require "capsium/package/dataset"
require "capsium/package/dataset_config"
require_relative "package_spec_helper"

RSpec.describe Capsium::Package::Dataset do
  let(:data_path) { File.join(Dir.mktmpdir, "animals.yaml") }
  let(:schema_path) do
    File.join(File.dirname(data_path), "animals_schema.yaml")
  end
  let(:config_path) { File.join(Dir.mktmpdir, "dataset_config.json") }
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
  let(:config_data) do
    {
      name: "animals",
      source: "animals.yaml",
      format: "yaml",
      schema: "animals_schema.yaml",
    }
  end
  let(:config) do
    Capsium::Package::DatasetConfig.new(
      name: "animals",
      source: "animals.yaml",
      format: "yaml",
      schema: "animals_schema.yaml",
    )
  end
  let(:dataset) { described_class.new(config: config, data_path: data_path) }

  before do
    File.write(data_path, dataset_data)
    File.write(schema_path, schema_data)
    File.write(config_path, config_data.to_json)
  end

  after do
    FileUtils.rm_f(data_path)
    FileUtils.rm_f(schema_path)
    FileUtils.rm_f(config_path)
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

  describe "#to_json" do
    it "serializes dataset to JSON" do
      json_data = dataset.to_json
      expected_data = config_data.to_json
      expect(json_data).to eq(expected_data)
    end
  end

  describe "#save_to_file" do
    it "saves dataset data to a JSON file" do
      json_path = "#{data_path.chomp('.yaml')}.json"
      dataset.save_to_file(json_path)
      saved_data = JSON.parse(File.read(json_path), symbolize_names: true)
      expected_data = config_data
      expect(saved_data).to eq(expected_data)
    end
  end
end
