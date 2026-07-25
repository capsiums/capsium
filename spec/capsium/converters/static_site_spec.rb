# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "json"
require "tmpdir"

RSpec.shared_examples "a static-site converter" do
  let(:converter_class) { described_class }

  let(:source_dir) do
    dir = Dir.mktmpdir
    write_site(dir)
    dir
  end

  after { FileUtils.remove_entry(source_dir) if File.directory?(source_dir) }

  def write_site(dir)
    FileUtils.mkdir_p(File.join(dir, "about"))
    FileUtils.mkdir_p(File.join(dir, "assets"))
    File.write(File.join(dir, "index.html"), "<html>home</html>")
    File.write(File.join(dir, "about", "index.html"), "<html>about</html>")
    File.write(File.join(dir, "assets", "style.css"), "body {}")
    File.write(File.join(dir, "page.html"), "<html>page</html>")
  end

  def package_json(output_dir, file)
    JSON.parse(File.read(File.join(output_dir, file)))
  end

  describe "#convert" do
    let(:output_dir) { Dir.mktmpdir }
    after { FileUtils.remove_entry(output_dir) if File.directory?(output_dir) }

    let(:result) do
      converter_class.new(source_dir: source_dir, output_dir: output_dir,
                          package_name: "demo-site").convert
    end

    it "produces a Capsium package directory with metadata, routes, content" do
      expect(File.directory?(result.output)).to be(true)
      expect(File.file?(File.join(result.output, "metadata.json"))).to be(true)
      expect(File.file?(File.join(result.output, "routes.json"))).to be(true)
      expect(File.directory?(File.join(result.output, "content"))).to be(true)
    end

    it "names the package via package_name:" do
      expect(package_json(result.output, "metadata.json")["name"]).to eq("demo-site")
    end

    it "sets a guid and matching uuid" do
      metadata = package_json(result.output, "metadata.json")
      expect(metadata["guid"]).to match(/\Aurn:uuid:[0-9a-f-]{36}\z/)
      expect(metadata["uuid"]).to eq(metadata["guid"].sub("urn:uuid:", ""))
    end

    it "routes the root index at /, /index, and /index.html" do
      routes = package_json(result.output, "routes.json")["routes"]
      paths = routes.map { |r| r["path"] }
      expect(paths).to include("/", "/index.html", "/index")
    end

    it "routes folder index.html at the folder basename + /" do
      routes = package_json(result.output, "routes.json")["routes"]
      paths = routes.map { |r| r["path"] }
      expect(paths).to include("/about")
      expect(paths).to include("/about/")
    end

    it "routes <name>.html at /<name> and /<name>.html" do
      routes = package_json(result.output, "routes.json")["routes"]
      paths = routes.map { |r| r["path"] }
      expect(paths).to include("/page")
      expect(paths).to include("/page.html")
    end

    it "routes non-HTML assets at their relative path" do
      routes = package_json(result.output, "routes.json")["routes"]
      resource = routes.find { |r| r["path"] == "/assets/style.css" }
      expect(resource["resource"]).to eq("content/assets/style.css")
    end

    it "copies every asset under content/" do
      expect(File.file?(File.join(result.output, "content", "index.html"))).to be(true)
      expect(File.file?(File.join(result.output, "content", "about", "index.html"))).to be(true)
      expect(File.file?(File.join(result.output, "content", "assets", "style.css"))).to be(true)
    end

    it "produces a validatable package" do
      results = Capsium::Package::Validator.new(result.output).run
      expect(results).to all(be_ok)
    end

    it "returns a result with counts" do
      expect(result.routes_added).to be > 0
      expect(result.assets_copied).to eq(4)
    end
  end

  describe "default output_dir" do
    it "creates <source>-capsium next to the source" do
      parent = File.dirname(source_dir)
      result = converter_class.new(source_dir: source_dir,
                                   package_name: "demo-site").convert
      expected_path = File.expand_path("#{File.basename(source_dir)}-capsium",
                                       parent)
      expect(result.output).to eq(expected_path)
      FileUtils.remove_entry(result.output) if File.directory?(result.output)
    end
  end

  describe "exclude:" do
    let(:output_dir) { Dir.mktmpdir }
    after { FileUtils.remove_entry(output_dir) if File.directory?(output_dir) }

    it "skips files matching the globs" do
      result = converter_class.new(source_dir: source_dir, output_dir: output_dir,
                                   package_name: "demo",
                                   exclude: ["assets/**"]).convert
      routes = package_json(result.output, "routes.json")["routes"]
      paths = routes.map { |r| r["path"] }
      expect(paths.none? { |p| p.start_with?("/assets/") }).to be(true)
    end
  end
end

RSpec.describe Capsium::Converters::StaticSite do
  # The base class is exercised through its subclasses; the shared
  # examples below cover the contract every SSG converter must hold.
end

RSpec.describe Capsium::Converters::Astro do
  include_examples "a static-site converter"
end

RSpec.describe Capsium::Converters::Hugo do
  include_examples "a static-site converter"
end

RSpec.describe Capsium::Converters::NextJs do
  include_examples "a static-site converter"
end
