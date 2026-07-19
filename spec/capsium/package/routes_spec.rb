# frozen_string_literal: true

require "spec_helper"
require_relative "package_spec_helper"

RSpec.describe Capsium::Package::Routes do
  let(:package_dir) { Dir.mktmpdir }
  let(:routes_path) { File.join(package_dir, "routes.json") }
  let(:manifest) do
    Capsium::Package::Manifest.new(File.join(package_dir, "manifest.json"))
  end
  let(:storage) do
    Capsium::Package::Storage.new(File.join(package_dir, "storage.json"))
  end
  let(:routes) { described_class.new(routes_path, manifest, storage) }

  after do
    FileUtils.rm_rf(package_dir)
  end

  describe "auto-generation" do
    before do
      content_dir = File.join(package_dir, "content")
      FileUtils.mkdir_p(content_dir)
      File.write(File.join(content_dir, "index.html"), "<html></html>")
      File.write(File.join(content_dir, "about.html"), "<html></html>")
      File.write(File.join(content_dir, "styles.css"), "body {}")
    end

    it "generates HTML dual routes, the index route and static routes" do
      paths = routes.config.routes.map(&:path)
      expect(paths).to eq(
        ["/", "/about", "/about.html", "/index", "/index.html", "/styles.css"]
      )
    end

    it "sets the index to content/index.html" do
      expect(routes.config.index).to eq("content/index.html")
    end

    it "emits deterministic canonical JSON" do
      expect(JSON.parse(routes.to_json)).to eq(
        "index" => "content/index.html",
        "routes" => [
          { "path" => "/", "resource" => "content/index.html" },
          { "path" => "/about", "resource" => "content/about.html" },
          { "path" => "/about.html", "resource" => "content/about.html" },
          { "path" => "/index", "resource" => "content/index.html" },
          { "path" => "/index.html", "resource" => "content/index.html" },
          { "path" => "/styles.css", "resource" => "content/styles.css" }
        ]
      )
    end

    context "with datasets in storage" do
      before do
        File.write(
          File.join(package_dir, "storage.json"),
          JSON.pretty_generate(
            "storage" => {
              "dataSets" => {
                "animals" => { "source" => "data/animals.json" }
              }
            }
          )
        )
        FileUtils.mkdir_p(File.join(package_dir, "data"))
        File.write(File.join(package_dir, "data", "animals.json"), "[]")
      end

      it "adds dataset routes under /api/v1/data/" do
        route = routes.resolve("/api/v1/data/animals")
        expect(route).not_to be_nil
        expect(route.dataset).to eq("animals")
        expect(route.kind).to eq(:dataset)
      end
    end
  end

  describe "legacy form" do
    before do
      File.write(
        routes_path,
        JSON.pretty_generate(
          "routes" => [
            { "path" => "/", "target" => { "file" => "content/index.html" } },
            { "path" => "/api/v1/data/animals",
              "target" => { "dataset" => "animals" } }
          ]
        )
      )
    end

    it "normalizes target forms to route kinds" do
      expect(JSON.parse(routes.to_json)).to eq(
        "routes" => [
          { "path" => "/", "resource" => "content/index.html" },
          { "path" => "/api/v1/data/animals", "dataset" => "animals" }
        ]
      )
    end
  end

  describe "mutators" do
    before do
      File.write(routes_path, JSON.pretty_generate("routes" => []))
    end

    it "adds, resolves, updates, sorts and removes routes" do
      routes.add_route("/b", "content/b.html")
      routes.add_route("/a", "content/a.html")
      expect(routes.resolve("/a").resource).to eq("content/a.html")

      routes.update_route("/a", "/c", "content/c.html")
      expect(routes.resolve("/a")).to be_nil
      expect(routes.resolve("/c").resource).to eq("content/c.html")

      routes.config.sort!
      expect(routes.config.routes.map(&:path)).to eq(%w[/b /c])

      routes.remove_route("/b")
      expect(routes.config.routes.map(&:path)).to eq(%w[/c])
    end
  end

  describe "handler routes" do
    before do
      File.write(
        routes_path,
        JSON.pretty_generate(
          "routes" => [
            { "path" => "/hook", "method" => "post", "handler" => "hook.rb" }
          ]
        )
      )
    end

    it "accepts and parses handler routes" do
      route = routes.resolve("/hook")
      expect(route.kind).to eq(:handler)
      expect(route.http_method).to eq("post")
    end
  end
end
