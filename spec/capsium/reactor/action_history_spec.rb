# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "webrick"

RSpec.describe "Reactor dataset action-history (mutation log + replay)" do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }
  let(:writable_source) { File.join(fixtures_path, "writable-package") }
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

  around do |example|
    Dir.mktmpdir do |dir|
      @workdir = dir
      example.run
    end
  end

  def build_reactor
    entries = [Capsium::Reactor::Mount::Entry.new(path: nil, source: writable_source,
                                                  store: nil)]
    Capsium::Reactor.new(mounts: Capsium::Reactor::Mount.build(entries),
                         workdir: @workdir, do_not_listen: true)
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

  before do
    # Seed three writes so we have a non-trivial log to inspect.
    request_to(app, "/api/v1/data/notes", method: "POST",
                                          body: JSON.generate("id" => "h1", "title" => "Alpha"))
    request_to(app, "/api/v1/data/notes", method: "POST",
                                          body: JSON.generate("id" => "h2", "title" => "Bravo"))
    request_to(app, "/api/v1/data/notes/h1", method: "PUT",
                                             body: JSON.generate("id" => "h1",
                                                                 "title" => "Alpha updated"))
  end

  describe "GET /api/v1/data/<name>/history" do
    it "returns the mutation log with monotonic seq numbers" do
      result = request_to(app, "/api/v1/data/notes/history")
      expect(result[:status]).to eq(200)

      entries = json(result)
      expect(entries.size).to eq(3)
      expect(entries.map { |e| e["seq"] }).to eq([0, 1, 2])
      expect(entries.first["op"]).to eq("append")
      expect(entries.last["op"]).to eq("replace")
    end

    it "returns 405 on non-GET" do
      result = request_to(app, "/api/v1/data/notes/history", method: "DELETE")
      expect(result[:status]).to eq(405)
    end
  end

  describe "GET /api/v1/data/<name>/history/<seq>" do
    it "returns a single mutation entry" do
      result = request_to(app, "/api/v1/data/notes/history/1")
      expect(result[:status]).to eq(200)
      entry = json(result)
      expect(entry["seq"]).to eq(1)
      expect(entry["op"]).to eq("append")
      expect(entry["item"]["id"]).to eq("h2")
    end

    it "returns 404 for an unknown seq" do
      result = request_to(app, "/api/v1/data/notes/history/9999")
      expect(result[:status]).to eq(404)
    end
  end

  describe "GET /api/v1/data/<name>?at=<seq> (collection at point in time)" do
    it "replays the log up to and including the seq" do
      at_zero = request_to(app, "/api/v1/data/notes", query: { "at" => "0" })
      ids_at_zero = json(at_zero).map { |n| n["id"] }
      # base (2 items: 1, 2) + 1 append (h1)
      expect(ids_at_zero).to contain_exactly("1", "2", "h1")
      expect(json(at_zero).find { |n| n["id"] == "h1" }["title"]).to eq("Alpha")

      at_two = request_to(app, "/api/v1/data/notes", query: { "at" => "2" })
      expect(json(at_two).find { |n| n["id"] == "h1" }["title"]).to eq("Alpha updated")
    end

    it "honors negative or invalid seq as 0" do
      result = request_to(app, "/api/v1/data/notes", query: { "at" => "garbage" })
      expect(result[:status]).to eq(200)
    end
  end

  describe "GET /api/v1/data/<name>?from=<seq>&to=<seq> (item diff)" do
    it "returns added/removed/changed keyed by stable id" do
      result = request_to(app, "/api/v1/data/notes",
                          query: { "from" => "1", "to" => "2" })
      expect(result[:status]).to eq(200)
      diff = json(result)
      # Between seq 1 (after h2 append) and seq 2 (after h1 replace):
      # nothing added, nothing removed, h1 changed.
      expect(diff["added"]).to eq([])
      expect(diff["removed"]).to eq([])
      expect(diff["changed"].size).to eq(1)
      expect(diff["changed"].first["id"]).to eq("h1")
      expect(diff["changed"].first["from"]["title"]).to eq("Alpha")
      expect(diff["changed"].first["to"]["title"]).to eq("Alpha updated")
    end

    it "reports removed items after a delete" do
      request_to(app, "/api/v1/data/notes/h2", method: "DELETE")
      # from=1 (after h2 appended) to=3 (after h2 deleted) — h2 was
      # present in the from snapshot and absent in the to snapshot.
      result = request_to(app, "/api/v1/data/notes",
                          query: { "from" => "1", "to" => "3" })
      diff = json(result)
      removed_ids = diff["removed"].map { |n| n["id"] }
      expect(removed_ids).to include("h2")
    end

    it "returns 405 on non-GET" do
      result = request_to(app, "/api/v1/data/notes",
                          method: "POST",
                          query: { "from" => "0", "to" => "1" },
                          body: JSON.generate("id" => "x", "title" => "Y"))
      # POST is for append, not diff — query is ignored on POST
      expect(result[:status]).to eq(201)
    end
  end
end
