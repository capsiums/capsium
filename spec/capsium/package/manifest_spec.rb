# frozen_string_literal: true

# spec/capsium/package/manifest_spec.rb
require "spec_helper"
require "capsium/package/manifest"

RSpec.describe Capsium::Package::Manifest do
  let(:build_path) { Dir.mktmpdir }
  let(:manifest_path) { File.join(build_path, "manifest_test") }
  let(:manifest_data) do
    { content: {
      "index.html" => "text/html",
      "example.css" => "text/css",
      "example.js" => "text/javascript"
    } }
  end
  let(:manifest) { described_class.new(manifest_path) }

  before do
    File.write(manifest_path, JSON.pretty_generate(manifest_data))
  end

  describe "#initialize" do
    it "loads the manifest data from the file" do
      expect(manifest.content).to eq(manifest_data[:content])
    end
  end
end
