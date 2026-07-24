# frozen_string_literal: true

require "spec_helper"
require "json"
require "net/http"
require "socket"
require "tmpdir"
require "webrick"

RSpec.describe "Reactor with multiple mounted packages" do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }
  let(:bare_source) { File.join(fixtures_path, "bare-package") }
  let(:data_source) { File.join(fixtures_path, "data-package") }
  let(:readonly_source) { File.join(fixtures_path, "readonly-package") }
  let(:mock_server) { instance_double(WEBrick::HTTPServer) }

  before do
    allow(WEBrick::HTTPServer).to receive(:new).and_return(mock_server)
    allow(mock_server).to receive(:mount_proc)
    allow(mock_server).to receive(:start)
    allow(mock_server).to receive(:shutdown)
  end

  after do
    Thread.list.each { |thread| thread.kill if thread != Thread.current }
  end

  def entry(path, source)
    Capsium::Reactor::Mount::Entry.new(path: path, source: source, store: nil)
  end

  def reactor_for(mounts)
    Capsium::Reactor.new(mounts: mounts, do_not_listen: true)
  end

  # Calls the handler directly (rack-free) and captures the response.
  def request_to(app, path, method: "GET", query: {})
    request = instance_double(WEBrick::HTTPRequest, path: path,
                                                    request_method: method,
                                                    query: query)
    # Allow header lookups (If-None-Match, etc.) without forcing every
    # spec to opt in.
    allow(request).to receive(:[]).and_return(nil)
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

  context "with two packages at distinct explicit prefixes" do
    let(:app) do
      reactor_for(Capsium::Reactor::Mount.build(
                    [entry("/bare", bare_source), entry("/data", data_source)]
                  ))
    end

    it "serves each package under its own prefix" do
      bare = request_to(app, "/bare/index.html")
      expect(bare[:status]).to eq(200)
      expect(bare[:headers]["Content-Type"]).to eq("text/html")
      expect(bare[:body]).to eq(File.read(File.join(bare_source, "content/index.html")))

      data = request_to(app, "/data/index.html")
      expect(data[:status]).to eq(200)
      expect(data[:body]).to eq(File.read(File.join(data_source, "content/index.html")))
    end

    it "serves the mount prefix itself as the index route" do
      expect(request_to(app, "/bare")[:status]).to eq(200)
    end

    it "serves datasets under the package prefix" do
      result = request_to(app, "/data/api/v1/data/animals")

      expect(result[:status]).to eq(200)
      expect(result[:headers]["Content-Type"]).to eq("application/json")
      expect(JSON.parse(result[:body])["animals"]).to be_an(Array)
    end

    it "does not leak one package's routes into the other prefix" do
      expect(request_to(app, "/bare/api/v1/data/animals")[:status]).to eq(404)
      expect(request_to(app, "/data/example.css")[:status]).to eq(200)
      expect(request_to(app, "/nonexistent-prefix/")[:status]).to eq(404)
    end

    it "mounts the non-root prefixes on the server" do
      app
      expect(mock_server).to have_received(:mount_proc).with("/bare")
      expect(mock_server).to have_received(:mount_proc).with("/data")
    end
  end

  context "with a / mount and a derived named mount" do
    let(:app) do
      reactor_for(Capsium::Reactor::Mount.build(
                    [entry(nil, bare_source), entry(nil, data_source)]
                  ))
    end

    it "serves the first package at / and the second at /<name>/" do
      expect(request_to(app, "/index.html")[:body])
        .to eq(File.read(File.join(bare_source, "content/index.html")))

      named = request_to(app, "/data-package/index.html")
      expect(named[:status]).to eq(200)
      expect(named[:body])
        .to eq(File.read(File.join(data_source, "content/index.html")))
    end

    it "serves the named mount's dataset route" do
      result = request_to(app, "/data-package/api/v1/data/animals")

      expect(result[:status]).to eq(200)
      expect(JSON.parse(result[:body])["categories"]).to be_an(Array)
    end
  end

  context "with mounts loaded from a JSON config file" do
    it "serves exactly the configured mount map" do
      Dir.mktmpdir do |dir|
        config = File.join(dir, "mounts.json")
        File.write(config, JSON.generate(
                             "mounts" => [
                               { "path" => "/", "source" => bare_source },
                               { "path" => "/named", "source" => data_source }
                             ]
                           ))
        mounts = Capsium::Reactor::Mount.build(
          Capsium::Reactor::Mount.config_entries(config)
        )
        app = reactor_for(mounts)

        expect(request_to(app, "/index.html")[:status]).to eq(200)
        expect(request_to(app, "/named/index.html")[:status]).to eq(200)
        expect(request_to(app, "/data-package/index.html")[:status]).to eq(404)
      end
    end
  end

  describe "aggregated introspection" do
    let(:app) do
      reactor_for(Capsium::Reactor::Mount.build(
                    [entry(nil, bare_source), entry(nil, data_source)]
                  ))
    end

    it "lists every mounted package in /api/v1/introspect/metadata" do
      result = request_to(app, "/api/v1/introspect/metadata")

      expect(result[:status]).to eq(200)
      names = JSON.parse(result[:body])["packages"].map { |pkg| pkg["name"] }
      expect(names).to eq(%w[bare-package data-package])
    end

    it "reports routes per package in /api/v1/introspect/routes" do
      parsed = JSON.parse(request_to(app, "/api/v1/introspect/routes")[:body])

      expect(parsed["routes"].map { |entry| entry["package"] })
        .to eq(%w[bare-package data-package])
      animals = parsed["routes"].find { |entry| entry["package"] == "data-package" }
      expect(animals["routes"]).to include("method" => "GET",
                                           "path" => "/api/v1/data/animals")
    end

    it "hashes every package in /api/v1/introspect/content-hashes" do
      parsed = JSON.parse(request_to(app, "/api/v1/introspect/content-hashes")[:body])

      expect(parsed["contentHashes"].map { |entry| entry["package"] })
        .to eq(%w[bare-package data-package])
      expect(parsed["contentHashes"].map { |entry| entry["hash"] })
        .to all(match(/\A[0-9a-f]{64}\z/))
    end

    it "checks every package in /api/v1/introspect/content-validity" do
      parsed = JSON.parse(request_to(app, "/api/v1/introspect/content-validity")[:body])

      expect(parsed["contentValidity"].map { |entry| entry["package"] })
        .to eq(%w[bare-package data-package])
      expect(parsed["contentValidity"].map { |entry| entry["valid"] })
        .to eq([true, true])
    end

    it "counts the mounted packages in /introspect/status" do
      body = JSON.parse(request_to(app, "/introspect/status")[:body])

      expect(body["packagesLoaded"]).to eq(2)
    end
  end

  describe "per-package endpoints resolved by name" do
    let(:app) do
      reactor_for(Capsium::Reactor::Mount.build(
                    [entry(nil, bare_source), entry(nil, data_source)]
                  ))
    end

    it "reports status per package name" do
      %w[bare-package data-package].each do |name|
        body = JSON.parse(request_to(app, "/package/#{name}/status")[:body])
        expect(body["package"]).to eq(name)
        expect(body["status"]).to eq("loaded")
      end
    end

    it "returns metadata per package name" do
      body = JSON.parse(request_to(app, "/package/data-package/metadata")[:body])

      expect(body["name"]).to eq("data-package")
      expect(body["description"]).to eq("A package with data")
    end

    it "returns the reactor logs per package name" do
      request_to(app, "/index.html")

      body = JSON.parse(request_to(app, "/package/bare-package/logs")[:body])
      expect(body["package"]).to eq("bare-package")
      expect(body["logs"].last).to include("GET /index.html -> 200")
    end

    it "returns 404 for an unknown package name" do
      result = request_to(app, "/package/nope/status")

      expect(result[:status]).to eq(404)
      expect(result[:headers]["Content-Type"]).to eq("text/plain")
    end
  end

  describe "#cleanup" do
    it "cleans up every mounted package" do
      packages = [Capsium::Package.new(bare_source),
                  Capsium::Package.new(data_source)]
      packages.each { |package| allow(package).to receive(:cleanup) }
      mounts = packages.each_with_index.map do |package, index|
        Capsium::Reactor::Mount.new(path: index.zero? ? "/" : "/#{package.name}",
                                    package: package)
      end

      reactor_for(mounts).cleanup

      expect(packages).to all(have_received(:cleanup))
    end
  end

  describe "live server on an ephemeral port" do
    it "serves two packages at their prefixes with aggregated introspection" do
      allow(WEBrick::HTTPServer).to receive(:new).and_call_original
      probe = TCPServer.new("127.0.0.1", 0)
      port = probe.addr[1]
      probe.close
      mounts = Capsium::Reactor::Mount.build(
        [entry(nil, bare_source), entry(nil, data_source)]
      )
      live = Capsium::Reactor.new(mounts: mounts, port: port)
      thread = Thread.new { live.server.start }

      expect(http_get(port, "/index.html").code).to eq("200")
      expect(http_get(port, "/data-package/index.html").code).to eq("200")
      expect(http_get(port, "/data-package/api/v1/data/animals").code).to eq("200")

      metadata = JSON.parse(http_get(port, "/api/v1/introspect/metadata").body)
      expect(metadata["packages"].map { |pkg| pkg["name"] })
        .to eq(%w[bare-package data-package])

      expect(http_get(port, "/package/data-package/status").code).to eq("200")
      expect(http_get(port, "/package/nope/status").code).to eq("404")
    ensure
      live&.server&.shutdown
      thread&.join(5)
      live&.cleanup
    end
  end

  describe "CLI --mount option merging" do
    it "accumulates repeated --mount flags" do
      merged = Capsium::Cli::Reactor.merge_mount_options(
        ["pkg1", "--mount", "/a=p2", "--mount", "/b=p3", "--port", "9000"]
      )

      expect(merged).to eq(["pkg1", "--port", "9000", "--mount", "/a=p2", "/b=p3"])
    end

    it "handles the --mount=PATH=SOURCE form" do
      merged = Capsium::Cli::Reactor.merge_mount_options(
        ["--mount=/a=p1", "--mount", "/b=p2"]
      )

      expect(merged).to eq(["--mount", "/a=p1", "/b=p2"])
    end

    it "leaves arguments untouched without --mount" do
      args = ["pkg1", "pkg2", "--port", "9000"]

      expect(Capsium::Cli::Reactor.merge_mount_options(args)).to eq(args)
    end

    it "mounts positional and repeated --mount sources through the Thor dispatch" do
      created = nil
      allow(Capsium::Reactor).to receive(:new).and_wrap_original do |original, **kwargs|
        created = original.call(**kwargs)
        allow(created).to receive(:serve)
        created
      end

      Dir.mktmpdir do |dir|
        Capsium::Cli.start(["reactor", "serve", data_source,
                            "--mount", "/ro=#{readonly_source}",
                            "--mount", "/bare=#{bare_source}",
                            "--workdir", dir, "--do_not_listen",
                            "--port", "18997"])
      end

      mounts = created.mounts.map { |mount| [mount.path, mount.package.name] }
      expect(mounts).to eq([["/ro", "readonly-package"],
                            ["/bare", "bare-package"],
                            ["/data-package", "data-package"]])
      expect(created.mounts.map(&:writable?)).to eq([false, true, true])
    ensure
      created&.cleanup
    end

    it "forces every mount read-only via the --read-only flag (issue #27)" do
      created = nil
      allow(Capsium::Reactor).to receive(:new).and_wrap_original do |original, **kwargs|
        created = original.call(**kwargs)
        allow(created).to receive(:serve)
        created
      end

      Dir.mktmpdir do |dir|
        Capsium::Cli.start(["reactor", "serve", data_source,
                            "--mount", "/bare=#{bare_source}",
                            "--read-only",
                            "--workdir", dir, "--do_not_listen",
                            "--port", "18998"])
      end

      expect(created.mounts.map(&:writable?)).to eq([false, false])
    ensure
      created&.cleanup
    end
  end

  def http_get(port, path)
    uri = URI("http://127.0.0.1:#{port}#{path}")
    20.times do
      return Net::HTTP.get_response(uri)
    rescue SystemCallError
      sleep(0.1)
    end
    Net::HTTP.get_response(uri)
  end
end
