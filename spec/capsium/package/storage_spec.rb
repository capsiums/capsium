# frozen_string_literal: true

# spec/capsium/package/storage_spec.rb
require "spec_helper"
require "capsium/package/storage"

RSpec.xdescribe Capsium::Package::Storage do
  let(:storage_path) { "/tmp/test_package/storage.json" }
  let(:storage_data) { { datasets: [] } }
  let(:storage) { described_class.new("/tmp/test_package") }

  before do
    allow(Dir).to receive(:pwd).and_return("/tmp")
    FileUtils.mkdir_p("/tmp/test_package")
    File.write(storage_path, JSON.pretty_generate(storage_data))
  end

  describe "#initialize" do
    it "loads the storage data from the file" do
      expect(storage.datasets).to eq([])
    end
  end

  describe "#add_dataset" do
    it "adds a dataset to the storage" do
      dataset_info = { source: "example.yaml", format: "yaml" }
      storage.add_dataset("example", dataset_info)
      expect(storage.datasets).to include(hash_including(name: "example", source: "example.yaml", format: "yaml"))
    end
  end
end
