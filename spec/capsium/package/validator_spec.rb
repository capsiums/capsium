# frozen_string_literal: true

require "spec_helper"

RSpec.describe Capsium::Package::Validator do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }

  describe "a canonical package directory" do
    it "passes all checks" do
      results = described_class.new(File.join(fixtures_path, "data-package")).run
      expect(results.map(&:name)).to eq(
        %w[metadata manifest routes storage security content]
      )
      expect(results).to all(be_ok)
    end
  end

  describe "a .cap file" do
    it "passes all checks" do
      cap = File.join(fixtures_path, "data-package-0.1.0.cap")
      expect(described_class.new(cap).run).to all(be_ok)
    end
  end

  describe "check failures" do
    let(:package_copy) do
      dir = Dir.mktmpdir
      FileUtils.cp_r(File.join(fixtures_path, "data-package"), dir)
      File.join(dir, "data-package")
    end

    after { FileUtils.rm_rf(File.dirname(package_copy)) }

    it "fails metadata when fields are invalid" do
      metadata = JSON.parse(File.read(File.join(package_copy, "metadata.json")))
      metadata["name"] = "Data_Package"
      File.write(File.join(package_copy, "metadata.json"), JSON.generate(metadata))
      result = check("metadata", package_copy)
      expect(result).not_to be_ok
      expect(result.messages).to include("name must be kebab-case")
    end

    it "fails manifest when a resource is missing on disk" do
      FileUtils.rm(File.join(package_copy, "content", "example.css"))
      FileUtils.rm(File.join(package_copy, "security.json"))
      result = check("manifest", package_copy)
      expect(result).not_to be_ok
      expect(result.messages).to include("resource missing on disk: content/example.css")
    end

    it "fails security when a checksum does not match" do
      File.write(File.join(package_copy, "content", "index.html"), "tampered")
      result = check("security", package_copy)
      expect(result).not_to be_ok
      expect(result.messages).to include("checksum mismatch: content/index.html")
    end

    it "fails storage when a dataset source is missing" do
      FileUtils.rm(File.join(package_copy, "data", "animals.yaml"))
      FileUtils.rm(File.join(package_copy, "security.json"))
      result = check("storage", package_copy)
      expect(result).not_to be_ok
      expect(result.messages).to include(
        "dataset source missing on disk: data/animals.yaml"
      )
    end

    it "fails content on external http(s) references" do
      File.write(
        File.join(package_copy, "content", "external.html"),
        '<script src="https://cdn.example.com/lib.js"></script>'
      )
      FileUtils.rm(File.join(package_copy, "security.json"))
      result = check("content", package_copy)
      expect(result).not_to be_ok
      expect(result.messages).to include("external reference in content/external.html")
    end

    it "fails routes when the index is missing" do
      routes = JSON.parse(File.read(File.join(package_copy, "routes.json")))
      routes.delete("index")
      File.write(File.join(package_copy, "routes.json"), JSON.generate(routes))
      result = check("routes", package_copy)
      expect(result).not_to be_ok
      expect(result.messages).to include("index route is missing")
    end
  end

  def check(name, path)
    described_class.new(path).run.find { |result| result.name == name }
  end
end
