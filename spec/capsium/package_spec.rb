# frozen_string_literal: true

require "spec_helper"
require_relative "package/package_spec_helper"

bare_manifest = {
  "resources" => {
    "content/example.css" => { "type" => "text/css", "visibility" => "exported" },
    "content/example.js" => { "type" => "text/javascript", "visibility" => "exported" },
    "content/index.html" => { "type" => "text/html", "visibility" => "exported" }
  }
}.freeze

data_manifest = {
  "resources" => {
    "content/example.css" => { "type" => "text/css", "visibility" => "exported" },
    "content/example.html" => { "type" => "text/html", "visibility" => "exported" },
    "content/example.js" => { "type" => "text/javascript", "visibility" => "exported" },
    "content/index.html" => { "type" => "text/html", "visibility" => "exported" }
  }
}.freeze

bare_routes = {
  "index" => "content/index.html",
  "routes" => [
    { "path" => "/", "resource" => "content/index.html" },
    { "path" => "/example.css", "resource" => "content/example.css" },
    { "path" => "/example.js", "resource" => "content/example.js" },
    { "path" => "/index", "resource" => "content/index.html" },
    { "path" => "/index.html", "resource" => "content/index.html" }
  ]
}.freeze

data_routes = {
  "index" => "content/index.html",
  "routes" => [
    { "path" => "/", "resource" => "content/index.html" },
    { "path" => "/api/v1/data/animals", "dataset" => "animals" },
    { "path" => "/example", "resource" => "content/example.html" },
    { "path" => "/example.css", "resource" => "content/example.css" },
    { "path" => "/example.html", "resource" => "content/example.html" },
    { "path" => "/example.js", "resource" => "content/example.js" },
    { "path" => "/index", "resource" => "content/index.html" },
    { "path" => "/index.html", "resource" => "content/index.html" }
  ]
}.freeze

data_storage = {
  "storage" => {
    "dataSets" => {
      "animals" => {
        "source" => "data/animals.yaml",
        "schemaFile" => "data/animals_schema.yaml",
        "schemaType" => "json-schema"
      }
    }
  }
}.freeze

RSpec.describe Capsium::Package do
  context "with a bare package as directory" do
    include_context "package setup", "bare-package", "0.1.0", :directory

    describe "loading and processing" do
      include_examples "a package loader",
                       { name: "bare-package", version: "0.1.0", dependencies: {} },
                       bare_manifest, bare_routes

      it "tracks the load type correctly" do
        expect(package.load_type).to eq(:directory)
      end
    end
  end

  context "with a data package as directory" do
    include_context "package setup", "data-package", "0.1.0", :directory

    describe "loading and processing" do
      include_examples "a package loader",
                       { name: "data-package", version: "0.1.0", dependencies: {} },
                       data_manifest, data_routes, data_storage

      it "tracks the load type correctly" do
        expect(package.load_type).to eq(:directory)
      end
    end
  end

  context "with a bare package as .cap file" do
    include_context "package setup", "bare-package", "0.1.0", :cap_file

    describe "loading and processing" do
      include_examples "a package loader",
                       { name: "bare-package", version: "0.1.0", dependencies: {} },
                       bare_manifest, bare_routes

      it "tracks the load type correctly" do
        expect(package.load_type).to eq(:cap_file)
      end
    end
  end

  context "with a data package as .cap file" do
    include_context "package setup", "data-package", "0.1.0", :cap_file

    describe "loading and processing" do
      include_examples "a package loader",
                       { name: "data-package", version: "0.1.0", dependencies: {} },
                       data_manifest, data_routes, data_storage

      it "tracks the load type correctly" do
        expect(package.load_type).to eq(:cap_file)
      end
    end
  end

  context "with a legacy-format package as directory" do
    include_context "package setup", "legacy-package", "0.1.0", :directory

    it "normalizes legacy dependencies to the object form" do
      expect(package.metadata.dependencies).to eq(
        "capsium://example.com/other-pkg" => ">=1.0.0"
      )
    end

    it "normalizes the legacy manifest to the resources object form" do
      expect(JSON.parse(package.manifest.to_json)).to eq(
        "resources" => {
          "content/index.html" => { "type" => "text/html", "visibility" => "exported" }
        }
      )
    end

    it "normalizes legacy route targets to route kinds" do
      expect(JSON.parse(package.routes.to_json)).to eq(
        "routes" => [
          { "path" => "/", "resource" => "content/index.html" },
          { "path" => "/api/v1/data/animals", "dataset" => "animals" },
          { "path" => "/index", "resource" => "content/index.html" },
          { "path" => "/index.html", "resource" => "content/index.html" }
        ]
      )
    end

    it "normalizes the legacy storage to the dataSets object form" do
      expect(JSON.parse(package.storage.to_json)).to eq(data_storage)
    end
  end

  describe "integrity verification on load" do
    let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "fixtures")) }

    it "rejects a package whose content was tampered with after packing" do
      Dir.mktmpdir do |dir|
        tampered = File.join(dir, "data-package")
        FileUtils.cp_r(File.join(fixtures_path, "data-package"), tampered)
        File.write(File.join(tampered, "content", "index.html"),
                   "<html>tampered</html>")

        expect { Capsium::Package.new(tampered) }
          .to raise_error(Capsium::Package::Security::IntegrityError, /index\.html/)
      end
    end
  end
end
