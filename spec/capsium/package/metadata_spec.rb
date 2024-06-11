# frozen_string_literal: true

require "spec_helper"
require "capsium/package/metadata"
require_relative "package_spec_helper"

RSpec.describe Capsium::Package::Metadata do
  let(:metadata_path) { File.join(Dir.mktmpdir, "metadata.json") }
  let(:metadata_data) { { "name" => "test_package", "version" => "0.1.0", "dependencies" => [] } }
  let(:metadata) { described_class.new(metadata_path) }

  before do
    File.write(metadata_path, JSON.pretty_generate(metadata_data))
  end

  after do
    File.delete(metadata_path) if File.exist?(metadata_path)
  end

  describe "#initialize" do
    it "loads metadata correctly from JSON file" do
      data = metadata.config.to_hash
      expect(data).to eq(metadata_data)
    end
  end

  describe "#to_json" do
    it "serializes metadata to JSON" do
      json_data = metadata.to_json
      expect(json_data).to eq(metadata_data.to_json)
    end
  end

  describe "#save_to_file" do
    it "saves metadata data to a JSON file" do
      metadata.save_to_file
      saved_data = JSON.parse(File.read(metadata_path))
      expect(saved_data).to eq(metadata_data)
    end
  end
end
