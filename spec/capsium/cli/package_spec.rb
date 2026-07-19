# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Capsium::Cli::Package do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }

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
