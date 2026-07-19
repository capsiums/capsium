# frozen_string_literal: true

require "spec_helper"
require_relative "open_pgp_spec_helper"

RSpec.describe Capsium::Package::OpenPgpSigner do
  let(:package_dir) { Dir.mktmpdir }
  let(:signer) { described_class.new(package_dir) }
  let(:secret_key_path) { File.join(@key_dir, "test-secret.asc") }
  let(:public_key_path) { File.join(@key_dir, "test-public.asc") }
  let(:wrong_public_key_path) { File.join(@key_dir, "wrong-public.asc") }

  before(:all) do
    @key_dir = Dir.mktmpdir
    OpenPgpSpecHelper.generate_keypairs(@key_dir) if OpenPgpSpecHelper.available?
  end

  after(:all) { FileUtils.rm_rf(@key_dir) }

  before do
    skip "OpenPGP support requires librnp and the rnp gem" unless OpenPgpSpecHelper.available?
    FileUtils.mkdir_p(File.join(package_dir, "content"))
    File.write(File.join(package_dir, "metadata.json"), "{}")
    File.write(File.join(package_dir, "content", "index.html"), "<html></html>")
    Capsium::Package::Security.generate(package_dir).save_to_file
  end

  after { FileUtils.rm_rf(package_dir) }

  def tamper_and_rechecksum(dir)
    File.write(File.join(dir, "content", "index.html"), "tampered")
    security = Capsium::Package::Security.generate(
      dir, digital_signatures: Capsium::Package::DigitalSignatures.new(
        certificate_type: "OpenPGP",
        public_key: described_class::PUBLIC_KEY_FILE,
        signature_file: Capsium::Package::SIGNATURE_FILE
      )
    )
    security.save_to_file
  end

  describe "#sign" do
    it "writes an armored detached signature, embeds the public key and records OpenPGP" do
      signer.sign(secret_key_path)

      signature = File.read(File.join(package_dir, "signature.sig"))
      expect(signature).to start_with("-----BEGIN PGP SIGNATURE-----")

      public_key = File.read(File.join(package_dir, "signature.pub.asc"))
      expect(public_key).to start_with("-----BEGIN PGP PUBLIC KEY BLOCK-----")

      declared = Capsium::Package::Security.new(
        File.join(package_dir, "security.json")
      ).digital_signatures
      expect(declared.certificate_type).to eq("OpenPGP")
      expect(declared.public_key).to eq("signature.pub.asc")
      expect(declared.signature_file).to eq("signature.sig")
    end

    it "does not cover signature.sig with the integrity checksums" do
      signer.sign(secret_key_path)
      checksums = Capsium::Package::Security.new(
        File.join(package_dir, "security.json")
      ).checksums
      expect(checksums.keys).to contain_exactly(
        "content/index.html", "metadata.json", "signature.pub.asc"
      )
    end

    it "rejects a public-only key for signing" do
      expect { signer.sign(public_key_path) }
        .to raise_error(Capsium::Package::OpenPgp::KeyError, /no suitable secret/)
    end

    it "rejects an unreadable key file" do
      expect { signer.sign(File.join(package_dir, "nonexistent.asc")) }
        .to raise_error(Capsium::Package::OpenPgp::KeyError, /cannot load OpenPGP key/)
    end
  end

  describe "#verify" do
    before { signer.sign(secret_key_path) }

    it "verifies a freshly signed package (round-trip)" do
      expect(signer.verify).to be(true)
      expect(signer.verify!).to be(true)
    end

    it "verifies against an explicit public key" do
      expect(signer.verify(public_key_path)).to be(true)
    end

    it "rejects a tampered package even when checksums were recomputed" do
      tamper_and_rechecksum(package_dir)
      expect(signer.verify).to be(false)
      expect { signer.verify! }
        .to raise_error(Capsium::Package::Signer::SignatureMismatchError)
    end

    it "rejects verification with the wrong public key" do
      expect(signer.verify(wrong_public_key_path)).to be(false)
    end
  end

  describe "unsigned packages" do
    it "raises UnsignedPackageError on verify" do
      expect(signer.signed?).to be(false)
      expect { signer.verify }
        .to raise_error(Capsium::Package::Signer::UnsignedPackageError)
    end
  end

  describe ".sign_package/.verify_package on .cap files" do
    let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }

    it "signs and verifies a .cap round-trip" do
      Dir.mktmpdir do |dir|
        cap = File.join(dir, "bare-package-0.1.0.cap")
        FileUtils.cp(File.join(fixtures_path, "bare-package-0.1.0.cap"), cap)

        described_class.sign_package(cap, secret_key_path)
        expect(described_class.verify_package(cap)).to be(true)
        expect(described_class.verify_package(cap, public_key_path)).to be(true)
      end
    end
  end

  describe "Capsium::Package integration" do
    let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }
    let(:package_copy) { File.join(Dir.mktmpdir, "bare-package") }

    before do
      FileUtils.cp_r(File.join(fixtures_path, "bare-package"), package_copy)
      described_class.new(package_copy).sign(secret_key_path)
    end

    after { FileUtils.rm_rf(File.dirname(package_copy)) }

    it "loads an OpenPGP-signed package and verifies it through the dispatch" do
      package = Capsium::Package.new(package_copy)
      expect(package.signed?).to be(true)
      expect(package.verify_signature).to be(true)
      expect(package.verify_integrity).to be_empty
    end

    it "auto-detects OpenPGP through Signer.verify_package" do
      expect(Capsium::Package::Signer.verify_package(package_copy)).to be(true)
    end

    it "fails to load when the signature no longer matches" do
      tamper_and_rechecksum(package_copy)
      expect { Capsium::Package.new(package_copy) }
        .to raise_error(Capsium::Package::Signer::SignatureMismatchError)
    end
  end
end
