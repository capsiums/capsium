# frozen_string_literal: true

require "spec_helper"
require "capsium/package/metadata"
require_relative "package_spec_helper"

RSpec.describe Capsium::Package::Metadata do
  let(:metadata_path) { File.join(Dir.mktmpdir, "metadata.json") }
  let(:metadata_data) do
    {
      "identifier" => "capsium://example.com/test-package",
      "uuid" => "550e8400-e29b-41d4-a716-446655440000",
      "name" => "test_package",
      "version" => "0.1.0",
      "description" => "A test package",
      "author" => "Test Author",
      "license" => "MIT",
      "repository" => {
        "type" => "git",
        "url" => "https://github.com/example/test-package.git"
      },
      "accessMode" => {
        "read" => true,
        "write" => false,
        "execute" => false
      },
      "dependencies" => [
        { "name" => "dep1", "version" => "1.0.0" },
        { "name" => "dep2", "version" => "2.0.0" }
      ]
    }
  end
  let(:metadata) { described_class.new(metadata_path) }

  before do
    File.write(metadata_path, JSON.pretty_generate(metadata_data))
  end

  after do
    FileUtils.rm_f(metadata_path)
  end

  describe "#initialize" do
    it "loads metadata correctly from JSON file" do
      expect(metadata.identifier).to eq("capsium://example.com/test-package")
      expect(metadata.uuid).to eq("550e8400-e29b-41d4-a716-446655440000")
      expect(metadata.name).to eq("test_package")
      expect(metadata.version).to eq("0.1.0")
      expect(metadata.description).to eq("A test package")
      expect(metadata.author).to eq("Test Author")
      expect(metadata.license).to eq("MIT")
    end

    it "loads repository data correctly" do
      expect(metadata.repository).to be_a(Capsium::Package::Repository)
      expect(metadata.repository.type).to eq("git")
      expect(metadata.repository.url).to eq(
        "https://github.com/example/test-package.git"
      )
    end

    it "loads access mode correctly" do
      expect(metadata.access_mode).to be_a(Capsium::Package::AccessMode)
      expect(metadata.access_mode.read).to be true
      expect(metadata.access_mode.write).to be false
      expect(metadata.access_mode.execute).to be false
    end

    it "loads dependencies correctly" do
      expect(metadata.dependencies).to be_an(Array)
      expect(metadata.dependencies.size).to eq(2)
      expect(metadata.dependencies[0]).to be_a(Capsium::Package::Dependency)
      expect(metadata.dependencies[0].name).to eq("dep1")
      expect(metadata.dependencies[0].version).to eq("1.0.0")
    end

    context "when file does not exist" do
      let(:new_metadata_path) do
        File.join(Dir.mktmpdir, "new_metadata.json")
      end
      let(:new_metadata) { described_class.new(new_metadata_path) }

      it "creates a new empty metadata config" do
        expect(new_metadata.config).to be_a(
          Capsium::Package::MetadataData
        )
        expect(new_metadata.name).to be_nil
      end
    end
  end

  describe "#to_json" do
    it "serializes metadata to JSON" do
      json_output = metadata.to_json
      parsed = JSON.parse(json_output)

      expect(parsed["identifier"]).to eq(
        "capsium://example.com/test-package"
      )
      expect(parsed["name"]).to eq("test_package")
      expect(parsed["version"]).to eq("0.1.0")
      expect(parsed["repository"]["type"]).to eq("git")
      expect(parsed["accessMode"]["read"]).to be true
    end
  end

  describe "#save_to_file" do
    it "saves metadata data to a JSON file" do
      metadata.save_to_file
      saved_data = JSON.parse(File.read(metadata_path))

      expect(saved_data["identifier"]).to eq(
        "capsium://example.com/test-package"
      )
      expect(saved_data["name"]).to eq("test_package")
      expect(saved_data["repository"]["url"]).to eq(
        "https://github.com/example/test-package.git"
      )
    end

    it "saves to a different path when specified" do
      new_path = File.join(Dir.mktmpdir, "new_metadata.json")
      metadata.save_to_file(new_path)

      expect(File.exist?(new_path)).to be true
      saved_data = JSON.parse(File.read(new_path))
      expect(saved_data["name"]).to eq("test_package")

      FileUtils.rm_f(new_path)
    end
  end

  describe "delegated methods" do
    it "delegates identifier to config" do
      expect(metadata.identifier).to eq(
        metadata.config.identifier
      )
    end

    it "delegates uuid to config" do
      expect(metadata.uuid).to eq(metadata.config.uuid)
    end

    it "delegates author to config" do
      expect(metadata.author).to eq(metadata.config.author)
    end

    it "delegates license to config" do
      expect(metadata.license).to eq(metadata.config.license)
    end

    it "delegates repository to config" do
      expect(metadata.repository).to eq(metadata.config.repository)
    end

    it "delegates access_mode to config" do
      expect(metadata.access_mode).to eq(metadata.config.access_mode)
    end
  end
end

RSpec.describe Capsium::Package::Repository do
  describe "JSON serialization" do
    it "serializes to JSON correctly" do
      repo = described_class.new(
        type: "git",
        url: "https://github.com/example/repo.git"
      )
      json = repo.to_json
      parsed = JSON.parse(json)

      expect(parsed["type"]).to eq("git")
      expect(parsed["url"]).to eq("https://github.com/example/repo.git")
    end

    it "deserializes from JSON correctly" do
      json = '{"type":"svn","url":"https://svn.example.com/repo"}'
      repo = described_class.from_json(json)

      expect(repo.type).to eq("svn")
      expect(repo.url).to eq("https://svn.example.com/repo")
    end
  end
end

RSpec.describe Capsium::Package::AccessMode do
  describe "default values" do
    it "sets read to true by default" do
      access = described_class.new
      expect(access.read).to be true
    end

    it "sets write to false by default" do
      access = described_class.new
      expect(access.write).to be false
    end

    it "sets execute to false by default" do
      access = described_class.new
      expect(access.execute).to be false
    end
  end

  describe "JSON serialization" do
    it "serializes to JSON correctly" do
      access = described_class.new(
        read: true,
        write: true,
        execute: false
      )
      json = access.to_json
      parsed = JSON.parse(json)

      expect(parsed["read"]).to be true
      expect(parsed["write"]).to be true
      expect(parsed["execute"]).to be false
    end

    it "deserializes from JSON correctly" do
      json = '{"read":false,"write":true,"execute":true}'
      access = described_class.from_json(json)

      expect(access.read).to be false
      expect(access.write).to be true
      expect(access.execute).to be true
    end
  end
end

RSpec.describe Capsium::Package::Dependency do
  describe "JSON serialization" do
    it "serializes to JSON correctly" do
      dep = described_class.new(
        name: "example-dep",
        version: "1.2.3"
      )
      json = dep.to_json
      parsed = JSON.parse(json)

      expect(parsed["name"]).to eq("example-dep")
      expect(parsed["version"]).to eq("1.2.3")
    end

    it "deserializes from JSON correctly" do
      json = '{"name":"test-dep","version":"2.0.0"}'
      dep = described_class.from_json(json)

      expect(dep.name).to eq("test-dep")
      expect(dep.version).to eq("2.0.0")
    end
  end
end
