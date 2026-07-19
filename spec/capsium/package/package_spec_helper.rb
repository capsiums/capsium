# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "json"

RSpec.shared_context "package setup" do |package_name, package_version, format|
  let(:fixtures_path) do
    File.expand_path(File.join(__dir__, "..", "..", "fixtures"))
  end
  let(:package_path) do
    case format
    when :directory
      File.join(fixtures_path, package_name)
    when :cap_file
      File.join(fixtures_path, "#{package_name}-#{package_version}.cap")
    else
      raise ArgumentError, "Invalid format: #{format}"
    end
  end
  let(:package) { Capsium::Package.new(package_path) }
end

RSpec.shared_examples "a package loader" do |metadata_data, manifest_data,
                                             routes_data, storage_data = nil|
  it "loads metadata correctly" do
    expect(package.metadata.name).to eq(metadata_data[:name])
    expect(package.metadata.version).to eq(metadata_data[:version])
    expect(package.metadata.dependencies).to eq(metadata_data[:dependencies])
  end

  it "builds manifest correctly" do
    expect(JSON.parse(package.manifest.to_json)).to eq(manifest_data)
  end

  it "builds routes correctly" do
    expect(JSON.parse(package.routes.to_json)).to eq(routes_data)
  end

  it "passes integrity verification" do
    expect(package.verify_integrity).to be_empty
  end

  if storage_data
    it "loads storage correctly" do
      expect(JSON.parse(package.storage.to_json)).to eq(storage_data)
    end

    it "saves storage to file correctly" do
      Dir.mktmpdir do |dir|
        storage_path = File.join(dir, "storage.json")

        package.storage.save_to_file(storage_path)
        expect(File).to exist(storage_path)

        saved_data = JSON.parse(File.read(storage_path))
        expect(saved_data).to eq(storage_data)
      end
    end

    it "loads datasets from the storage" do
      expect(package.storage.datasets.size).to be > 0
    end
  end
end
