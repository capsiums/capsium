# frozen_string_literal: true

require "spec_helper"
require "openssl"

RSpec.describe Capsium::Package::Signer do
  let(:package_dir) { Dir.mktmpdir }
  let(:key_dir) { Dir.mktmpdir }
  let(:key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:key_path) { File.join(key_dir, "private.pem") }
  let(:signer) { described_class.new(package_dir) }

  before do
    FileUtils.mkdir_p(File.join(package_dir, "content"))
    File.write(File.join(package_dir, "metadata.json"), "{}")
    File.write(File.join(package_dir, "content", "index.html"), "<html></html>")
    File.write(key_path, key.to_pem)
    Capsium::Package::Security.generate(package_dir).save_to_file
  end

  after do
    FileUtils.rm_rf(package_dir)
    FileUtils.rm_rf(key_dir)
  end

  def self_signed_cert(cert_key)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse("/CN=capsium-test")
    cert.issuer = cert.subject
    cert.public_key = cert_key.public_key
    cert.not_before = Time.now
    cert.not_after = Time.now + 3600
    cert.sign(cert_key, OpenSSL::Digest.new("SHA256"))
    cert
  end

  def tamper_and_rechecksum(dir)
    File.write(File.join(dir, "content", "index.html"), "tampered")
    security = Capsium::Package::Security.generate(
      dir, digital_signatures: Capsium::Package::DigitalSignatures.new(
        public_key: described_class::PUBLIC_KEY_FILE,
        signature_file: Capsium::Package::SIGNATURE_FILE
      )
    )
    security.save_to_file
  end

  describe "#sign" do
    it "writes signature.sig, embeds the public key and records digitalSignatures" do
      signer.sign(key_path)

      expect(File).to exist(File.join(package_dir, "signature.sig"))
      expect(File).to exist(File.join(package_dir, "signature.pub.pem"))
      declared = Capsium::Package::Security.new(
        File.join(package_dir, "security.json")
      ).digital_signatures
      expect(declared.public_key).to eq("signature.pub.pem")
      expect(declared.signature_file).to eq("signature.sig")
    end

    it "does not cover signature.sig with the integrity checksums" do
      signer.sign(key_path)
      checksums = Capsium::Package::Security.new(
        File.join(package_dir, "security.json")
      ).checksums
      expect(checksums.keys).to contain_exactly(
        "content/index.html", "metadata.json", "signature.pub.pem"
      )
    end

    it "rejects a private key shorter than 2048 bits" do
      short_key_path = File.join(key_dir, "short.pem")
      File.write(short_key_path, OpenSSL::PKey::RSA.generate(1024).to_pem)
      expect { signer.sign(short_key_path) }
        .to raise_error(described_class::SignatureError, /too short/)
    end

    it "rejects an unloadable private key" do
      expect { signer.sign(File.join(key_dir, "nonexistent.pem")) }
        .to raise_error(described_class::SignatureError, /cannot load private key/)
    end

    it "rejects a certificate that does not match the private key" do
      other_cert_path = File.join(key_dir, "other.pem")
      File.write(other_cert_path, self_signed_cert(OpenSSL::PKey::RSA.generate(2048)).to_pem)
      expect { signer.sign(key_path, other_cert_path) }
        .to raise_error(described_class::SignatureError, /does not match/)
    end

    it "embeds the certificate public key when a matching certificate is given" do
      cert_path = File.join(key_dir, "cert.pem")
      File.write(cert_path, self_signed_cert(key).to_pem)
      signer.sign(key_path, cert_path)

      embedded = File.read(File.join(package_dir, "signature.pub.pem"))
      expect(OpenSSL::PKey::RSA.new(embedded).to_pem).to eq(key.public_key.to_pem)
    end
  end

  describe "#verify" do
    before { signer.sign(key_path) }

    it "verifies a freshly signed package (round-trip)" do
      expect(signer.verify).to be(true)
      expect(signer.verify!).to be(true)
    end

    it "verifies against an explicit public key or certificate" do
      public_key_path = File.join(key_dir, "public.pem")
      File.write(public_key_path, key.public_key.to_pem)
      expect(signer.verify(public_key_path)).to be(true)

      cert_path = File.join(key_dir, "cert.pem")
      File.write(cert_path, self_signed_cert(key).to_pem)
      expect(signer.verify(cert_path)).to be(true)
    end

    it "rejects a tampered package even when checksums were recomputed" do
      tamper_and_rechecksum(package_dir)
      expect(signer.verify).to be(false)
      expect { signer.verify! }.to raise_error(described_class::SignatureMismatchError)
    end

    it "rejects verification with the wrong public key" do
      wrong_key_path = File.join(key_dir, "wrong.pem")
      File.write(wrong_key_path, OpenSSL::PKey::RSA.generate(2048).public_key.to_pem)
      expect(signer.verify(wrong_key_path)).to be(false)
    end

    it "verifies with openssl dgst (interop)" do
      skip "openssl CLI not available" unless system("which openssl > /dev/null 2>&1")

      payload = Capsium::Package::Security.new(
        File.join(package_dir, "security.json")
      ).checksums.keys.sort.map do |relative_path|
        File.binread(File.join(package_dir, relative_path))
      end.join
      payload_path = File.join(package_dir, "payload.bin")
      File.binwrite(payload_path, payload)

      verified = system(
        "openssl", "dgst", "-sha256",
        "-verify", File.join(package_dir, "signature.pub.pem"),
        "-signature", File.join(package_dir, "signature.sig"),
        payload_path,
        out: File::NULL, err: File::NULL
      )
      expect(verified).to be(true)
    end
  end

  describe "unsigned packages" do
    it "raises UnsignedPackageError on verify" do
      expect(signer.signed?).to be(false)
      expect { signer.verify }.to raise_error(described_class::UnsignedPackageError)
    end
  end

  describe "Capsium::Package integration" do
    let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }
    let(:package_copy) { File.join(Dir.mktmpdir, "bare-package") }

    before do
      FileUtils.cp_r(File.join(fixtures_path, "bare-package"), package_copy)
      described_class.new(package_copy).sign(key_path)
    end

    after do
      FileUtils.rm_rf(File.dirname(package_copy))
    end

    it "loads a signed package and reports it as signed" do
      package = Capsium::Package.new(package_copy)
      expect(package.signed?).to be(true)
      expect(package.verify_signature).to be(true)
      expect(package.verify_integrity).to be_empty
    end

    it "fails to load when the signature no longer matches" do
      tamper_and_rechecksum(package_copy)
      expect { Capsium::Package.new(package_copy) }
        .to raise_error(described_class::SignatureMismatchError)
    end

    it "fails to load a tampered package on checksums first" do
      File.write(File.join(package_copy, "content", "index.html"), "tampered")
      expect { Capsium::Package.new(package_copy) }
        .to raise_error(Capsium::Package::Security::IntegrityError)
    end
  end
end
