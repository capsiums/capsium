# frozen_string_literal: true

require "spec_helper"
require "digest"
require_relative "package_spec_helper"

RSpec.describe Capsium::Package::Security do
  let(:package_dir) { Dir.mktmpdir }

  before do
    FileUtils.mkdir_p(File.join(package_dir, "content"))
    File.write(File.join(package_dir, "metadata.json"), "{}")
    File.write(File.join(package_dir, "content", "index.html"), "<html></html>")
  end

  after do
    FileUtils.rm_rf(package_dir)
  end

  describe ".generate" do
    let(:security) { described_class.generate(package_dir) }

    it "checksums every package file except security.json" do
      File.write(File.join(package_dir, "security.json"), "{}")
      checksums = security.checksums
      expect(checksums.keys).to contain_exactly("content/index.html", "metadata.json")
    end

    it "computes SHA-256 hex digests" do
      expected = Digest::SHA256.file(File.join(package_dir, "metadata.json")).hexdigest
      expect(security.checksums["metadata.json"]).to eq(expected)
    end

    it "serializes to the canonical security.json form" do
      expect(JSON.parse(security.to_json)).to eq(
        "security" => {
          "integrityChecks" => {
            "checksumAlgorithm" => "SHA-256",
            "checksums" => security.checksums
          }
        }
      )
    end
  end

  describe "#verify" do
    let!(:security) do
      described_class.generate(package_dir).tap(&:save_to_file)
    end

    it "accepts an untampered package" do
      described_class.new(security.path)
      expect(security.verify(package_dir)).to be_empty
    end

    it "rejects a modified file" do
      File.write(File.join(package_dir, "content", "index.html"), "tampered")
      errors = security.verify(package_dir)
      expect(errors.map(&:path)).to eq(["content/index.html"])
      expect(errors.first).to be_a(described_class::ChecksumMismatch)
      expect(errors.first.message).to eq("checksum mismatch: content/index.html")
    end

    it "rejects a missing file" do
      FileUtils.rm(File.join(package_dir, "metadata.json"))
      errors = security.verify(package_dir)
      expect(errors.first).to be_a(described_class::MissingFile)
    end

    it "rejects an unchecked (added) file" do
      File.write(File.join(package_dir, "content", "extra.js"), "x")
      errors = security.verify(package_dir)
      expect(errors.first).to be_a(described_class::UncheckedFile)
    end

    it "raises IntegrityError from verify!" do
      File.write(File.join(package_dir, "content", "index.html"), "tampered")
      expect { security.verify!(package_dir) }
        .to raise_error(described_class::IntegrityError)
    end
  end

  describe "#present?" do
    it "is false when no security.json exists" do
      security = described_class.new(File.join(package_dir, "security.json"))
      expect(security.present?).to be(false)
      expect(security.checksums).to eq({})
    end
  end
end
