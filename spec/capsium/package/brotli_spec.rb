# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require "brotli"

RSpec.describe Capsium::Package::Brotli do
  let(:fixtures_path) { File.expand_path("fixtures", File.join(__dir__, "..", "..")) }
  let(:source_path) { File.join(fixtures_path, "bare-package") }

  around do |example|
    Dir.mktmpdir do |dir|
      @workdir = dir
      @package_dir = File.join(@workdir, "pkg")
      FileUtils.cp_r(source_path, @package_dir)
      @package = Capsium::Package.new(@package_dir)
      example.run
    end
  end

  describe ".compressible?" do
    it "true for HTML, CSS, JS, JSON, YAML, SVG" do
      %w[index.html styles.css app.js data.json config.yaml logo.svg].each do |path|
        expect(described_class.compressible?(path)).to be(true), path
      end
    end

    it "false for images, fonts, already-compressed formats" do
      %w[photo.jpg photo.png font.woff2 archive.zip data.db].each do |path|
        expect(described_class.compressible?(path)).to be(false), path
      end
    end

    it "case-insensitive on extensions" do
      expect(described_class.compressible?("INDEX.HTML")).to be(true)
    end
  end

  describe "#generate" do
    it "writes a .br sidecar for every compressible manifest resource" do
      generated = described_class.new(@package).generate
      expect(generated).to include("content/index.html.br")

      sidecar = File.join(@package_dir, "content", "index.html.br")
      expect(File.file?(sidecar)).to be(true)

      original = File.read(File.join(@package_dir, "content", "index.html"))
      inflated = Brotli.inflate(File.binread(sidecar))
      expect(inflated).to eq(original)
    end

    it "does not write sidecars for non-compressible resources" do
      described_class.new(@package).generate
      expect(File.file?(File.join(@package_dir, "manifest.json.br"))).to be(false)
    end

    it "overwrites an existing sidecar" do
      sidecar = File.join(@package_dir, "content", "index.html.br")
      FileUtils.mkdir_p(File.dirname(sidecar))
      File.binwrite(sidecar, "stale bytes")

      described_class.new(@package).generate
      inflated = Brotli.inflate(File.binread(sidecar))
      expect(inflated).to include("<html")
      expect(inflated).not_to include("stale bytes")
    end
  end

  describe ".generate" do
    it "writes sidecars and returns their paths" do
      paths = described_class.generate(@package)
      expect(paths).to include("content/index.html.br")
      paths.each do |relative|
        expect(File.file?(File.join(@package_dir, relative))).to be(true)
      end
    end
  end
end
