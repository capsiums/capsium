# frozen_string_literal: true

require "spec_helper"
require "capsium/package/manifest"
require_relative "package_spec_helper"

RSpec.describe Capsium::Package::Manifest do
  let(:manifest_path) { File.join(Dir.mktmpdir, "manifest.json") }
  let(:manifest_data) do
    {
      "content" => [
        { "file" => "example.css", "mime" => "text/css" },
        { "file" => "example.js", "mime" => "application/javascript" },
        { "file" => "index.html", "mime" => "text/html" },
      ],
    }
  end
  let(:manifest) { described_class.new(manifest_path) }

  before do
    File.write(manifest_path, JSON.pretty_generate(manifest_data))
  end

  after do
    FileUtils.rm_f(manifest_path)
  end

  describe "#initialize" do
    it "loads manifest correctly from JSON file" do
      data = manifest.config.content
      expect(data.map(&:to_hash)).to eq(manifest_data["content"])
    end
  end

  describe "#to_json" do
    it "serializes manifest to JSON" do
      json_data = manifest.to_json
      expect(json_data).to eq(manifest_data.to_json)
    end
  end

  describe "#save_to_file" do
    it "saves manifest data to a JSON file" do
      manifest.save_to_file
      saved_data = JSON.parse(File.read(manifest_path))
      expect(saved_data).to eq(manifest_data)
    end
  end
end
