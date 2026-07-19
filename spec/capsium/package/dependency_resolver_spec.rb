# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "composite_spec_helper"

RSpec.describe Capsium::Package::DependencyResolver do
  let(:workdir) { Dir.mktmpdir }
  let(:guid) { CompositeSpecHelper::BASE_GUID }

  after { FileUtils.rm_rf(workdir) }

  # An empty store directory plus a Local registry holding base-package
  # at the given versions.
  def build_store_and_registry(versions)
    store_dir = File.join(workdir, "store")
    FileUtils.mkdir_p(store_dir)
    registry = Capsium::Registry.fetch(File.join(workdir, "registry"))
    versions.each do |version|
      package_dir = CompositeSpecHelper.write_package(
        workdir, name: "base-package", version: version, guid: guid,
                 files: { "index.html" => "<html>base #{version}</html>" }
      )
      registry.push(CompositeSpecHelper.pack(workdir, package_dir))
    end
    [store_dir, registry]
  end

  describe "store hits" do
    let(:store_dir) { CompositeSpecHelper.build_store(workdir) }

    it "resolves from the store without consulting the registry" do
      _store_dir, registry = build_store_and_registry(["9.9.9"])
      resolver = described_class.new(store_dir, registry: registry)

      expect(resolver.resolve_path(guid, "^1.0.0", chain: []))
        .to end_with("base-package-1.2.0.cap")
    end

    it "raises UnsatisfiableDependencyError without falling back when the " \
       "store has the GUID but no satisfying version" do
      _store_dir, registry = build_store_and_registry(["9.9.9"])
      resolver = described_class.new(store_dir, registry: registry)

      expect { resolver.resolve_path(guid, ">=9.0.0", chain: []) }
        .to raise_error(Capsium::Package::UnsatisfiableDependencyError)
    end
  end

  describe "registry fallback (store -> registry -> typed error)" do
    it "installs from the registry when the store misses the GUID" do
      store_dir, registry = build_store_and_registry(["1.2.0", "2.0.0"])
      resolver = described_class.new(store_dir, registry: registry)

      path = resolver.resolve_path(guid, "^1.0.0", chain: [])

      expect(path).to eq(File.join(store_dir, "base-package-1.2.0.cap"))
      expect(File).to exist(path)
      index = JSON.parse(File.read(File.join(store_dir, "index.json")))
      expect(index[guid]).to eq("base-package-1.2.0.cap")
    end

    it "accepts a registry reference string" do
      store_dir, registry = build_store_and_registry(["1.2.0"])
      resolver = described_class.new(store_dir, registry: registry.location)

      expect(resolver.resolve_path(guid, "*", chain: []))
        .to end_with("base-package-1.2.0.cap")
    end

    it "uses CAPSIUM_REGISTRY when no registry is given" do
      store_dir, registry = build_store_and_registry(["1.2.0"])
      ENV["CAPSIUM_REGISTRY"] = registry.location
      resolver = described_class.new(store_dir)

      expect(resolver.resolve_path(guid, "*", chain: []))
        .to end_with("base-package-1.2.0.cap")
    ensure
      ENV.delete("CAPSIUM_REGISTRY")
    end

    it "raises DependencyNotFoundError mentioning the registry when " \
       "neither has the GUID" do
      store_dir, registry = build_store_and_registry(["1.2.0"])
      resolver = described_class.new(store_dir, registry: registry)

      expect { resolver.resolve_path("https://example.com/unknown", "*", chain: []) }
        .to raise_error(Capsium::Package::DependencyNotFoundError, /registry/)
    end

    it "raises UnsatisfiableDependencyError when only unsatisfying " \
       "registry versions exist" do
      store_dir, registry = build_store_and_registry(["1.2.0"])
      resolver = described_class.new(store_dir, registry: registry)

      expect { resolver.resolve_path(guid, ">=9.0.0", chain: []) }
        .to raise_error(Capsium::Package::UnsatisfiableDependencyError,
                        />=9\.0\.0/)
    end

    it "re-raises the store error when no registry is configured" do
      store_dir, = build_store_and_registry([])
      resolver = described_class.new(store_dir)

      expect { resolver.resolve_path(guid, "*", chain: []) }
        .to raise_error(Capsium::Package::DependencyNotFoundError,
                        /no package for dependency/)
    end

    it "checks circularity before consulting store or registry" do
      store_dir, registry = build_store_and_registry(["1.2.0"])
      resolver = described_class.new(store_dir, registry: registry)

      expect { resolver.resolve_path(guid, "*", chain: [guid]) }
        .to raise_error(Capsium::Package::CircularDependencyError)
    end
  end

  describe "composite package loading through the fallback" do
    it "resolves a dependency that only exists in the registry" do
      store_dir, registry = build_store_and_registry(["1.2.0"])
      dependent = CompositeSpecHelper.write_dependent(
        workdir, name: "registry-dep", routes: [],
                 dependencies: { guid => "^1.0.0" }
      )

      package = Capsium::Package.new(dependent, store: store_dir,
                                                registry: registry)

      dependency = package.resolved_dependencies.first
      expect(dependency.version).to eq("1.2.0")
      expect(dependency.path).to eq(File.join(store_dir, "base-package-1.2.0.cap"))
    ensure
      package&.cleanup
    end
  end
end
