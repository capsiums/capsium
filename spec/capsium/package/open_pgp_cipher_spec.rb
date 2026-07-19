# frozen_string_literal: true

require "spec_helper"
require "base64"
require "json"
require "openssl"
require "zip"
require_relative "open_pgp_spec_helper"

RSpec.describe Capsium::Package::OpenPgpCipher do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }
  let(:work_dir) { Dir.mktmpdir }
  let(:cap_path) { File.join(work_dir, "bare-package-0.1.0.cap") }
  let(:encrypted_path) { File.join(work_dir, "bare-package-0.1.0-encrypted.cap") }
  let(:cipher) { described_class.new }
  let(:public_key_path) { File.join(@key_dir, "test-public.asc") }
  let(:secret_key_path) { File.join(@key_dir, "test-secret.asc") }
  let(:wrong_secret_key_path) { File.join(@key_dir, "wrong-secret.asc") }

  before(:all) do
    @key_dir = Dir.mktmpdir
    OpenPgpSpecHelper.generate_keypairs(@key_dir) if OpenPgpSpecHelper.available?
  end

  after(:all) { FileUtils.rm_rf(@key_dir) }

  before do
    skip "OpenPGP support requires librnp and the rnp gem" unless OpenPgpSpecHelper.available?
    FileUtils.cp(File.join(fixtures_path, "bare-package-0.1.0.cap"), cap_path)
  end

  after { FileUtils.rm_rf(work_dir) }

  describe "#encrypt" do
    it "writes the standard encrypted layout with cleartext metadata.json" do
      cipher.encrypt(cap_path, public_key_path, encrypted_path)

      entries = Zip::File.open(encrypted_path) { |zip| zip.map(&:name) }
      expect(entries).to contain_exactly("metadata.json", "signature.json", "package.enc")

      metadata = Zip::File.open(encrypted_path) do |zip|
        JSON.parse(zip.find_entry("metadata.json").get_input_stream.read)
      end
      expect(metadata["name"]).to eq("bare-package")
    end

    it "writes the OpenPGP envelope into signature.json" do
      cipher.encrypt(cap_path, public_key_path, encrypted_path)

      envelope = Zip::File.open(encrypted_path) do |zip|
        JSON.parse(zip.find_entry("signature.json").get_input_stream.read)
      end
      encryption = envelope["encryption"]
      expect(encryption["algorithm"]).to eq("AES-256-GCM")
      expect(encryption["keyManagement"]).to eq("OpenPGP")
      expect(encryption["message"]).to start_with("-----BEGIN PGP MESSAGE-----")
      expect(encryption).not_to have_key("encryptedDek")
      expect(Base64.strict_decode64(encryption["iv"]).bytesize).to eq(12)
      expect(Base64.strict_decode64(encryption["authTag"]).bytesize).to eq(16)
    end

    it "is detected as OpenPGP key management by the Cipher dispatch" do
      cipher.encrypt(cap_path, public_key_path, encrypted_path)

      expect(Capsium::Package::Cipher.key_management(encrypted_path)).to eq("OpenPGP")
      expect(Capsium::Package::Cipher.for_encrypted(encrypted_path))
        .to be_a(described_class)
    end

    it "rejects an unloadable recipient key" do
      expect { cipher.encrypt(cap_path, File.join(work_dir, "missing.asc"), encrypted_path) }
        .to raise_error(Capsium::Package::OpenPgp::KeyError, /cannot load OpenPGP key/)
    end
  end

  describe "#decrypt" do
    before { cipher.encrypt(cap_path, public_key_path, encrypted_path) }

    it "round-trips the package" do
      decrypted_path = File.join(work_dir, "decrypted.cap")
      cipher.decrypt(encrypted_path, secret_key_path, decrypted_path)

      package = Capsium::Package.new(decrypted_path)
      expect(package.name).to eq("bare-package")
      expect(package.verify_integrity).to be_empty
      expect(package.content_files.map { |f| File.basename(f) })
        .to include("index.html", "example.css", "example.js")
    end

    it "fails with a typed error for the wrong secret key" do
      expect do
        cipher.decrypt(encrypted_path, wrong_secret_key_path, File.join(work_dir, "x.cap"))
      end.to raise_error(Capsium::Package::Cipher::DecryptionError)
    end

    it "fails with a typed error for a tampered package.enc" do
      tampered_path = File.join(work_dir, "tampered.cap")
      FileUtils.cp(encrypted_path, tampered_path)
      Zip::File.open(tampered_path) do |zip|
        zip.remove("package.enc")
        zip.get_output_stream("package.enc") { |stream| stream.write("tampered") }
      end

      expect do
        cipher.decrypt(tampered_path, secret_key_path, File.join(work_dir, "x.cap"))
      end.to raise_error(Capsium::Package::Cipher::DecryptionError)
    end

    it "decrypts the uncompressed directory form" do
      directory_form = File.join(work_dir, "encrypted-dir")
      Capsium::Packager.new.unpack(encrypted_path, directory_form)

      decrypted_path = File.join(work_dir, "decrypted.cap")
      cipher.decrypt(directory_form, secret_key_path, decrypted_path)
      expect(Capsium::Package.new(decrypted_path).name).to eq("bare-package")
    end
  end

  describe "Capsium::Package integration" do
    before { cipher.encrypt(cap_path, public_key_path, encrypted_path) }

    it "loads an OpenPGP-encrypted .cap transparently with decryption_key:" do
      package = Capsium::Package.new(encrypted_path, decryption_key: secret_key_path)
      expect(package.name).to eq("bare-package")
      expect(package.metadata.version).to eq("0.1.0")
      expect(package.verify_integrity).to be_empty
    end

    it "raises KeyRequiredError without a decryption key" do
      expect { Capsium::Package.new(encrypted_path) }
        .to raise_error(Capsium::Package::Cipher::KeyRequiredError, /decryption_key/)
    end

    it "fails with a typed error when the decryption key has the wrong format" do
      rsa_key_path = File.join(work_dir, "rsa.pem")
      File.write(rsa_key_path, OpenSSL::PKey::RSA.generate(2048).to_pem)

      expect { Capsium::Package.new(encrypted_path, decryption_key: rsa_key_path) }
        .to raise_error(Capsium::Package::OpenPgp::KeyError)
    end
  end
end
