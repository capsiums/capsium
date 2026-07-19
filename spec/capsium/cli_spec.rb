# frozen_string_literal: true

require "spec_helper"
require "stringio"
require_relative "package/composite_spec_helper"

RSpec.describe Capsium::Cli do
  describe "install" do
    let(:guid) { "https://example.com/capsiums/story-of-claire" }

    # A Local registry holding one story-of-claire version.
    def build_registry(dir, version)
      registry_dir = File.join(dir, "registry")
      package_dir = CompositeSpecHelper.write_package(
        dir, name: "story-of-claire", version: version, guid: guid,
             files: { "index.html" => "<html>story-of-claire #{version}</html>" }
      )
      registry = Capsium::Registry.fetch(registry_dir)
      registry.push(CompositeSpecHelper.pack(dir, package_dir))
      registry_dir
    end

    it "installs a GUID from a registry into the store" do
      Dir.mktmpdir do |dir|
        registry_dir = build_registry(dir, "1.0.0")
        store_dir = File.join(dir, "store")

        output = capture_stdout do
          described_class.start(
            ["install", guid, "--registry", registry_dir, "--store", store_dir]
          )
        end

        expect(output).to include("Installed #{guid}")
        installed = File.join(store_dir, "story-of-claire-1.0.0.cap")
        expect(File).to exist(installed)
        store = Capsium::Package::Store.new(store_dir)
        expect(store.find(guid, "*")).to eq(installed)
      end
    end

    it "honors --constraint" do
      Dir.mktmpdir do |dir|
        registry_dir = build_registry(dir, "1.0.0")
        store_dir = File.join(dir, "store")

        status = capture_exit_status do
          described_class.start(
            ["install", guid, "--constraint", ">=9.0.0",
             "--registry", registry_dir, "--store", store_dir]
          )
        end
        expect(status).to eq(1)
      end
    end

    it "uses CAPSIUM_REGISTRY and CAPSIUM_STORE as defaults" do
      Dir.mktmpdir do |dir|
        ENV["CAPSIUM_REGISTRY"] = build_registry(dir, "1.0.0")
        ENV["CAPSIUM_STORE"] = File.join(dir, "store")

        output = capture_stdout { described_class.start(["install", guid]) }

        expect(output).to include("Installed #{guid}")
        store_dir = ENV.fetch("CAPSIUM_STORE")
        expect(File).to exist(File.join(store_dir, "story-of-claire-1.0.0.cap"))
      end
    ensure
      ENV.delete("CAPSIUM_REGISTRY")
      ENV.delete("CAPSIUM_STORE")
    end

    it "exits nonzero without a registry" do
      Dir.mktmpdir do |dir|
        status = capture_exit_status do
          described_class.start(["install", guid, "--store", File.join(dir, "store")])
        end
        expect(status).to eq(1)
      end
    end

    it "exits nonzero without a store" do
      Dir.mktmpdir do |dir|
        status = capture_exit_status do
          described_class.start(["install", guid, "--registry", build_registry(dir, "1.0.0")])
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
