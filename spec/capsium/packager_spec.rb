# frozen_string_literal: true

require "spec_helper"
require "capsium/packager"
require "fileutils"
require "tmpdir"

RSpec.describe Capsium::Packager do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "fixtures")) }
  let(:tmpdir) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir)
  end

  shared_examples "a packager" do |package_name, package_version, expected_files|
    let(:original_dir) { File.join(fixtures_path, package_name) }
    let(:existing_cap_file) { File.join(fixtures_path, "#{package_name}-#{package_version}.cap") }
    let(:temporary_package_dir) { File.join(tmpdir, package_name) }

    before do
      FileUtils.cp_r(original_dir, temporary_package_dir)
    end

    it "packages the directory into a .cap file" do
      package = Capsium::Package.new(temporary_package_dir)
      cap_file = described_class.new.pack(package, force: true)
      expect(cap_file).not_to be_nil
      expect(File).to exist(cap_file)
    end

    it "extracts the .cap file into a directory" do
      package = Capsium::Package.new(temporary_package_dir)
      cap_file = described_class.new.pack(package, force: true)
      expect(cap_file).not_to be_nil
      extract_dir = File.join(tmpdir, "extracted_package")
      described_class.new.unpack(cap_file, extract_dir)

      expected_files.each do |file|
        expect(File).to exist(File.join(extract_dir, file))
      end
    end

    it "ensures the extracted files match the original files" do
      package = Capsium::Package.new(temporary_package_dir)
      cap_file = described_class.new.pack(package, force: true)
      expect(cap_file).not_to be_nil
      extract_dir = File.join(tmpdir, "extracted_package")
      described_class.new.unpack(cap_file, extract_dir)

      expected_files.each do |file|
        original_content = File.read(File.join(temporary_package_dir, file))
        extracted_content = File.read(File.join(extract_dir, file))

        if file.end_with?(".json")
          original_content = JSON.pretty_generate(JSON.parse(original_content))
          extracted_content = JSON.pretty_generate(JSON.parse(extracted_content))
        end

        expect(extracted_content).to eq(original_content)
      end
    end

    it "extracts an existing .cap file into a directory" do
      extract_dir = File.join(tmpdir, "extracted_existing_package")
      described_class.new.unpack(existing_cap_file, extract_dir)

      expected_files.each do |file|
        expect(File).to exist(File.join(extract_dir, file))
      end
    end

    it "ensures the extracted files from an existing .cap match the original files" do
      extract_dir = File.join(tmpdir, "extracted_existing_package")
      described_class.new.unpack(existing_cap_file, extract_dir)

      expected_files.each do |file|
        original_content = File.read(File.join(temporary_package_dir, file))
        extracted_content = File.read(File.join(extract_dir, file))

        if file.end_with?(".json")
          original_content = JSON.pretty_generate(JSON.parse(original_content))
          extracted_content = JSON.pretty_generate(JSON.parse(extracted_content))
        end

        expect(extracted_content).to eq(original_content)
      end
    end
  end

  context "with a bare package" do
    let(:package_name) { "bare_package" }
    let(:package_version) { "0.1.0" }
    let(:expected_files) do
      [
        "content/index.html",
        "content/example.css",
        "content/example.js",
        "metadata.json",
      ]
    end

    it_behaves_like "a packager", "bare_package", "0.1.0", [
      "content/index.html",
      "content/example.css",
      "content/example.js",
      "metadata.json",
    ]
  end

  context "with a data package" do
    let(:package_name) { "data_package" }
    let(:package_version) { "0.1.0" }
    let(:expected_files) do
      [
        "content/index.html",
        "content/example.css",
        "content/example.js",
        "metadata.json",
        "data/animals.yaml",
        "data/animals_schema.yaml",
        "storage.json",
      ]
    end

    it_behaves_like "a packager", "data_package", "0.1.0", [
      "content/index.html",
      "content/example.css",
      "content/example.js",
      "metadata.json",
      "data/animals.yaml",
      "data/animals_schema.yaml",
      "storage.json",
    ]
  end
end
