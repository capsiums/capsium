# frozen_string_literal: true

require "spec_helper"
require "base64"
require "json"
require "openssl"
require "zip"

RSpec.describe Capsium::Package::Cipher do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }
  let(:work_dir) { Dir.mktmpdir }
  let(:key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:public_key_path) { File.join(work_dir, "public.pem") }
  let(:private_key_path) { File.join(work_dir, "private.pem") }
  let(:cap_path) { File.join(work_dir, "bare-package-0.1.0.cap") }
  let(:encrypted_path) { File.join(work_dir, "bare-package-0.1.0-encrypted.cap") }
  let(:cipher) { described_class.new }

  before do
    File.write(public_key_path, key.public_key.to_pem)
    File.write(private_key_path, key.to_pem)
    FileUtils.cp(File.join(fixtures_path, "bare-package-0.1.0.cap"), cap_path)
  end

  after do
    FileUtils.rm_rf(work_dir)
  end

  describe "#encrypt" do
    it "writes the standard encrypted layout with cleartext metadata.json" do
      cipher.encrypt(cap_path, public_key_path, encrypted_path)

      entries = Zip::File.open(encrypted_path) { |zip| zip.map(&:name) }
      expect(entries).to contain_exactly("metadata.json", "signature.json", "package.enc")

      metadata = Zip::File.open(encrypted_path) do |zip|
        JSON.parse(zip.find_entry("metadata.json").get_input_stream.read)
      end
      expect(metadata["name"]).to eq("bare-package")
      expect(metadata["version"]).to eq("0.1.0")
    end

    it "writes the encryption envelope into signature.json" do
      cipher.encrypt(cap_path, public_key_path, encrypted_path)

      envelope = Zip::File.open(encrypted_path) do |zip|
        JSON.parse(zip.find_entry("signature.json").get_input_stream.read)
      end
      encryption = envelope["encryption"]
      expect(encryption["algorithm"]).to eq("AES-256-GCM")
      expect(encryption["keyManagement"]).to eq("RSA-OAEP-SHA256")
      expect(Base64.strict_decode64(encryption["encryptedDek"]).bytesize).to eq(256)
      expect(Base64.strict_decode64(encryption["iv"]).bytesize).to eq(12)
      expect(Base64.strict_decode64(encryption["authTag"]).bytesize).to eq(16)
    end

    it "encrypts a package directory by packing it first" do
      cipher.encrypt(File.join(fixtures_path, "bare-package"), public_key_path, encrypted_path)

      expect(described_class.encrypted?(encrypted_path)).to be(true)
    end

    it "rejects an unloadable public key" do
      missing_key = File.join(work_dir, "missing.pem")
      expect { cipher.encrypt(cap_path, missing_key, encrypted_path) }
        .to raise_error(described_class::CipherError, /cannot load public key/)
    end
  end

  describe "#decrypt" do
    before { cipher.encrypt(cap_path, public_key_path, encrypted_path) }

    it "round-trips the package" do
      decrypted_path = File.join(work_dir, "decrypted.cap")
      cipher.decrypt(encrypted_path, private_key_path, decrypted_path)

      package = Capsium::Package.new(decrypted_path)
      expect(package.name).to eq("bare-package")
      expect(package.verify_integrity).to be_empty
      expect(package.content_files.map { |f| File.basename(f) })
        .to include("index.html", "example.css", "example.js")
    end

    it "fails with a typed error for the wrong private key" do
      wrong_key_path = File.join(work_dir, "wrong.pem")
      File.write(wrong_key_path, OpenSSL::PKey::RSA.generate(2048).to_pem)

      expect { cipher.decrypt(encrypted_path, wrong_key_path, File.join(work_dir, "x.cap")) }
        .to raise_error(described_class::DecryptionError)
    end

    it "fails with a typed error for a tampered package.enc" do
      tampered_path = File.join(work_dir, "tampered.cap")
      FileUtils.cp(encrypted_path, tampered_path)
      Zip::File.open(tampered_path) do |zip|
        zip.remove("package.enc")
        zip.get_output_stream("package.enc") { |stream| stream.write("tampered") }
      end

      expect { cipher.decrypt(tampered_path, private_key_path, File.join(work_dir, "x.cap")) }
        .to raise_error(described_class::DecryptionError)
    end

    it "decrypts the uncompressed directory form" do
      directory_form = File.join(work_dir, "encrypted-dir")
      Capsium::Packager.new.unpack(encrypted_path, directory_form)

      decrypted_path = File.join(work_dir, "decrypted.cap")
      cipher.decrypt(directory_form, private_key_path, decrypted_path)
      expect(Capsium::Package.new(decrypted_path).name).to eq("bare-package")
    end
  end

  describe ".encrypted?" do
    it "detects encrypted and plaintext packages" do
      expect(described_class.encrypted?(cap_path)).to be(false)
      cipher.encrypt(cap_path, public_key_path, encrypted_path)
      expect(described_class.encrypted?(encrypted_path)).to be(true)
      expect(described_class.encrypted?(File.join(fixtures_path, "bare-package"))).to be(false)
    end
  end

  describe "Capsium::Package integration" do
    before { cipher.encrypt(cap_path, public_key_path, encrypted_path) }

    it "loads an encrypted .cap transparently with decryption_key:" do
      package = Capsium::Package.new(encrypted_path, decryption_key: private_key_path)
      expect(package.name).to eq("bare-package")
      expect(package.metadata.version).to eq("0.1.0")
      expect(package.verify_integrity).to be_empty
    end

    it "raises KeyRequiredError without a decryption key" do
      expect { Capsium::Package.new(encrypted_path) }
        .to raise_error(described_class::KeyRequiredError, /decryption_key/)
    end

    it "prevents the reactor from serving an encrypted package without a key" do
      expect { Capsium::Reactor.new(package: encrypted_path, do_not_listen: true) }
        .to raise_error(described_class::KeyRequiredError)
    end

    it "lets the reactor serve a decrypted package" do
      package = Capsium::Package.new(encrypted_path, decryption_key: private_key_path)
      reactor = Capsium::Reactor.new(package: package, do_not_listen: true)
      expect(reactor.routes.resolve("/").resource).to eq("content/index.html")
    end
  end
end
