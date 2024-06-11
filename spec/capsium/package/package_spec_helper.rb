# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require "json"

RSpec.shared_context "package setup" do |package_name, package_version, format|
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }
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

RSpec.shared_examples "a package loader" do |metadata_data, manifest_data, routes_data, storage_data = nil|
  it "loads metadata correctly" do
    expect(package.metadata.name).to eq(metadata_data[:name])
    expect(package.metadata.version).to eq(metadata_data[:version])
    expect(package.metadata.dependencies).to eq(metadata_data[:dependencies])
  end

  it "builds manifest correctly" do
    content = package.manifest
    expect(sorted_pretty_json(content.to_json)).to eq(sorted_pretty_json(manifest_data.to_json))
  end

  it "builds routes correctly" do
    content = package.routes.to_json
    parsed_content = JSON.parse(content, symbolize_names: true)
    sorted_content_routes = parsed_content[:routes].sort_by { |route| route[:path] }
    sorted_expected_routes = routes_data[:routes].sort_by { |route| route[:path] }
    expect(sorted_content_routes).to eq(sorted_expected_routes)
  end

  if storage_data
    it "loads storage correctly" do
      content = package.storage.to_json
      expect(sorted_pretty_json(content)).to eq(sorted_pretty_json(storage_data.to_json))
    end

    it "saves storage to file correctly" do
      Dir.mktmpdir do |dir|
        storage_path = File.join(dir, "storage.json")

        package.storage.save_to_file(storage_path)
        expect(File).to exist(storage_path)

        saved_data = JSON.parse(File.read(storage_path), symbolize_names: true)
        expect(saved_data).to eq(storage_data)
      end
    end

    it "handles missing datasets correctly" do
      Dir.mktmpdir do |dir|
        storage_path = File.join(dir, "storage.json")

        File.delete(storage_path) if File.exist?(storage_path)
        expect(package.storage.datasets.size).to be > 0
      end
    end
  end
end

def sorted_pretty_json(json_str)
  JSON.pretty_generate(sort_json(JSON.parse(json_str)))
end

def sort_json(obj)
  case obj
  when Array
    obj.map { |e| sort_json(e) }.sort_by { |e| e.is_a?(Hash) && e["file"] ? e["file"] : e }
  when Hash
    obj.keys.sort.each_with_object({}) do |key, result|
      result[key] = sort_json(obj[key])
    end
  else
    obj
  end
end
