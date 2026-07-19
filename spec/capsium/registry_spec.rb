# frozen_string_literal: true

require "spec_helper"
require "digest"
require "json"
require "net/http"
require "socket"
require "webrick"
require_relative "package/composite_spec_helper"

RSpec.describe Capsium::Registry do
  let(:workdir) { Dir.mktmpdir }
  let(:guid) { "https://example.com/capsiums/story-of-claire" }

  after { FileUtils.rm_rf(workdir) }

  # Packs a valid package and returns its .cap path.
  def build_cap(version, name: "story-of-claire", guid: nil, files: nil)
    package_dir = CompositeSpecHelper.write_package(
      workdir, name: name, version: version, guid: guid || self.guid,
               files: files || { "index.html" => "<html>#{name} #{version}</html>" }
    )
    CompositeSpecHelper.pack(workdir, package_dir)
  end

  # Packs a package that fails validation (external http reference in
  # content) and returns its .cap path.
  def build_invalid_cap
    package_dir = File.join(workdir, "bad-package-1.0.0")
    FileUtils.mkdir_p(File.join(package_dir, "content"))
    CompositeSpecHelper.write_metadata(package_dir, name: "bad-package",
                                                    version: "1.0.0", guid: "https://example.com/bad")
    File.write(File.join(package_dir, "content", "index.html"),
               '<html><script src="https://cdn.example.com/x.js"></script></html>')
    CompositeSpecHelper.write_manifest(package_dir, ["index.html"], [])
    CompositeSpecHelper.zip_package(package_dir, "#{package_dir}.cap")
  end

  # Serves the given directory over http on an ephemeral port.
  def with_static_server(root)
    server = WEBrick::HTTPServer.new(Port: 0, DocumentRoot: root,
                                     Logger: WEBrick::Log.new(File::NULL),
                                     AccessLog: [])
    thread = Thread.new { server.start }
    yield server, "http://127.0.0.1:#{server.listeners.first.addr[1]}"
  ensure
    server.shutdown
    thread.join(5) || thread.kill
  end

  describe ".fetch" do
    it "returns a Local registry for a directory path" do
      expect(described_class.fetch(workdir)).to be_a(Capsium::Registry::Local)
    end

    it "returns a Remote registry for an http(s) base URL" do
      expect(described_class.fetch("https://example.com/registry"))
        .to be_a(Capsium::Registry::Remote)
    end

    it "raises RegistryNotConfiguredError when no reference is given" do
      expect { described_class.fetch(nil) }
        .to raise_error(Capsium::Registry::RegistryNotConfiguredError,
                        /CAPSIUM_REGISTRY/)
      expect { described_class.fetch("") }
        .to raise_error(Capsium::Registry::RegistryNotConfiguredError)
    end

    it "rejects plain http for non-loopback hosts" do
      expect { described_class.fetch("http://example.com/registry") }
        .to raise_error(Capsium::Registry::InvalidRegistryError, /https/)
    end

    it "accepts plain http for loopback hosts" do
      expect(described_class.fetch("http://127.0.0.1:8864/registry"))
        .to be_a(Capsium::Registry::Remote)
    end

    it "rejects a registry path that is not a directory" do
      file = File.join(workdir, "not-a-dir")
      File.write(file, "x")
      expect { described_class.fetch(file) }
        .to raise_error(Capsium::Registry::InvalidRegistryError, /not a directory/)
    end
  end

  describe ".default" do
    it "reads CAPSIUM_REGISTRY and stays nil when unset" do
      expect(described_class.default).to be_nil
      ENV["CAPSIUM_REGISTRY"] = workdir
      expect(described_class.default).to be_a(Capsium::Registry::Local)
    ensure
      ENV.delete("CAPSIUM_REGISTRY")
    end
  end

  describe Capsium::Registry::Local do
    let(:registry_dir) { File.join(workdir, "registry") }
    let(:registry) { described_class.fetch(registry_dir) }

    describe "#push" do
      it "copies the .cap in and records sha256/size/file in index.json" do
        cap = build_cap("1.0.0")
        entry = registry.push(cap)

        expect(entry.name).to eq("story-of-claire")
        expect(entry.version.to_s).to eq("1.0.0")
        expect(entry.guid).to eq(guid)
        copied = File.join(registry_dir, "story-of-claire-1.0.0.cap")
        expect(File).to exist(copied)

        index = JSON.parse(File.read(File.join(registry_dir, "index.json")))
        recorded = index.dig("packages", guid, "versions", "1.0.0")
        expect(recorded["file"]).to eq("story-of-claire-1.0.0.cap")
        expect(recorded["sha256"]).to eq(Digest::SHA256.file(cap).hexdigest)
        expect(recorded["size"]).to eq(File.size(cap))
        expect(index.dig("packages", guid, "name")).to eq("story-of-claire")
      end

      it "accumulates multiple versions under one GUID" do
        registry.push(build_cap("1.0.0"))
        registry.push(build_cap("1.1.0"))

        versions = JSON
                   .parse(File.read(File.join(registry_dir, "index.json")))
                   .dig("packages", guid, "versions")
        expect(versions.keys).to contain_exactly("1.0.0", "1.1.0")
      end

      it "creates the registry directory when missing" do
        registry.push(build_cap("1.0.0"))
        expect(File).to exist(File.join(registry_dir, "index.json"))
      end

      it "rejects a package that fails validation" do
        expect { registry.push(build_invalid_cap) }
          .to raise_error(Capsium::Registry::InvalidPackageError, /external reference/)
        expect(File).not_to exist(File.join(registry_dir, "index.json"))
      end

      it "rejects a missing .cap file" do
        expect { registry.push(File.join(workdir, "nope.cap")) }
          .to raise_error(Capsium::Registry::InvalidPackageError, /not a file/)
      end
    end

    describe "#resolve" do
      before do
        %w[1.0.0 1.2.0 2.0.0].each { |version| registry.push(build_cap(version)) }
      end

      it "returns the newest version satisfying the constraint" do
        expect(registry.resolve(guid, "^1.0.0").version.to_s).to eq("1.2.0")
        expect(registry.resolve(guid, ">=1.0.0, <2.0.0").version.to_s).to eq("1.2.0")
        expect(registry.resolve(guid, "*").version.to_s).to eq("2.0.0")
        expect(registry.resolve(guid).version.to_s).to eq("2.0.0")
      end

      it "resolves exact and tilde constraints" do
        expect(registry.resolve(guid, "1.0.0").version.to_s).to eq("1.0.0")
        expect(registry.resolve(guid, "~1.0.0").version.to_s).to eq("1.0.0")
      end

      it "raises PackageNotFoundError for an unknown GUID" do
        expect { registry.resolve("https://example.com/unknown", "*") }
          .to raise_error(Capsium::Registry::PackageNotFoundError, /unknown/)
      end

      it "raises UnsatisfiableConstraintError when no version matches" do
        expect { registry.resolve(guid, ">=9.0.0") }
          .to raise_error(Capsium::Registry::UnsatisfiableConstraintError,
                          />=9\.0\.0/)
      end
    end

    describe "#install" do
      let(:store_dir) { File.join(workdir, "store") }

      before do
        %w[1.0.0 2.0.0].each { |version| registry.push(build_cap(version)) }
      end

      it "installs the newest satisfying version into the store" do
        path = registry.install(guid, "^1.0.0", store: store_dir)

        expect(path).to eq(File.join(store_dir, "story-of-claire-1.0.0.cap"))
        expect(File).to exist(path)
        index = JSON.parse(File.read(File.join(store_dir, "index.json")))
        expect(index[guid]).to eq("story-of-claire-1.0.0.cap")
      end

      it "makes the package resolvable through the store afterwards" do
        installed = registry.install(guid, "*", store: store_dir)

        store = Capsium::Package::Store.new(store_dir)
        expect(store.find(guid, "*")).to eq(installed)
      end

      it "rejects a tampered registry file with ChecksumMismatchError" do
        cap = File.join(registry_dir, "story-of-claire-2.0.0.cap")
        File.open(cap, "a") { |file| file.write("tampered") }

        expect { registry.install(guid, "*", store: store_dir) }
          .to raise_error(Capsium::Registry::ChecksumMismatchError, /sha256/)
        expect(File).not_to exist(File.join(store_dir, "story-of-claire-2.0.0.cap"))
      end
    end
  end

  describe Capsium::Registry::Remote do
    let(:registry_dir) { File.join(workdir, "registry") }

    before do
      local = described_class.fetch(registry_dir)
      %w[1.0.0 2.0.0].each { |version| local.push(build_cap(version)) }
    end

    it "is read-only for push" do
      remote = described_class.fetch("https://example.com/registry")
      expect { remote.push("x.cap") }
        .to raise_error(Capsium::Registry::RegistryError, /read-only/)
    end

    it "resolves and installs over http" do
      with_static_server(registry_dir) do |_server, base_url|
        remote = described_class.fetch(base_url)
        entry = remote.resolve(guid, "^1.0.0")
        expect(entry.version.to_s).to eq("1.0.0")

        store_dir = File.join(workdir, "store")
        path = remote.install(guid, "^1.0.0", store: store_dir)
        expect(File).to exist(path)
        original = File.join(registry_dir, "story-of-claire-1.0.0.cap")
        expect(Digest::SHA256.file(path).hexdigest)
          .to eq(Digest::SHA256.file(original).hexdigest)
      end
    end

    it "follows redirects to the index" do
      with_static_server(registry_dir) do |server, base_url|
        server.mount_proc("/r") do |_request, response|
          response.set_redirect(WEBrick::HTTPStatus::Found, "/index.json")
        end

        remote = described_class.fetch("#{base_url}/r")
        expect(remote.resolve(guid, "*").version.to_s).to eq("2.0.0")
      end
    end

    it "rejects a tampered download with ChecksumMismatchError" do
      cap = File.join(registry_dir, "story-of-claire-2.0.0.cap")
      File.open(cap, "a") { |file| file.write("tampered") }

      with_static_server(registry_dir) do |_server, base_url|
        remote = described_class.fetch(base_url)
        expect { remote.install(guid, "*", store: File.join(workdir, "store")) }
          .to raise_error(Capsium::Registry::ChecksumMismatchError)
      end
    end

    it "raises InvalidRegistryError when the index is missing" do
      empty = File.join(workdir, "empty")
      FileUtils.mkdir_p(empty)
      with_static_server(empty) do |_server, base_url|
        remote = described_class.fetch(base_url)
        expect { remote.resolve(guid, "*") }
          .to raise_error(Capsium::Registry::InvalidRegistryError, /index\.json/)
      end
    end
  end

  describe "end-to-end: install and serve a capsium:// GUID" do
    it "installs from a registry and serves the package on an ephemeral port" do
      cap = build_cap("1.0.0", guid: "capsium://example.com/story",
                               files: { "index.html" => "<html>served from registry</html>" })
      registry = described_class.fetch(File.join(workdir, "registry"))
      registry.push(cap)

      installed = registry.install("capsium://example.com/story", "*",
                                   store: File.join(workdir, "store"))
      probe = TCPServer.new("127.0.0.1", 0)
      port = probe.addr[1]
      probe.close
      reactor = Capsium::Reactor.new(package: installed, port: port)
      thread = Thread.new { reactor.server.start }

      response = wait_for_response(port, "/")
      expect(response.code).to eq("200")
      expect(response.body).to include("served from registry")
    ensure
      reactor&.server&.shutdown
      thread&.join(5)
      reactor&.package&.cleanup
    end
  end

  def wait_for_response(port, path)
    uri = URI("http://127.0.0.1:#{port}#{path}")
    20.times do
      return Net::HTTP.get_response(uri)
    rescue SystemCallError
      sleep(0.1)
    end
    Net::HTTP.get_response(uri)
  end
end
