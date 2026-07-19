# frozen_string_literal: true

require "spec_helper"
require_relative "package_spec_helper"

RSpec.describe Capsium::Package::Storage do
  let(:storage_dir) { Dir.mktmpdir }
  let(:storage_path) { File.join(storage_dir, "storage.json") }
  let(:data_dir) { File.join(storage_dir, "data") }
  let(:fixtures_path) do
    File.expand_path(File.join(__dir__, "..", "..", "fixtures", "data-package"))
  end

  let(:storage_data) do
    {
      "storage" => {
        "dataSets" => {
          "animals" => {
            "source" => "data/animals.yaml",
            "schemaFile" => "data/animals_schema.yaml",
            "schemaType" => "json-schema"
          }
        }
      }
    }
  end
  let(:storage) { described_class.new(storage_path) }

  before do
    FileUtils.mkdir_p(data_dir)
    FileUtils.cp(File.join(fixtures_path, "data", "animals.yaml"), data_dir)
    FileUtils.cp(File.join(fixtures_path, "data", "animals_schema.yaml"), data_dir)
    File.write(storage_path, JSON.pretty_generate(storage_data))
  end

  after do
    FileUtils.rm_rf(storage_dir)
  end

  describe "#load_datasets" do
    it "loads datasets correctly from JSON file" do
      expect(storage.dataset_names).to eq(%w[animals])
      dataset = storage.dataset("animals")
      expect(dataset.config.source).to eq("data/animals.yaml")
      expect(dataset.config.schema_file).to eq("data/animals_schema.yaml")
      expect(dataset.config.format).to eq("yaml")
    end
  end

  describe "#to_json" do
    it "serializes storage to canonical JSON" do
      expect(JSON.parse(storage.to_json)).to eq(storage_data)
    end
  end

  describe "#save_to_file" do
    it "saves storage data to a JSON file" do
      storage.save_to_file
      saved_data = JSON.parse(File.read(storage_path))
      expect(saved_data).to eq(storage_data)
    end
  end

  describe "legacy form" do
    let(:storage_data) do
      {
        "datasets" => [
          {
            "name" => "animals",
            "source" => "data/animals.yaml",
            "format" => "yaml",
            "schema" => "data/animals_schema.yaml"
          }
        ]
      }
    end

    it "normalizes the datasets array to the dataSets object" do
      expect(JSON.parse(storage.to_json)).to eq(
        "storage" => {
          "dataSets" => {
            "animals" => {
              "source" => "data/animals.yaml",
              "schemaFile" => "data/animals_schema.yaml",
              "schemaType" => "json-schema"
            }
          }
        }
      )
    end
  end
end
