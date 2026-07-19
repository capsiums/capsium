# frozen_string_literal: true

require "spec_helper"
require "stringio"
require_relative "../package/open_pgp_spec_helper"

RSpec.describe "capsium package OpenPGP commands" do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }
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
  end

  describe "sign --openpgp and verify-signature" do
    it "signs a package directory and verifies it (explicit and auto-detected)" do
      Dir.mktmpdir do |dir|
        copy = File.join(dir, "bare-package")
        FileUtils.cp_r(File.join(fixtures_path, "bare-package"), copy)

        output = capture_stdout do
          Capsium::Cli::Package.start(["sign", copy, "--openpgp", "--key", secret_key_path])
        end
        expect(output).to include("Package signed:")

        declared = Capsium::Package::Security.new(
          File.join(copy, "security.json")
        ).digital_signatures
        expect(declared.certificate_type).to eq("OpenPGP")

        output = capture_stdout do
          Capsium::Cli::Package.start(["verify-signature", copy, "--openpgp"])
        end
        expect(output).to include("Signature valid:")

        # Without --openpgp the scheme is auto-detected from security.json.
        output = capture_stdout do
          Capsium::Cli::Package.start(["verify-signature", copy])
        end
        expect(output).to include("Signature valid:")
      end
    end

    it "signs and verifies a .cap file" do
      Dir.mktmpdir do |dir|
        cap = File.join(dir, "bare-package-0.1.0.cap")
        FileUtils.cp(File.join(fixtures_path, "bare-package-0.1.0.cap"), cap)

        capture_stdout do
          Capsium::Cli::Package.start(["sign", cap, "--openpgp", "--key", secret_key_path])
        end
        output = capture_stdout do
          Capsium::Cli::Package.start(["verify-signature", cap, "--cert", public_key_path])
        end
        expect(output).to include("Signature valid:")
      end
    end

    it "exits nonzero when the package was tampered with after signing" do
      Dir.mktmpdir do |dir|
        copy = File.join(dir, "bare-package")
        FileUtils.cp_r(File.join(fixtures_path, "bare-package"), copy)
        capture_stdout do
          Capsium::Cli::Package.start(["sign", copy, "--openpgp", "--key", secret_key_path])
        end
        File.write(File.join(copy, "content", "index.html"), "tampered")

        status = capture_exit_status do
          Capsium::Cli::Package.start(["verify-signature", copy, "--openpgp"])
        end
        expect(status).to eq(1)
      end
    end

    it "exits nonzero when --cert is combined with --openpgp" do
      Dir.mktmpdir do |dir|
        copy = File.join(dir, "bare-package")
        FileUtils.cp_r(File.join(fixtures_path, "bare-package"), copy)

        status = capture_exit_status do
          Capsium::Cli::Package.start(
            ["sign", copy, "--openpgp", "--key", secret_key_path, "--cert", public_key_path]
          )
        end
        expect(status).to eq(1)
      end
    end
  end

  describe "encrypt --openpgp and decrypt" do
    it "encrypts and decrypts a .cap round-trip (explicit and auto-detected)" do
      Dir.mktmpdir do |dir|
        cap = File.join(dir, "bare-package-0.1.0.cap")
        FileUtils.cp(File.join(fixtures_path, "bare-package-0.1.0.cap"), cap)
        encrypted = File.join(dir, "encrypted.cap")
        decrypted = File.join(dir, "decrypted.cap")
        auto_decrypted = File.join(dir, "auto-decrypted.cap")

        output = capture_stdout do
          Capsium::Cli::Package.start(
            ["encrypt", cap, "--openpgp", "--recipient", public_key_path, "-o", encrypted]
          )
        end
        expect(output).to include("Package encrypted:")

        output = capture_stdout do
          Capsium::Cli::Package.start(
            ["decrypt", encrypted, "--openpgp", "--key", secret_key_path, "-o", decrypted]
          )
        end
        expect(output).to include("Package decrypted:")
        expect(Capsium::Package.new(decrypted).name).to eq("bare-package")

        # Without --openpgp the envelope's keyManagement selects the cipher.
        capture_stdout do
          Capsium::Cli::Package.start(
            ["decrypt", encrypted, "--key", secret_key_path, "-o", auto_decrypted]
          )
        end
        expect(Capsium::Package.new(auto_decrypted).name).to eq("bare-package")
      end
    end

    it "exits nonzero when decrypting with the wrong key" do
      Dir.mktmpdir do |dir|
        cap = File.join(dir, "bare-package-0.1.0.cap")
        FileUtils.cp(File.join(fixtures_path, "bare-package-0.1.0.cap"), cap)
        encrypted = File.join(dir, "encrypted.cap")
        capture_stdout do
          Capsium::Cli::Package.start(
            ["encrypt", cap, "--openpgp", "--recipient", public_key_path, "-o", encrypted]
          )
        end

        status = capture_exit_status do
          Capsium::Cli::Package.start(
            ["decrypt", encrypted, "--openpgp", "--key", wrong_secret_key_path]
          )
        end
        expect(status).to eq(1)
      end
    end

    it "exits nonzero when no recipient key is given" do
      status = capture_exit_status do
        Capsium::Cli::Package.start(["encrypt", "x.cap", "--openpgp", "-o", "y.cap"])
      end
      expect(status).to eq(1)
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def capture_exit_status
    original_err = $stderr
    $stderr = StringIO.new
    yield
    0
  rescue SystemExit => e
    e.status
  ensure
    $stderr = original_err
  end
end
