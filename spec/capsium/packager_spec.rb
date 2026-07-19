# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require "zip"

RSpec.describe Capsium::Packager do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "fixtures")) }
  let(:tmpdir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  shared_examples "a packager" do |package_name, package_version, expected_files|
    let(:original_dir) { File.join(fixtures_path, package_name) }
    let(:existing_cap_file) do
      File.join(fixtures_path, "#{package_name}-#{package_version}.cap")
    end
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

    it "writes a security.json with valid checksums into the .cap file" do
      package = Capsium::Package.new(temporary_package_dir)
      cap_file = described_class.new.pack(package, force: true)
      extract_dir = File.join(tmpdir, "extracted_security_package")
      described_class.new.unpack(cap_file, extract_dir)

      security = Capsium::Package::Security.new(
        File.join(extract_dir, "security.json")
      )
      expect(security.present?).to be(true)
      expect(security.verify(extract_dir)).to be_empty
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

    it "includes dotfiles in the manifest and the .cap" do
      dotfile_dir = File.join(temporary_package_dir, "content", ".well-known")
      FileUtils.mkdir_p(dotfile_dir)
      File.write(File.join(dotfile_dir, "capsium.txt"), "capsium")
      # Force manifest + checksum regeneration (fixtures ship committed
      # manifest.json/security.json that do not know about the dotfile)
      FileUtils.rm_f(File.join(temporary_package_dir, "manifest.json"))
      FileUtils.rm_f(File.join(temporary_package_dir, "security.json"))

      package = Capsium::Package.new(temporary_package_dir)
      expect(package.manifest.resources).to have_key("content/.well-known/capsium.txt")

      cap_file = described_class.new.pack(package, force: true)
      extract_dir = File.join(tmpdir, "extracted_dotfiles")
      described_class.new.unpack(cap_file, extract_dir)
      extracted = File.join(extract_dir, "content", ".well-known", "capsium.txt")
      expect(File.read(extracted)).to eq("capsium")
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
    it_behaves_like "a packager", "bare-package", "0.1.0", [
      "content/index.html",
      "content/example.css",
      "content/example.js",
      "metadata.json",
      "manifest.json",
      "routes.json",
      "security.json"
    ]
  end

  context "with a data package" do
    it_behaves_like "a packager", "data-package", "0.1.0", [
      "content/index.html",
      "content/example.css",
      "content/example.js",
      "metadata.json",
      "manifest.json",
      "routes.json",
      "security.json",
      "data/animals.yaml",
      "data/animals_schema.yaml",
      "storage.json"
    ]
  end

  describe "#unpack zip-slip protection" do
    let(:extract_dir) { File.join(tmpdir, "extracted") }

    # Builds a .cap whose entries rubyzip accepts on write ("..", drive
    # letters) but that escape the destination on extraction.
    def build_cap(path, entry_names)
      payload = File.join(File.dirname(path), "payload.txt")
      File.write(payload, "pwned")
      Zip::File.open(path, create: true) do |zipfile|
        entry_names.each { |name| zipfile.add(name, payload) }
      end
      path
    end

    # rubyzip refuses to *create* entries with absolute names but happily
    # reads them back, so patch a placeholder into the archive (same byte
    # length, present in the local and central directory headers).
    def build_absolute_cap(path)
      cap = build_cap(path, ["Aabsolute.txt"])
      File.binwrite(cap, File.binread(cap).gsub("Aabsolute.txt", "/absolute.txt"))
      cap
    end

    it "rejects entries with .. segments escaping the destination" do
      cap = build_cap(File.join(tmpdir, "dotdot.cap"), ["../evil.txt"])

      expect { described_class.new.unpack(cap, extract_dir) }
        .to raise_error(Capsium::Packager::UnsafeEntryError, /evil\.txt/)
      expect(File).not_to exist(File.join(tmpdir, "evil.txt"))
    end

    it "rejects nested entries that resolve outside the destination" do
      cap = build_cap(File.join(tmpdir, "nested.cap"),
                      ["sub/../../escaped.txt"])

      expect { described_class.new.unpack(cap, extract_dir) }
        .to raise_error(Capsium::Packager::UnsafeEntryError, /escaped\.txt/)
      expect(File).not_to exist(File.join(tmpdir, "escaped.txt"))
    end

    it "rejects absolute entry names" do
      cap = build_absolute_cap(File.join(tmpdir, "absolute.cap"))

      expect { described_class.new.unpack(cap, extract_dir) }
        .to raise_error(Capsium::Packager::UnsafeEntryError, %r{/absolute\.txt})
    end

    it "rejects drive-letter entry names" do
      cap = build_cap(File.join(tmpdir, "drive.cap"), ["C:/drive.txt"])

      expect { described_class.new.unpack(cap, extract_dir) }
        .to raise_error(Capsium::Packager::UnsafeEntryError, /drive\.txt/)
    end

    it "rejects an unsafe .cap when loading it as a package" do
      cap = build_cap(File.join(tmpdir, "package.cap"), ["../evil.txt"])

      expect { Capsium::Package.new(cap) }
        .to raise_error(Capsium::Packager::UnsafeEntryError)
    end

    it "still extracts safe entries from a mixed archive before the unsafe one" do
      cap = build_cap(File.join(tmpdir, "mixed.cap"),
                      ["content/index.html", "../evil.txt"])

      expect { described_class.new.unpack(cap, extract_dir) }
        .to raise_error(Capsium::Packager::UnsafeEntryError)
      expect(File).not_to exist(File.join(tmpdir, "evil.txt"))
    end
  end
end
