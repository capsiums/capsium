# frozen_string_literal: true

require "spec_helper"
require "webrick"
require_relative "composite_spec_helper"

RSpec.describe "Encapsulated packages (bundled dependencies)" do
  let(:fixtures_path) do
    File.expand_path(File.join(__dir__, "..", "..", "fixtures"))
  end
  let(:composite_source) { File.join(fixtures_path, "composite-package") }
  let(:workdir) { Dir.mktmpdir }
  let(:store_dir) { CompositeSpecHelper.build_store(workdir) }

  after { FileUtils.rm_rf(workdir) }

  # Packs a copy of the composite-package fixture with --bundle-deps
  # into workdir and returns the .cap path.
  def pack_encapsulated(workdir, store, options = { bundle_deps: true })
    source = File.join(workdir, "composite-package")
    FileUtils.cp_r(File.join(fixtures_path, "composite-package"), source)
    package = Capsium::Package.new(source, store: store)
    CompositeSpecHelper.quietly do
      Capsium::Packager.new.pack(package, { force: true, store: store }.merge(options))
    end
  end

  describe "packing with bundle_deps" do
    let(:cap_path) { pack_encapsulated(workdir, store_dir) }

    it "embeds the resolved dependency .cap and the manifest" do
      entries = Zip::File.open(cap_path) { |zip| zip.map(&:name) }
      expect(entries).to include("packages/index.json",
                                 "packages/base-package-1.2.0.cap")
    end

    it "records guid => file, version and sha256 in packages/index.json" do
      index = Zip::File.open(cap_path) do |zip|
        JSON.parse(zip.find_entry("packages/index.json").get_input_stream.read)
      end
      entry = index.fetch(CompositeSpecHelper::BASE_GUID)
      expect(entry["file"]).to eq("packages/base-package-1.2.0.cap")
      expect(entry["version"]).to eq("1.2.0")

      bundled = Zip::File.open(cap_path) do |zip|
        zip.find_entry("packages/base-package-1.2.0.cap").get_input_stream.read
      end
      expect(entry["sha256"]).to eq(Digest::SHA256.hexdigest(bundled))
    end

    it "covers the bundled files with the parent security.json checksums" do
      checksums = Zip::File.open(cap_path) do |zip|
        JSON.parse(zip.find_entry("security.json").get_input_stream.read)
      end.fetch("security").fetch("integrityChecks").fetch("checksums")
      expect(checksums.keys).to include("packages/index.json",
                                        "packages/base-package-1.2.0.cap")
    end

    it "produces a package that passes validation" do
      results = Capsium::Package::Validator.new(cap_path).run
      expect(results).to all(be_ok)
    end

    it "does not embed anything when no dependencies are declared" do
      source = File.join(workdir, "bare-package")
      FileUtils.cp_r(File.join(fixtures_path, "bare-package"), source)
      cap = CompositeSpecHelper.quietly do
        Capsium::Packager.new.pack(Capsium::Package.new(source),
                                   { force: true, bundle_deps: true, store: store_dir })
      end
      entries = Zip::File.open(cap) { |zip| zip.map(&:name) }
      expect(entries.grep(%r{\Apackages/})).to be_empty
    end

    it "fails at pack time when a declared dependency is unresolvable" do
      dependent = CompositeSpecHelper.write_dependent(
        workdir, name: "unresolvable", routes: [],
                 dependencies: { "https://example.com/capsiums/unknown" => "*" }
      )
      status = capture_exit_status do
        Capsium::Cli::Package.start(
          ["pack", dependent, "--bundle-deps", "--store", store_dir]
        )
      end
      expect(status).to eq(1)
    end
  end

  describe "activation without a store or registry" do
    let(:cap_path) { pack_encapsulated(workdir, store_dir) }
    let(:package) { Capsium::Package.new(cap_path) }

    before { ENV.delete("CAPSIUM_STORE") }

    after { package.cleanup }

    it "resolves the bundled dependency first" do
      dependency = package.resolved_dependencies.first
      expect(dependency.guid).to eq(CompositeSpecHelper::BASE_GUID)
      expect(dependency.version).to eq("1.2.0")
      expect(dependency.path).to end_with("packages/base-package-1.2.0.cap")
      expect(dependency.path).to start_with(package.path)
    end

    it "serves dependency content through the merged view" do
      expect(package.merged_view.resolve("content/app.js"))
        .to eq(File.join(package.resolved_dependencies.first.package.path,
                         "content", "app.js"))
    end

    it "serves an inherited route with no store configured" do
      mock_server = instance_double(WEBrick::HTTPServer)
      allow(WEBrick::HTTPServer).to receive(:new).and_return(mock_server)
      allow(mock_server).to receive(:mount_proc)
      allow(mock_server).to receive(:start)
      allow(mock_server).to receive(:shutdown)
      reactor = Capsium::Reactor.new(package: package, do_not_listen: true)

      request = instance_double(WEBrick::HTTPRequest, path: "/vendor/public.txt",
                                                      request_method: "GET")
      response = instance_double(WEBrick::HTTPResponse)
      result = {}
      allow(response).to receive(:status=) { |value| result[:status] = value }
      allow(response).to receive(:status) { result[:status] }
      allow(response).to receive(:[]=)
      allow(response).to receive(:body=) { |value| result[:body] = value }
      reactor.handle_request(request, response)

      expect(result[:status]).to eq(200)
      expect(result[:body]).to eq("public 1.2.0")
    end

    it "loads a directory-form encapsulated package without a store" do
      destination = File.join(workdir, "encapsulated")
      Capsium::Packager.new.unpack(cap_path, destination)
      unpacked = Capsium::Package.new(destination)
      expect(unpacked.resolved_dependencies.first.version).to eq("1.2.0")
    end
  end

  describe "bundle security" do
    it "rejects a bundled .cap whose SHA-256 does not match the manifest" do
      cap_path = pack_encapsulated(workdir, store_dir)
      destination = File.join(workdir, "tampered")
      Capsium::Packager.new.unpack(cap_path, destination)

      bundled = File.join(destination, "packages", "base-package-1.2.0.cap")
      File.binwrite(bundled, "tampered")
      # Recompute the parent checksums so ONLY the manifest SHA-256 fails.
      Capsium::Package::Security.generate(destination).save_to_file

      expect { Capsium::Package.new(destination) }
        .to raise_error(Capsium::Package::Security::IntegrityError, /SHA-256/)
    end

    it "rejects a bundled version that does not satisfy the declared range" do
      cap_path = pack_encapsulated(workdir, store_dir)
      destination = File.join(workdir, "unsatisfiable")
      Capsium::Packager.new.unpack(cap_path, destination)

      metadata_path = File.join(destination, "metadata.json")
      metadata = JSON.parse(File.read(metadata_path))
      metadata["dependencies"] = { CompositeSpecHelper::BASE_GUID => ">=9.0.0" }
      File.write(metadata_path, JSON.pretty_generate(metadata))
      Capsium::Package::Security.generate(destination).save_to_file

      expect { Capsium::Package.new(destination) }
        .to raise_error(Capsium::Package::UnsatisfiableDependencyError, /bundled/)
    end

    it "detects a package bundling itself as circular" do
      cap_path = pack_encapsulated(workdir, store_dir)
      destination = File.join(workdir, "circular")
      Capsium::Packager.new.unpack(cap_path, destination)

      index_path = File.join(destination, "packages", "index.json")
      index = JSON.parse(File.read(index_path))
      guid = JSON.parse(File.read(File.join(destination, "metadata.json"))).fetch("guid")
      index[guid] = index.delete(CompositeSpecHelper::BASE_GUID)
      File.write(index_path, JSON.pretty_generate(index))

      metadata_path = File.join(destination, "metadata.json")
      metadata = JSON.parse(File.read(metadata_path))
      metadata["dependencies"] = { guid => "*" }
      File.write(metadata_path, JSON.pretty_generate(metadata))
      Capsium::Package::Security.generate(destination).save_to_file

      expect { Capsium::Package.new(destination) }
        .to raise_error(Capsium::Package::CircularDependencyError, /circular/)
    end
  end

  describe "transitive bundling (one-level policy)" do
    let(:middle_guid) { "https://example.com/capsiums/middle-package" }

    before { ENV.delete("CAPSIUM_STORE") }

    # middle-package depends on base-package; top-package declares the
    # transitive closure (middle AND base), so its bundle serves
    # middle-package's own dependency too.
    def build_transitive_cap
      middle = CompositeSpecHelper.write_dependent(
        workdir, name: "middle-package", routes: [],
                 dependencies: { CompositeSpecHelper::BASE_GUID => "^1.0.0" }
      )
      middle_cap = CompositeSpecHelper.quietly do
        Capsium::Packager.new.pack(
          Capsium::Package.new(middle, store: store_dir),
          { force: true, store: store_dir }
        )
      end
      FileUtils.mv(middle_cap, File.join(store_dir, "middle-package-0.1.0.cap"))
      FileUtils.rm_rf(middle)

      top = CompositeSpecHelper.write_dependent(
        workdir, name: "top-package", routes: [],
                 dependencies: { middle_guid => "*",
                                 CompositeSpecHelper::BASE_GUID => "^1.0.0" }
      )
      cap = CompositeSpecHelper.quietly do
        Capsium::Packager.new.pack(
          Capsium::Package.new(top, store: store_dir),
          { force: true, bundle_deps: true, store: store_dir }
        )
      end
      FileUtils.rm_rf(top)
      cap
    end

    it "activates the whole tree with no store or registry" do
      package = Capsium::Package.new(build_transitive_cap)
      middle = package.resolved_dependencies.find { |dep| dep.guid == middle_guid }
      expect(middle.package.resolved_dependencies.map(&:guid))
        .to eq([CompositeSpecHelper::BASE_GUID])
      expect(middle.package.resolved_dependencies.first.path)
        .to start_with(package.path)
      package.cleanup
    end
  end

  describe "capsium package pack --bundle-deps" do
    it "packs a self-contained .cap that loads with no store" do
      source = File.join(workdir, "composite-package")
      FileUtils.cp_r(composite_source, source)

      output = capture_stdout do
        Capsium::Cli::Package.start(
          ["pack", source, "--bundle-deps", "--store", store_dir]
        )
      end
      expect(output).to include("Package created:")

      ENV.delete("CAPSIUM_STORE")
      cap_path = File.join(workdir, "composite-package-0.1.0.cap")
      package = Capsium::Package.new(cap_path)
      expect(package.resolved_dependencies.first.version).to eq("1.2.0")
      package.cleanup
    end

    it "accepts --bundle as an alias" do
      source = File.join(workdir, "composite-package")
      FileUtils.cp_r(composite_source, source)

      capture_stdout do
        Capsium::Cli::Package.start(["pack", source, "--bundle", "--store", store_dir])
      end

      ENV.delete("CAPSIUM_STORE")
      package = Capsium::Package.new(File.join(workdir, "composite-package-0.1.0.cap"))
      expect(package.resolved_dependencies.first.version).to eq("1.2.0")
      package.cleanup
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
