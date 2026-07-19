# frozen_string_literal: true

require "spec_helper"
require_relative "package_spec_helper"

RSpec.describe Capsium::Package::Manifest do
  let(:manifest_dir) { Dir.mktmpdir }
  let(:manifest_path) { File.join(manifest_dir, "manifest.json") }
  let(:manifest_data) do
    {
      "resources" => {
        "content/example.css" => { "type" => "text/css", "visibility" => "exported" },
        "content/example.js" => { "type" => "text/javascript",
                                  "visibility" => "exported" },
        "content/index.html" => { "type" => "text/html", "visibility" => "exported" }
      }
    }
  end
  let(:manifest) { described_class.new(manifest_path) }

  before do
    File.write(manifest_path, JSON.pretty_generate(manifest_data))
  end

  after do
    FileUtils.rm_rf(manifest_dir)
  end

  describe "#initialize" do
    it "loads manifest correctly from JSON file" do
      expect(manifest.resources.keys).to eq(manifest_data["resources"].keys)
      expect(manifest.lookup("content/index.html").type).to eq("text/html")
    end
  end

  describe "#to_json" do
    it "serializes manifest to canonical JSON" do
      expect(JSON.parse(manifest.to_json)).to eq(manifest_data)
    end
  end

  describe "#save_to_file" do
    it "saves manifest data to a JSON file without mutating the model" do
      manifest.save_to_file
      saved_data = JSON.parse(File.read(manifest_path))
      expect(saved_data).to eq(manifest_data)
    end
  end

  describe "legacy form" do
    let(:manifest_data) do
      {
        "content" => [
          { "file" => "content/example.css", "mime" => "text/css" },
          { "file" => "content/index.html", "mime" => "text/html" }
        ]
      }
    end

    it "normalizes the content array to the resources object" do
      expect(JSON.parse(manifest.to_json)).to eq(
        "resources" => {
          "content/example.css" => { "type" => "text/css",
                                     "visibility" => "exported" },
          "content/index.html" => { "type" => "text/html",
                                    "visibility" => "exported" }
        }
      )
    end
  end

  describe "auto-generation" do
    let(:manifest_path) { File.join(manifest_dir, "manifest.json") }

    before do
      FileUtils.rm_f(manifest_path)
      content_dir = File.join(manifest_dir, "content")
      FileUtils.mkdir_p(content_dir)
      File.write(File.join(content_dir, "index.html"), "<html></html>")
      File.write(File.join(content_dir, "styles.css"), "body {}")
      File.write(File.join(content_dir, "app.js"), "console.log(1);")
    end

    it "generates the manifest from a content/ scan, sorted" do
      expect(manifest.resources.keys).to eq(
        %w[content/app.js content/index.html content/styles.css]
      )
    end

    it "detects MIME types and defaults visibility to exported" do
      expect(manifest.lookup("content/app.js").type).to eq("text/javascript")
      expect(manifest.lookup("content/styles.css").type).to eq("text/css")
      expect(manifest.lookup("content/index.html").visibility).to eq("exported")
    end
  end
end
