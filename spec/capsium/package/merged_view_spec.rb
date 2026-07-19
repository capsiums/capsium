# frozen_string_literal: true

require "spec_helper"

RSpec.describe Capsium::Package::MergedView do
  let(:fixtures_path) do
    File.expand_path(File.join(__dir__, "..", "..", "fixtures"))
  end

  context "with a multi-layer package (ARCHITECTURE.md section 5a)" do
    let(:package_path) { File.join(fixtures_path, "layered-package") }
    let(:package) { Capsium::Package.new(package_path) }
    let(:view) { package.merged_view }

    it "stacks the implicit content/ layer below the configured layers" do
      expect(view.layers.map(&:root)).to eq(
        %w[content base updates].map { |dir| File.join(package_path, dir) }
      )
    end

    it "resolves from the topmost layer providing the file" do
      expect(view.resolve("content/shared.css"))
        .to eq(File.join(package_path, "updates", "shared.css"))
    end

    it "falls through to a middle layer" do
      expect(view.resolve("content/base-only.txt"))
        .to eq(File.join(package_path, "base", "base-only.txt"))
    end

    it "falls through to the implicit content/ layer" do
      expect(view.resolve("content/local.txt"))
        .to eq(File.join(package_path, "content", "local.txt"))
    end

    it "resolves files that exist only in an upper layer" do
      expect(view.resolve("content/extra.js"))
        .to eq(File.join(package_path, "updates", "extra.js"))
    end

    it "resolves tombstoned paths to nil even though a lower layer has them" do
      expect(view.resolve("content/index.html")).to be_nil
    end

    it "never resolves the tombstone file itself" do
      expect(view.resolve("content/.capsium-tombstones")).to be_nil
    end

    it "returns nil for unknown content paths" do
      expect(view.resolve("content/nope.txt")).to be_nil
    end

    it "returns nil for non-content paths" do
      expect(view.resolve("data/animals.yaml")).to be_nil
    end
  end

  context "with a package without a layers config (single implicit layer)" do
    let(:package_path) { File.join(fixtures_path, "bare-package") }
    let(:package) { Capsium::Package.new(package_path) }
    let(:view) { package.merged_view }

    it "behaves as the single content/ layer" do
      expect(view.layers.size).to eq(1)
      expect(view.layers.first.root).to eq(File.join(package_path, "content"))
    end

    it "resolves content files exactly like direct content/ access" do
      expect(view.resolve("content/index.html"))
        .to eq(File.join(package_path, "content", "index.html"))
      expect(view.resolve("content/example.css"))
        .to eq(File.join(package_path, "content", "example.css"))
    end
  end

  context "with a malformed tombstone file" do
    it "raises a Capsium::Error naming the file" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "content"))
        File.write(File.join(dir, "content", ".capsium-tombstones"), "{not json")
        storage = Capsium::Package::Storage.new(File.join(dir, "storage.json"))
        manifest = Capsium::Package::Manifest.new(File.join(dir, "manifest.json"))

        expect { described_class.new(dir, storage: storage, manifest: manifest) }
          .to raise_error(Capsium::Error, /Malformed .capsium-tombstones/)
      end
    end
  end

  context "with an exported-only view (what dependent packages see)" do
    let(:package_path) { File.join(fixtures_path, "layered-package") }
    let(:package) { Capsium::Package.new(package_path) }
    let(:view) { package.merged_view(exported_only: true) }

    it "hides private layers entirely, including their tombstones" do
      # "updates" is private: its override of shared.css and its new files
      # disappear, and its index.html tombstone no longer applies.
      expect(view.layers.map(&:root)).to eq(
        %w[content base].map { |dir| File.join(package_path, dir) }
      )
      expect(view.resolve("content/shared.css"))
        .to eq(File.join(package_path, "base", "shared.css"))
      expect(view.resolve("content/extra.js")).to be_nil
      expect(view.resolve("content/index.html"))
        .to eq(File.join(package_path, "content", "index.html"))
    end

    it "hides resources whose manifest visibility is private" do
      expect(view.resolve("content/local.txt")).to be_nil
    end
  end
end
