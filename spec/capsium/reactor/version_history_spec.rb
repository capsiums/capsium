# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "webrick"

# Version history + rollback (TODO 33). POST /package/<name>/save
# now records the saved .cap in a per-package JSONL history under the
# reactor workdir. GET /package/<name>/versions lists every recorded
# version. POST /package/<name>/rollback?to=<version-or-sha> swaps
# the mount's source to the named saved .cap and reloads (overlay
# survives so subsequent writes still work).
RSpec.describe "Reactor version history + rollback" do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }
  let(:source) { File.join(fixtures_path, "writable-package") }
  let(:mock_server) { instance_double(WEBrick::HTTPServer) }

  before do
    allow(WEBrick::HTTPServer).to receive(:new).and_return(mock_server)
    allow(mock_server).to receive(:mount_proc)
    allow(mock_server).to receive(:start)
    allow(mock_server).to receive(:shutdown)
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @workdir = dir
      example.run
    end
  end

  def build_reactor
    entries = [Capsium::Reactor::Mount::Entry.new(path: nil, source: source, store: nil)]
    mounts = Capsium::Reactor::Mount.build(entries)
    Capsium::Reactor.new(mounts: mounts, workdir: @workdir, do_not_listen: true)
  end

  def request_to(app, path, method: "GET", body: nil, query: nil)
    request = instance_double(WEBrick::HTTPRequest, path: path,
                                                    request_method: method,
                                                    body: body)
    allow(request).to receive(:[]).and_return(nil)
    allow(request).to receive(:query).and_return(query)
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

  def json(result)
    JSON.parse(result[:body])
  end

  let(:app) { build_reactor }

  describe "VersionHistory" do
    it "records each save as a JSONL line under versions/<name>.jsonl" do
      history = Capsium::Reactor::VersionHistory.new(dir: @workdir, package_name: "demo")
      history.record(version: "0.1.0", sha256: "a" * 64, path: "/tmp/a.cap")
      history.record(version: "0.1.1", sha256: "b" * 64, path: "/tmp/b.cap")

      expect(history.all.map(&:version)).to eq(%w[0.1.0 0.1.1])
    end

    it "is idempotent on sha256 (re-recording same bytes doesn't duplicate)" do
      history = Capsium::Reactor::VersionHistory.new(dir: @workdir, package_name: "demo")
      first = history.record(version: "0.1.0", sha256: "x" * 64, path: "/tmp/x.cap")
      second = history.record(version: "0.1.0", sha256: "x" * 64, path: "/tmp/x.cap")

      expect(first.sha256).to eq(second.sha256)
      expect(history.all.length).to eq(1)
    end

    it "finds a record by version OR sha256 (newest match wins)" do
      history = Capsium::Reactor::VersionHistory.new(dir: @workdir, package_name: "demo")
      history.record(version: "0.1.0", sha256: "a" * 64, path: "/tmp/a.cap")
      history.record(version: "0.1.0", sha256: "b" * 64, path: "/tmp/b.cap")

      expect(history.find("0.1.0").sha256).to eq("b" * 64)
      expect(history.find("a" * 64).sha256).to eq("a" * 64)
    end
  end

  describe "POST /package/<name>/save records in history" do
    it "the saved record appears in GET /package/<name>/versions" do
      saved = request_to(app, "/package/writable-package/save", method: "POST")
      expect(saved[:status]).to eq(200)
      saved_version = json(saved)["version"]

      versions = request_to(app, "/package/writable-package/versions")
      expect(versions[:status]).to eq(200)
      list = json(versions)
      expect(list.last["version"]).to eq(saved_version)
      expect(list.last["sha256"]).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  describe "POST /package/<name>/rollback?to=<version>" do
    it "swaps the mount's source to the saved .cap" do
      saved = request_to(app, "/package/writable-package/save", method: "POST")
      saved_version = json(saved)["version"]

      rolled = request_to(app, "/package/writable-package/rollback",
                          method: "POST", query: { "to" => saved_version })
      expect(rolled[:status]).to eq(200)
      expect(json(rolled)["rolled_back_to"]["version"]).to eq(saved_version)
    end

    it "returns 404 when no version matches" do
      result = request_to(app, "/package/writable-package/rollback",
                          method: "POST", query: { "to" => "9.9.9" })
      expect(result[:status]).to eq(404)
    end

    it "returns 400 when 'to' query parameter is missing" do
      result = request_to(app, "/package/writable-package/rollback",
                          method: "POST", query: {})
      expect(result[:status]).to eq(400)
    end

    it "returns 404 when the package name is unknown" do
      result = request_to(app, "/package/no-such-package/rollback",
                          method: "POST", query: { "to" => "0.1.0" })
      expect(result[:status]).to eq(404)
    end
  end

  describe "GET /package/<name>/versions" do
    it "returns 405 on non-GET" do
      result = request_to(app, "/package/writable-package/versions", method: "POST")
      expect(result[:status]).to eq(405)
    end

    it "returns 404 when the package name is unknown" do
      result = request_to(app, "/package/no-such-package/versions")
      expect(result[:status]).to eq(404)
    end
  end
end
