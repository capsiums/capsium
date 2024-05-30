# frozen_string_literal: true

# spec/capsium/package/dataset_spec.rb
require "spec_helper"
require "capsium/package/dataset"

RSpec.xdescribe Capsium::Package::Dataset do
  let(:yaml_path) { "/tmp/test_package/data/example.yaml" }
  let(:json_path) { "/tmp/test_package/data/example.json" }
  let(:csv_path) { "/tmp/test_package/data/example.csv" }
  let(:sqlite_path) { "/tmp/test_package/data/example.db" }

  before do
    allow(Dir).to receive(:pwd).and_return("/tmp")
    FileUtils.mkdir_p("/tmp/test_package/data")

    File.write(yaml_path, "---\n- example: data")
    File.write(json_path, '[{"example": "data"}]')
    File.write(csv_path, "example,data\nfoo,bar")
    SQLite3::Database.new(sqlite_path) do |db|
      db.execute <<-SQL
        CREATE TABLE example (
          id INTEGER PRIMARY KEY,
          data TEXT
        );
      SQL
    end
  end

  describe "#initialize" do
    it "determines YAML dataset type" do
      dataset = described_class.new(yaml_path)
      expect(dataset.type).to eq(:yaml)
    end

    it "determines JSON dataset type" do
      dataset = described_class.new(json_path)
      expect(dataset.type).to eq(:json)
    end

    it "determines CSV dataset type" do
      dataset = described_class.new(csv_path)
      expect(dataset.type).to eq(:csv)
    end

    it "determines SQLite dataset type" do
      dataset = described_class.new(sqlite_path)
      expect(dataset.type).to eq(:sqlite)
    end
  end

  describe "#table_name" do
    it "returns the table name for SQLite datasets" do
      dataset = described_class.new(sqlite_path)
      expect(dataset.table_name).to eq("example")
    end

    it "returns nil for non-SQLite datasets" do
      dataset = described_class.new(yaml_path)
      expect(dataset.table_name).to be_nil
    end
  end
end
