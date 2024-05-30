# frozen_string_literal: true

require "spec_helper"
require "capsium/package/metadata"

RSpec.describe Capsium::Package::Metadata do
  let(:build_path) { Dir.mktmpdir }
  let(:metadata_path) { File.join(build_path, "metadata_test") }
  let(:metadata_data) do
    { name: "test_package", version: "0.1.0" }
  end
  let(:metadata) { described_class.new(metadata_path) }

  before do
    File.write(metadata_path, JSON.pretty_generate(metadata_data))
  end

  describe "#initialize" do
    it "loads metadata from the file" do
      expect(metadata.name).to eq("test_package")
      expect(metadata.version).to eq("0.1.0")
      expect(metadata.dependencies).to eq({})
    end
  end
end
