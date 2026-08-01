# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"

RSpec.describe Capsium::Cli::Init do
  describe ".templates" do
    it "lists the bundled templates" do
      expect(described_class.templates)
        .to include("static-site", "dataset-app", "blog", "quiz", "portfolio",
                    "docs-site", "photo-gallery")
    end

    it "every template resolves to a real directory under templates/" do
      described_class.templates.each do |name|
        path = File.join(described_class::TEMPLATES_DIR, name)
        expect(File.directory?(path)).to be(true)
      end
    end

    it "every template carries a metadata.json with the {{name}} placeholder" do
      described_class.templates.each do |name|
        metadata_path = File.join(described_class::TEMPLATES_DIR, name, "metadata.json")
        expect(File.file?(metadata_path)).to be(true)
        expect(File.read(metadata_path)).to include("{{name}}")
      end
    end
  end

  describe ".call" do
    it "scaffolds a static-site package from the template" do
      Dir.mktmpdir do |dir|
        result = described_class.call(template: "static-site",
                                      name: "my-site",
                                      parent_dir: dir)
        expect(result.name).to eq("my-site")
        expect(result.template).to eq("static-site")
        expect(File.directory?(result.path)).to be(true)
        expect(File.file?(File.join(result.path, "metadata.json"))).to be(true)
        expect(File.file?(File.join(result.path, "content", "index.html"))).to be(true)
      end
    end

    # Every bundled template must scaffold to a structurally valid
    # package: metadata.json with the substituted name, plus either a
    # routes.json declaring an index route OR the auto-route-friendly
    # content/index.html that the reactor generates routes from.
    # Parameterized so adding a new template automatically gets coverage.
    described_class.templates.each do |template_name|
      it "scaffolds the #{template_name} template to a valid package shape" do
        Dir.mktmpdir do |dir|
          result = described_class.call(template: template_name,
                                        name: "pkg-from-#{template_name}",
                                        parent_dir: dir)
          metadata = JSON.parse(File.read(File.join(result.path, "metadata.json")))
          expect(metadata["name"]).to eq("pkg-from-#{template_name}")
          expect(metadata["guid"]).to match(%r{\A(urn:uuid:|https?://)})

          routes_path = File.join(result.path, "routes.json")
          if File.file?(routes_path)
            routes = JSON.parse(File.read(routes_path))
            index_route = routes["routes"].find { |r| r["path"] == "/" }
            expect(index_route).not_to be_nil
          else
            # Templates without routes.json rely on the reactor's
            # auto-route generation from content/index.html.
            expect(File.file?(File.join(result.path, "content", "index.html"))).to be(true)
          end
        end
      end
    end

    it "substitutes {{name}} and {{uuid}} placeholders in every file" do
      Dir.mktmpdir do |dir|
        described_class.call(template: "static-site", name: "demo-site",
                             parent_dir: dir)
        metadata = JSON.parse(File.read(File.join(dir, "demo-site", "metadata.json")))
        expect(metadata["name"]).to eq("demo-site")
        expect(metadata["guid"]).to match(/\Aurn:uuid:[0-9a-f-]{36}\z/)

        html = File.read(File.join(dir, "demo-site", "content", "index.html"))
        expect(html).to include("<title>demo-site</title>")
        expect(html).to include("<h1>demo-site</h1>")
        expect(html).not_to include("{{")
      end
    end

    it "scaffolds a dataset-app with a schema-backed dataset" do
      Dir.mktmpdir do |dir|
        described_class.call(template: "dataset-app", name: "data-demo",
                             parent_dir: dir)
        storage_path = File.join(dir, "data-demo", "storage.json")
        expect(File.file?(storage_path)).to be(true)

        storage = JSON.parse(File.read(storage_path))
        expect(storage["storage"]["dataSets"]["items"]["schemaFile"])
          .to eq("data/items_schema.json")
      end
    end

    it "produces a validatable static-site package" do
      Dir.mktmpdir do |dir|
        described_class.call(template: "static-site", name: "validatable",
                             parent_dir: dir)
        results = Capsium::Package::Validator
                  .new(File.join(dir, "validatable")).run
        expect(results).to all(be_ok)
      end
    end

    it "raises ArgumentError for an unknown template" do
      expect { described_class.call(template: "nope", name: "x") }
        .to raise_error(ArgumentError, /unknown template/)
    end

    it "raises ArgumentError for an invalid name" do
      expect { described_class.call(template: "static-site", name: "../escape") }
        .to raise_error(ArgumentError, /invalid name/)
      expect { described_class.call(template: "static-site", name: "with space") }
        .to raise_error(ArgumentError, /invalid name/)
      expect { described_class.call(template: "static-site", name: "") }
        .to raise_error(ArgumentError, /invalid name/)
    end

    it "raises ArgumentError when the target directory already exists" do
      Dir.mktmpdir do |dir|
        described_class.call(template: "static-site", name: "exists",
                             parent_dir: dir)
        expect do
          described_class.call(template: "static-site", name: "exists",
                               parent_dir: dir)
        end
          .to raise_error(ArgumentError, /target already exists/)
      end
    end

    it "uses a unique UUID for each invocation" do
      Dir.mktmpdir do |dir|
        described_class.call(template: "static-site", name: "first",
                             parent_dir: dir)
        described_class.call(template: "static-site", name: "second",
                             parent_dir: dir)
        first_guid = JSON.parse(File.read(File.join(dir, "first", "metadata.json")))["guid"]
        second_guid = JSON.parse(File.read(File.join(dir, "second", "metadata.json")))["guid"]
        expect(first_guid).not_to eq(second_guid)
      end
    end
  end
end
