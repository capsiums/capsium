# frozen_string_literal: true

# spec/capsium/package_spec.rb
require "spec_helper"
require "capsium/package"

RSpec.describe Capsium::Package do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "fixtures")) }

  context "package with minimal content" do
    let(:package_name) { "bare_package" }
    let(:package_path) { File.join(build_path, package_name) }
    let(:content_dir) { File.join(package_path, "content") }
    let(:metadata_path) { File.join(package_path, "metadata.json") }
    let(:metadata_data) { { name: package_name, version: "0.1.0" } }
    let(:metadata_data_dependencies) { {} }
    let(:content_html) { "<html>  <body>    Hello    </body>  </html>" }
    let(:content_css) { "body { color: red; }" }
    let(:content_js) { "function test() { return true; }" }

    let(:manifest_data) do
      {
        content: [
          { file: "example.css", mime: "text/css" },
          { file: "example.js", mime: "text/javascript" },
          { file: "index.html", mime: "text/html" },
        ]
      }
    end

    let(:routes_data) do
      {
        routes: {
          "/" => "index.html",
          "/index" => "index.html",
          "/index.html" => "index.html",
          "/example.css" => "example.css",
          "/example.js" => "example.js"
        }
      }
    end

    describe "generates missing information (manifest, routes)" do
      let(:build_path) { Dir.mktmpdir }
      let(:package) { described_class.new(package_path) }

      before do
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "index.html"), JSON.pretty_generate(content_html))
        File.write(File.join(content_dir, "example.css"), JSON.pretty_generate(content_css))
        File.write(File.join(content_dir, "example.js"), JSON.pretty_generate(content_js))
        File.write(metadata_path, JSON.pretty_generate(metadata_data))
      end

      after do
        FileUtils.remove_entry(build_path)
      end

      it "loads metadata" do
        expect(package.metadata.name).to eq(metadata_data[:name])
        expect(package.metadata.version).to eq(metadata_data[:version])
        expect(package.metadata.dependencies).to eq(metadata_data_dependencies)
      end

      it "builds manifest" do
        content = package.manifest
        expect(content.to_json).to eq(manifest_data.to_json)
      end

      it "builds routes" do
        content = package.routes.as_json
        expect(content).to eq(routes_data)
      end
    end

    describe "loads as directory" do
      let(:package_path) { File.join(fixtures_path, package_name) }
      let(:package) { described_class.new(package_path) }

      it "loads metadata" do
        expect(package.metadata.name).to eq(metadata_data[:name])
        expect(package.metadata.version).to eq(metadata_data[:version])
        expect(package.metadata.dependencies).to eq(metadata_data_dependencies)
      end

      it "builds manifest" do
        content = package.manifest
        expect(content.to_json).to eq(manifest_data.to_json)
      end

      it "builds routes" do
        content = package.routes.as_json
        expect(content).to eq(routes_data)
      end
    end

    describe "loads as .cap file" do
      let(:package_path) { File.join(fixtures_path, "#{metadata_data[:name]}-#{metadata_data[:version]}.cap") }
      let(:package) { described_class.new(package_path) }

      it "loads metadata" do
        expect(package.metadata.name).to eq(metadata_data[:name])
        expect(package.metadata.version).to eq(metadata_data[:version])
        expect(package.metadata.dependencies).to eq(metadata_data_dependencies)
      end

      it "builds manifest" do
        content = package.manifest
        expect(content.to_json).to eq(manifest_data.to_json)
      end

      it "builds routes" do
        content = package.routes.as_json
        expect(content).to eq(routes_data)
      end
    end

    # describe '#add_dataset' do
    #   it 'adds a dataset to the storage' do
    #     package = described_class.new(package_path)
    #     dataset_info = { source: 'example.yaml', format: 'yaml' }
    #     package.add_dataset('example', dataset_info)
    #     expect(package.storage.datasets).to include(hash_including(name: 'example', source: 'example.yaml', format: 'yaml'))
    #   end
    # end
  end

  xcontext "package with data" do
    let(:package_name) { "data_package" }
    let(:package_path) { File.join(build_path, package_name) }
    let(:content_dir) { File.join(package_path, "content") }
    let(:metadata_path) { File.join(package_path, "metadata.json") }
    let(:metadata_data) { { name: package_name, version: "0.1.0" } }
    let(:metadata_data_dependencies) { {} }
    let(:storage_path) { File.join(package_path, "storage.json") }
    let(:storage_data) do
      { datasets: [
        {
          "name": "animals",
          "source": "animals.yaml",
          "format": "yaml",
          "schema": "animals_schema.yaml"
        }
      ] }
    end
    let(:content_html) { "<html>  <body>    Hello    </body>  </html>" }
    let(:content_css) { "body { color: red; }" }
    let(:content_js) { "function test() { return true; }" }

    let(:manifest_data) do
      {
        content: [
          { file: "example.css", mime: "text/css" },
          { file: "example.js", mime: "text/javascript" },
          { file: "index.html", mime: "text/html" },
        ]
      }
    end

    let(:routes_data) do
      {
        routes: {
          "/" => "index.html",
          "/index" => "index.html",
          "/index.html" => "index.html",
          "/example.css" => "example.css",
          "/example.js" => "example.js",
          "/api/v1/data/animals" => { "type" => "dataset", "name" => "animals" }
        }
      }
    end

    describe "generates missing information (manifest, routes)" do
      let(:build_path) { Dir.mktmpdir }
      let(:package) { described_class.new(package_path) }

      before do
        FileUtils.mkdir_p(content_dir)
        File.write(File.join(content_dir, "index.html"), JSON.pretty_generate(content_html))
        File.write(File.join(content_dir, "example.css"), JSON.pretty_generate(content_css))
        File.write(File.join(content_dir, "example.js"), JSON.pretty_generate(content_js))
        File.write(metadata_path, JSON.pretty_generate(metadata_data))
        File.write(storage_path, JSON.pretty_generate(storage_data))
      end

      after do
        FileUtils.remove_entry(build_path)
      end

      it "loads metadata" do
        expect(package.metadata.name).to eq(metadata_data[:name])
        expect(package.metadata.version).to eq(metadata_data[:version])
        expect(package.metadata.dependencies).to eq(metadata_data_dependencies)
      end

      it "builds manifest" do
        content = package.manifest
        expect(content.to_json).to eq(manifest_data.to_json)
      end

      it "builds routes" do
        content = package.routes.as_json
        expect(content).to eq(routes_data)
      end

      it "loads storage" do
        content = package.storage.as_json
        expect(content).to eq(storage_data)
      end
    end

    describe "loads as directory" do
      let(:package_path) { File.join(fixtures_path, package_name) }
      let(:package) { described_class.new(package_path) }

      it "loads metadata" do
        expect(package.metadata.name).to eq(metadata_data[:name])
        expect(package.metadata.version).to eq(metadata_data[:version])
        expect(package.metadata.dependencies).to eq(metadata_data_dependencies)
      end

      it "builds manifest" do
        content = package.manifest
        expect(content.to_json).to eq(manifest_data.to_json)
      end

      it "builds routes" do
        content = package.routes.as_json
        expect(content).to eq(routes_data)
      end

      it "loads storage" do
        content = package.storage.as_json
        expect(content).to eq(storage_data)
      end
    end

    describe "loads as .cap file" do
      let(:package_path) { File.join(fixtures_path, "#{metadata_data[:name]}-#{metadata_data[:version]}.cap") }
      let(:package) { described_class.new(package_path) }

      it "loads metadata" do
        expect(package.metadata.name).to eq(metadata_data[:name])
        expect(package.metadata.version).to eq(metadata_data[:version])
        expect(package.metadata.dependencies).to eq(metadata_data_dependencies)
      end

      it "builds manifest" do
        content = package.manifest
        expect(content.to_json).to eq(manifest_data.to_json)
      end

      it "builds routes" do
        content = package.routes.as_json
        expect(content).to eq(routes_data)
      end

      it "loads storage" do
        content = package.storage.as_json
        expect(content).to eq(storage_data)
      end
    end
  end
end
