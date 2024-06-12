# frozen_string_literal: true

require "spec_helper"
require "capsium/package/storage"
require_relative "package_spec_helper"

RSpec.describe Capsium::Package::Storage do
  let(:storage_path) { File.join(Dir.mktmpdir, "storage.json") }
  let(:data_dir) { File.join(File.dirname(storage_path), "data") }
  let(:animals_yaml_path) { File.join(data_dir, "animals.yaml") }
  let(:animals_schema_path) { File.join(data_dir, "animals_schema.yaml") }
  let(:fixtures_animals_yaml_path) do
    File.expand_path(File.join(__dir__, "..", "..", "fixtures", "data_package",
                               "data", "animals.yaml"))
  end
  let(:fixtures_animals_schema_path) do
    File.expand_path(File.join(__dir__, "..", "..", "fixtures", "data_package",
                               "data", "animals_schema.yaml"))
  end

  let(:storage_data) do
    {
      "datasets" => [
        {
          "name" => "animals",
          "source" => "data/animals.yaml",
          "format" => "yaml",
          "schema" => "data/animals_schema.yaml",
        },
      ],
    }
  end
  let(:storage) { described_class.new(storage_path) }

  before do
    FileUtils.mkdir_p(data_dir)
    FileUtils.cp(fixtures_animals_yaml_path, animals_yaml_path)
    FileUtils.cp(fixtures_animals_schema_path, animals_schema_path)
    File.write(storage_path, JSON.pretty_generate(storage_data))
  end

  after do
    FileUtils.rm_rf(File.dirname(storage_path))
  end

  describe "#load_datasets" do
    it "loads datasets correctly from JSON file" do
      datasets = storage.load_datasets
      expect(datasets.map(&:config).map(&:to_hash)).to eq(storage_data["datasets"])
    end
  end

  describe "#save_to_file" do
    it "saves storage data to a JSON file" do
      storage.save_to_file
      saved_data = JSON.parse(File.read(storage_path))
      expect(saved_data).to eq(storage_data)
    end
  end
end
