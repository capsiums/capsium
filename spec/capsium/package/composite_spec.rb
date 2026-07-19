# frozen_string_literal: true

require "spec_helper"
require "webrick"
require_relative "composite_spec_helper"

RSpec.describe "Composite packages (ARCHITECTURE.md section 4a)" do
  let(:fixtures_path) do
    File.expand_path(File.join(__dir__, "..", "..", "fixtures"))
  end
  let(:composite_path) { File.join(fixtures_path, "composite-package") }
  let(:workdir) { Dir.mktmpdir }
  let(:store_dir) { CompositeSpecHelper.build_store(workdir) }

  after { FileUtils.rm_rf(workdir) }

  describe "dependency resolution" do
    let(:package) { Capsium::Package.new(composite_path, store: store_dir) }

    after { package.cleanup }

    it "resolves the newest satisfying store version" do
      dependency = package.resolved_dependencies.first
      expect(dependency.guid).to eq(CompositeSpecHelper::BASE_GUID)
      expect(dependency.range).to eq("^1.0.0")
      expect(dependency.version).to eq("1.2.0")
      expect(dependency.path).to end_with("base-package-1.2.0.cap")
      expect(dependency.package.metadata.name).to eq("base-package")
    end

    it "resolves via CAPSIUM_STORE when no store is passed" do
      ENV["CAPSIUM_STORE"] = store_dir
      env_package = Capsium::Package.new(composite_path)
      expect(env_package.resolved_dependencies.first.version).to eq("1.2.0")
    ensure
      ENV.delete("CAPSIUM_STORE")
      env_package&.cleanup
    end

    it "raises DependencyError when no store is configured" do
      ENV.delete("CAPSIUM_STORE")
      expect { Capsium::Package.new(composite_path) }
        .to raise_error(Capsium::Package::DependencyError, /no package store/)
    end

    it "raises DependencyNotFoundError for a missing dependency" do
      dependent = CompositeSpecHelper.write_dependent(
        workdir, name: "missing-dep", routes: [],
                 dependencies: { "https://example.com/capsiums/unknown" => "*" }
      )
      expect { Capsium::Package.new(dependent, store: store_dir) }
        .to raise_error(Capsium::Package::DependencyNotFoundError, /unknown/)
    end

    it "raises UnsatisfiableDependencyError for an unsatisfiable range" do
      dependent = CompositeSpecHelper.write_dependent(
        workdir, name: "unsatisfiable", routes: [],
                 dependencies: { CompositeSpecHelper::BASE_GUID => ">=9.0.0" }
      )
      expect { Capsium::Package.new(dependent, store: store_dir) }
        .to raise_error(Capsium::Package::UnsatisfiableDependencyError)
    end

    it "raises CircularDependencyError for dependency cycles" do
      circular_store = CompositeSpecHelper.build_circular_store(workdir)
      cap = File.join(circular_store, "circular-a-1.0.0.cap")
      expect { Capsium::Package.new(cap, store: circular_store) }
        .to raise_error(Capsium::Package::CircularDependencyError, /circular/)
    end
  end

  describe "merged view with dependency layers" do
    let(:package) { Capsium::Package.new(composite_path, store: store_dir) }
    let(:dependency_path) do
      package.resolved_dependencies.first.package.path
    end

    after { package.cleanup }

    it "falls through to dependency content the package lacks" do
      expect(package.merged_view.resolve("content/app.js"))
        .to eq(File.join(dependency_path, "content", "app.js"))
    end

    it "prefers the package's own layers over dependency content" do
      expect(package.merged_view.resolve("content/shared.txt"))
        .to eq(File.join(composite_path, "content", "shared.txt"))
    end

    it "hides private dependency resources" do
      expect(package.merged_view.resolve("content/secret.txt")).to be_nil
    end

    it "resolves explicit dependency references by GUID" do
      reference = "#{CompositeSpecHelper::BASE_GUID}/content/public.txt"
      expect(package.merged_view.resolve(reference))
        .to eq(File.join(dependency_path, "content", "public.txt"))
    end

    it "returns nil for references to unknown dependencies" do
      expect(package.merged_view.resolve("https://example.com/capsiums/unknown/content/x"))
        .to be_nil
    end
  end

  describe "route reference validation" do
    it "rejects references to a dependency's private resource" do
      dependent = CompositeSpecHelper.write_dependent(
        workdir, name: "bad-visibility",
                 dependencies: { CompositeSpecHelper::BASE_GUID => "^1.0.0" },
                 routes: [{ "path" => "/secret",
                            "resource" => "#{CompositeSpecHelper::BASE_GUID}/content/secret.txt" }]
      )
      expect { Capsium::Package.new(dependent, store: store_dir) }
        .to raise_error(Capsium::Package::DependencyVisibilityError, /private/)
    end

    it "rejects references to a resource missing from the dependency" do
      dependent = CompositeSpecHelper.write_dependent(
        workdir, name: "bad-resource",
                 dependencies: { CompositeSpecHelper::BASE_GUID => "^1.0.0" },
                 routes: [{ "path" => "/nope",
                            "resource" => "#{CompositeSpecHelper::BASE_GUID}/content/nope.txt" }]
      )
      expect { Capsium::Package.new(dependent, store: store_dir) }
        .to raise_error(Capsium::Package::DependencyError, /missing/)
    end

    it "rejects references to undeclared dependencies" do
      dependent = CompositeSpecHelper.write_dependent(
        workdir, name: "bad-guid", dependencies: {},
                 routes: [{ "path" => "/x",
                            "resource" => "https://example.com/capsiums/unknown/content/x.txt" }]
      )
      expect { Capsium::Package.new(dependent, store: store_dir) }
        .to raise_error(Capsium::Package::DependencyError, /unknown dependency/)
    end
  end

  describe "reactor serving with route inheritance" do
    let(:mock_server) { instance_double(WEBrick::HTTPServer) }
    let(:package) { Capsium::Package.new(composite_path, store: store_dir) }
    let(:reactor) { Capsium::Reactor.new(package: package, do_not_listen: true) }

    before do
      allow(WEBrick::HTTPServer).to receive(:new).and_return(mock_server)
      allow(mock_server).to receive(:mount_proc)
      allow(mock_server).to receive(:start)
      allow(mock_server).to receive(:shutdown)
    end

    after { package.cleanup }

    def request_to(app, path)
      request = instance_double(WEBrick::HTTPRequest, path: path,
                                                      request_method: "GET")
      response = instance_double(WEBrick::HTTPResponse)
      result = { headers: {} }
      allow(response).to receive(:status=) { |value| result[:status] = value }
      allow(response).to receive(:status) { result[:status] }
      allow(response).to receive(:[]=) do |name, value|
        result[:headers][name] = value
      end
      allow(response).to receive(:body=) { |value| result[:body] = value }
      app.handle_request(request, response)
      result
    end

    it "serves dependency content reached by implicit fallthrough" do
      result = request_to(reactor, "/app.js")
      expect(result[:status]).to eq(200)
      expect(result[:headers]["Content-Type"]).to eq("text/javascript")
      expect(result[:body]).to eq("console.log('base 1.2.0');")
    end

    it "prefers the package's own content over dependency content" do
      expect(request_to(reactor, "/shared.txt")[:body]).to eq("composite shared\n")
    end

    it "serves explicit dependency references" do
      result = request_to(reactor, "/vendor/public.txt")
      expect(result[:status]).to eq(200)
      expect(result[:body]).to eq("public 1.2.0")
    end

    it "serves remapped routes at the remapped path only" do
      expect(request_to(reactor, "/core/app.js")[:body])
        .to eq("console.log('base 1.2.0');")
      expect(request_to(reactor, "/vendor/app.js")[:status]).to eq(404)
    end

    it "mounts serving paths (remap replaces the mount path)" do
      reactor
      expect(mock_server).to have_received(:mount_proc).with("/core/app.js")
      expect(mock_server).not_to have_received(:mount_proc).with("/vendor/app.js")
    end

    it "rewrites inherited responses (responseRewrite body and headers)" do
      result = request_to(reactor, "/rewritten")
      expect(result[:status]).to eq(200)
      expect(result[:body]).to eq("Modified response content")
      expect(result[:headers]["X-Custom-Header"]).to eq("CustomValue")
    end

    it "merges responseHeaders over the served headers" do
      result = request_to(reactor, "/enhanced")
      expect(result[:headers]["Cache-Control"]).to eq("no-cache")
      expect(result[:headers]["X-Enhanced-Header"]).to eq("EnhancedValue")
      expect(result[:body]).to eq("public 1.2.0")
    end

    it "serves requestHeaders routes statically (documented no-op)" do
      result = request_to(reactor, "/supplanted")
      expect(result[:status]).to eq(200)
      expect(result[:body]).to eq("public 1.2.0")
    end
  end
end
