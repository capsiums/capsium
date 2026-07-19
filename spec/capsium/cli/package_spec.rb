# frozen_string_literal: true

require "spec_helper"
require "openssl"
require "stringio"
require_relative "../package/composite_spec_helper"

RSpec.describe Capsium::Cli::Package do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }

  describe "info" do
    it "shows the resolved dependency tree for a composite package" do
      Dir.mktmpdir do |dir|
        store = CompositeSpecHelper.build_store(dir)
        output = capture_stdout do
          described_class.start(
            ["info", File.join(fixtures_path, "composite-package"),
             "--store", store]
          )
        end
        expect(output).to include(
          "- https://example.com/capsiums/base-package (^1.0.0) => 1.2.0"
        )
        expect(output).to include("base-package-1.2.0.cap")
      end
    end
  end

  describe "validate" do
    it "reports success for a valid package directory" do
      output = capture_stdout do
        described_class.start(["validate", File.join(fixtures_path, "data-package")])
      end
      expect(output).to include("PASS metadata", "PASS manifest", "PASS routes",
                                "PASS storage", "PASS security", "PASS content")
    end

    it "exits nonzero for an invalid package" do
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(File.join(fixtures_path, "data-package"), dir)
        copy = File.join(dir, "data-package")
        File.write(File.join(copy, "content", "index.html"), "tampered")

        status = capture_exit_status do
          described_class.start(["validate", copy])
        end
        expect(status).to eq(1)
      end
    end

    it "exits nonzero for a nonexistent path" do
      status = capture_exit_status do
        described_class.start(["validate", "/nonexistent/package"])
      end
      expect(status).to eq(1)
    end
  end

  describe "unpack" do
    it "unpacks a .cap file into the given directory" do
      Dir.mktmpdir do |dir|
        destination = File.join(dir, "unpacked")
        capture_stdout do
          described_class.start(
            ["unpack", File.join(fixtures_path, "bare-package-0.1.0.cap"),
             "-o", destination]
          )
        end
        expect(File).to exist(File.join(destination, "metadata.json"))
        expect(File).to exist(File.join(destination, "content", "index.html"))
        expect(File).to exist(File.join(destination, "security.json"))
      end
    end

    it "exits nonzero for a missing .cap file" do
      status = capture_exit_status do
        described_class.start(["unpack", "/nonexistent.cap", "-o", Dir.mktmpdir])
      end
      expect(status).to eq(1)
    end
  end

  describe "sign and verify-signature" do
    let(:key_dir) { Dir.mktmpdir }
    let(:key_path) { File.join(key_dir, "private.pem") }

    before do
      File.write(key_path, OpenSSL::PKey::RSA.generate(2048).to_pem)
    end

    after do
      FileUtils.rm_rf(key_dir)
    end

    it "signs a package directory and verifies the signature" do
      Dir.mktmpdir do |dir|
        copy = File.join(dir, "bare-package")
        FileUtils.cp_r(File.join(fixtures_path, "bare-package"), copy)

        output = capture_stdout { described_class.start(["sign", copy, "--key", key_path]) }
        expect(output).to include("Package signed:")
        expect(File).to exist(File.join(copy, "signature.sig"))

        output = capture_stdout { described_class.start(["verify-signature", copy]) }
        expect(output).to include("Signature valid:")
      end
    end

    it "signs and verifies a .cap file" do
      Dir.mktmpdir do |dir|
        cap = File.join(dir, "bare-package-0.1.0.cap")
        FileUtils.cp(File.join(fixtures_path, "bare-package-0.1.0.cap"), cap)

        capture_stdout { described_class.start(["sign", cap, "--key", key_path]) }
        output = capture_stdout { described_class.start(["verify-signature", cap]) }
        expect(output).to include("Signature valid:")
      end
    end

    it "exits nonzero when the package was tampered with after signing" do
      Dir.mktmpdir do |dir|
        copy = File.join(dir, "bare-package")
        FileUtils.cp_r(File.join(fixtures_path, "bare-package"), copy)
        capture_stdout { described_class.start(["sign", copy, "--key", key_path]) }
        File.write(File.join(copy, "content", "index.html"), "tampered")

        status = capture_exit_status { described_class.start(["verify-signature", copy]) }
        expect(status).to eq(1)
      end
    end

    it "exits nonzero for an unsigned package" do
      status = capture_exit_status do
        described_class.start(["verify-signature", File.join(fixtures_path, "bare-package")])
      end
      expect(status).to eq(1)
    end

    it "exits nonzero when --key is missing" do
      status = capture_exit_status do
        described_class.start(["sign", File.join(fixtures_path, "bare-package")])
      end
      expect(status).to eq(1)
    end
  end

  describe "encrypt and decrypt" do
    let(:key_dir) { Dir.mktmpdir }
    let(:key) { OpenSSL::PKey::RSA.generate(2048) }
    let(:public_key_path) { File.join(key_dir, "public.pem") }
    let(:private_key_path) { File.join(key_dir, "private.pem") }

    before do
      File.write(public_key_path, key.public_key.to_pem)
      File.write(private_key_path, key.to_pem)
    end

    after do
      FileUtils.rm_rf(key_dir)
    end

    it "encrypts and decrypts a .cap round-trip" do
      Dir.mktmpdir do |dir|
        cap = File.join(dir, "bare-package-0.1.0.cap")
        FileUtils.cp(File.join(fixtures_path, "bare-package-0.1.0.cap"), cap)
        encrypted = File.join(dir, "encrypted.cap")
        decrypted = File.join(dir, "decrypted.cap")

        output = capture_stdout do
          described_class.start(
            ["encrypt", cap, "--public-key", public_key_path, "-o", encrypted]
          )
        end
        expect(output).to include("Package encrypted:")

        output = capture_stdout do
          described_class.start(
            ["decrypt", encrypted, "--private-key", private_key_path, "-o", decrypted]
          )
        end
        expect(output).to include("Package decrypted:")
        expect(Capsium::Package.new(decrypted).name).to eq("bare-package")
      end
    end

    it "uses a default output name for decrypt" do
      Dir.mktmpdir do |dir|
        cap = File.join(dir, "bare-package-0.1.0.cap")
        FileUtils.cp(File.join(fixtures_path, "bare-package-0.1.0.cap"), cap)
        encrypted = File.join(dir, "encrypted.cap")
        capture_stdout do
          described_class.start(
            ["encrypt", cap, "--public-key", public_key_path, "-o", encrypted]
          )
        end

        Dir.chdir(dir) do
          capture_stdout do
            described_class.start(["decrypt", encrypted, "--private-key", private_key_path])
          end
          expect(File).to exist(File.join(dir, "encrypted-decrypted.cap"))
        end
      end
    end

    it "exits nonzero when decrypting with the wrong key" do
      Dir.mktmpdir do |dir|
        cap = File.join(dir, "bare-package-0.1.0.cap")
        FileUtils.cp(File.join(fixtures_path, "bare-package-0.1.0.cap"), cap)
        encrypted = File.join(dir, "encrypted.cap")
        capture_stdout do
          described_class.start(
            ["encrypt", cap, "--public-key", public_key_path, "-o", encrypted]
          )
        end
        wrong_key_path = File.join(dir, "wrong.pem")
        File.write(wrong_key_path, OpenSSL::PKey::RSA.generate(2048).to_pem)

        status = capture_exit_status do
          described_class.start(["decrypt", encrypted, "--private-key", wrong_key_path])
        end
        expect(status).to eq(1)
      end
    end

    it "exits nonzero when --public-key is missing" do
      status = capture_exit_status do
        described_class.start(["encrypt", "x.cap", "-o", "y.cap"])
      end
      expect(status).to eq(1)
    end
  end

  describe "test" do
    it "runs the fixture package suite and exits zero" do
      output = capture_stdout do
        described_class.start(["test", File.join(fixtures_path, "test-package")])
      end
      expect(output).to include("PASS Home route responds")
      expect(output).to include("7 tests, 0 failures")
    end

    it "exits nonzero when tests fail" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "tests"))
        File.write(File.join(dir, "metadata.json"), '{"name": "x", "version": "0.1.0"}')
        File.write(File.join(dir, "tests", "suite.yaml"), <<~YAML)
          tests:
            - name: Missing file
              type: file
              path: "content/missing.txt"
        YAML

        status = capture_exit_status { described_class.start(["test", dir]) }
        expect(status).to eq(1)
      end
    end

    it "exits nonzero for a nonexistent package" do
      status = capture_exit_status do
        described_class.start(["test", "/nonexistent/package"])
      end
      expect(status).to eq(1)
    end
  end

  describe "push" do
    it "pushes a .cap into a registry directory" do
      Dir.mktmpdir do |dir|
        registry_dir = File.join(dir, "registry")
        output = capture_stdout do
          described_class.start(
            ["push", File.join(fixtures_path, "bare-package-0.1.0.cap"),
             "--registry", registry_dir]
          )
        end
        expect(output).to include("Pushed bare-package 0.1.0")
        expect(File).to exist(File.join(registry_dir, "index.json"))
        expect(File).to exist(File.join(registry_dir, "bare-package-0.1.0.cap"))
      end
    end

    it "exits nonzero without a registry" do
      status = capture_exit_status do
        described_class.start(["push", File.join(fixtures_path, "bare-package-0.1.0.cap")])
      end
      expect(status).to eq(1)
    end

    it "exits nonzero for an invalid package" do
      Dir.mktmpdir do |dir|
        status = capture_exit_status do
          described_class.start(
            ["push", File.join(dir, "missing.cap"),
             "--registry", File.join(dir, "registry")]
          )
        end
        expect(status).to eq(1)
      end
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
