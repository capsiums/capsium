# frozen_string_literal: true

require "spec_helper"
require_relative "package_spec_helper"

RSpec.describe Capsium::Package::Metadata do
  let(:metadata_path) { File.join(Dir.mktmpdir, "metadata.json") }
  let(:metadata_data) do
    {
      "name" => "test-package",
      "version" => "0.1.0",
      "description" => "A test package",
      "guid" => "https://example.com/test-package",
      "uuid" => "123e4567-e89b-12d3-a456-426614174000",
      "dependencies" => { "capsium://example.com/other" => ">=1.0.0" }
    }
  end
  let(:metadata) { described_class.new(metadata_path) }

  before do
    File.write(metadata_path, JSON.pretty_generate(metadata_data))
  end

  after do
    FileUtils.rm_rf(File.dirname(metadata_path))
  end

  describe "#initialize" do
    it "loads metadata correctly from JSON file" do
      expect(metadata.name).to eq("test-package")
      expect(metadata.guid).to eq("https://example.com/test-package")
      expect(metadata.uuid).to eq("123e4567-e89b-12d3-a456-426614174000")
      expect(metadata.dependencies).to eq("capsium://example.com/other" => ">=1.0.0")
    end
  end

  describe "#to_json" do
    it "serializes metadata to canonical JSON" do
      expect(JSON.parse(metadata.to_json)).to eq(metadata_data)
    end
  end

  describe "#save_to_file" do
    it "saves metadata data to a JSON file" do
      metadata.save_to_file
      saved_data = JSON.parse(File.read(metadata_path))
      expect(saved_data).to eq(metadata_data)
    end
  end

  describe "legacy dependencies array" do
    let(:metadata_data) do
      {
        "name" => "test-package",
        "version" => "0.1.0",
        "dependencies" => [{ "name" => "capsium://example.com/other",
                             "version" => ">=1.0.0" }]
      }
    end

    it "normalizes to the object form" do
      expect(metadata.dependencies).to eq("capsium://example.com/other" => ">=1.0.0")
      expect(JSON.parse(metadata.to_json)["dependencies"])
        .to eq("capsium://example.com/other" => ">=1.0.0")
    end
  end
end

RSpec.describe Capsium::Package::MetadataData do
  describe "#format_errors" do
    it "accepts a fully populated canonical document" do
      metadata = described_class.from_json(
        {
          name: "test-package", version: "1.0.0", description: "d",
          guid: "https://example.com/x",
          uuid: "123e4567-e89b-12d3-a456-426614174000"
        }.to_json
      )
      expect(metadata.format_errors).to be_empty
    end

    it "reports missing required fields" do
      metadata = described_class.new(name: "test-package", version: "1.0.0")
      expect(metadata.format_errors).to contain_exactly(
        "description is missing", "guid is missing", "uuid is missing"
      )
    end

    it "reports invalid field formats" do
      metadata = described_class.new(
        name: "Test_Package", version: "1.0", description: "d",
        guid: "https://example.com/x", uuid: "not-a-uuid"
      )
      expect(metadata.format_errors).to contain_exactly(
        "name must be kebab-case", "version must be semver",
        "uuid is not a valid UUID"
      )
    end
  end
end
