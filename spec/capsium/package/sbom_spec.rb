# frozen_string_literal: true

require "spec_helper"
require "digest"
require "fileutils"
require "json"
require "tmpdir"

RSpec.describe Capsium::Package::Sbom do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }
  let(:package_path) { File.join(fixtures_path, "bare-package") }
  let(:package) { Capsium::Package.new(package_path) }
  let(:sbom) { described_class.new(package) }

  describe "#to_h" do
    let(:doc) { sbom.to_h }

    it "emits SPDX 2.3" do
      expect(doc[:spdxVersion]).to eq("SPDX-2.3")
    end

    it "uses the SPDXRef-DOCUMENT root ID" do
      expect(doc[:SPDXID]).to eq("SPDXRef-DOCUMENT")
    end

    it "names the document after the package and version" do
      expect(doc[:name]).to eq("#{package.metadata.name}-#{package.metadata.version}")
    end

    it "records the packager as the creator" do
      expect(doc[:creationInfo][:creators]).to include("Tool: capsium-packager")
    end

    it "uses CC0-1.0 as the document data license (SPDX convention)" do
      expect(doc[:dataLicense]).to eq("CC0-1.0")
    end

    it "exposes one package entry with the package's metadata" do
      expect(doc[:packages].size).to eq(1)
      pkg = doc[:packages].first
      expect(pkg[:name]).to eq(package.metadata.name)
      expect(pkg[:versionInfo]).to eq(package.metadata.version.to_s)
      expect(pkg[:packageFileName])
        .to eq("#{package.metadata.name}-#{package.metadata.version}.cap")
    end

    it "lists every manifest resource as a file with its sha256" do
      files = doc[:files]
      expect(files.length).to eq(package.manifest.resources.size)

      entry = files.find { |f| f[:fileName] == "content/index.html" }
      expect(entry).not_to be_nil
      checksum = entry.dig(:checksums, 0, :checksumValue)
      expected = Digest::SHA256.file(File.join(package_path, "content", "index.html")).hexdigest
      expect(checksum).to eq(expected)
      expect(entry.dig(:checksums, 0, :algorithm)).to eq("SHA256")
    end
  end

  describe "#to_json" do
    it "round-trips through JSON.parse" do
      roundtripped = JSON.parse(sbom.to_json, symbolize_names: true)
      expect(roundtripped[:spdxVersion]).to eq("SPDX-2.3")
    end
  end

  describe ".generate" do
    after { FileUtils.rm_f(File.join(package_path, described_class::SBOM_FILE)) }

    it "writes the SBOM file into the package directory" do
      path = described_class.generate(package)
      expect(path).to eq(File.join(package_path, described_class::SBOM_FILE))
      expect(File.file?(path)).to be(true)

      doc = JSON.parse(File.read(path))
      expect(doc["spdxVersion"]).to eq("SPDX-2.3")
      expect(doc["packages"].first["name"]).to eq(package.metadata.name)
    end
  end

  describe "determinism" do
    it "produces identical JSON across two Sbom instances for the same package" do
      first = described_class.new(package).to_json
      second = described_class.new(package).to_json
      expect(first).to eq(second)
    end
  end
end
