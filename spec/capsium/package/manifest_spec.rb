# frozen_string_literal: true

# spec/capsium/package/manifest_spec.rb
require "spec_helper"
require "capsium/package/manifest"

RSpec.describe Capsium::Package::Manifest do
  let(:build_path) { Dir.mktmpdir }
  let(:manifest_path) { File.join(build_path, "manifest.json") }
  let(:manifest_data) do
    {
      content: [
        { file: "index.html", mime: "text/html" },
        { file: "example.css", mime: "text/css" },
        { file: "example.js", mime: "text/javascript" }
      ]
    }
  end
  let(:manifest) { described_class.new(manifest_path) }

  before do
    File.write(manifest_path, JSON.pretty_generate(manifest_data))
  end

  describe "#initialize" do
    it "loads the manifest data from the file" do
      expect(manifest.to_json).to eq(manifest_data.to_json)
    end
  end
end
