# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "webrick"

RSpec.describe "Reactor GraphQL API" do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }
  let(:writable_source) { File.join(fixtures_path, "writable-package") }
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

  around do |example|
    Dir.mktmpdir do |dir|
      @workdir = dir
      example.run
    end
  end

  def build_reactor(source)
    entry = Capsium::Reactor::Mount::Entry.new(path: nil, source: source, store: nil)
    Capsium::Reactor.new(mounts: Capsium::Reactor::Mount.build([entry]),
                         workdir: @workdir, do_not_listen: true)
  end

  def graphql_post(app, payload)
    request = instance_double(WEBrick::HTTPRequest, path: "/graphql",
                                                    request_method: "POST",
                                                    body: JSON.generate(payload))
    capture(app, request)
  end

  def graphql_get(app, query)
    request = instance_double(WEBrick::HTTPRequest, path: "/graphql",
                                                    request_method: "GET",
                                                    body: nil,
                                                    query: { "query" => query })
    capture(app, request)
  end

  def graphql_request(app, method)
    request = instance_double(WEBrick::HTTPRequest, path: "/graphql",
                                                    request_method: method,
                                                    body: nil)
    capture(app, request)
  end

  def capture(app, request)
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

  let(:app) { build_reactor(writable_source) }

  describe "queries" do
    it "lists the merged collection with schema-derived fields" do
      result = graphql_post(app, query: "{ notes { id title body } }")

      expect(result[:status]).to eq(200)
      expect(json(result)["data"]["notes"]).to eq(
        [{ "id" => "1", "title" => "First note", "body" => "alpha" },
         { "id" => "2", "title" => "Second note", "body" => "beta" }]
      )
    end

    it "selects a single item with the id argument" do
      result = graphql_post(app, query: '{ notes(id: "2") { title } }')

      expect(json(result)["data"]["notes"]).to eq([{ "title" => "Second note" }])
    end

    it "supports GET with a query parameter" do
      result = graphql_get(app, "{ notes { title } }")

      expect(result[:status]).to eq(200)
      expect(json(result)["data"]["notes"].size).to eq(2)
    end

    it "answers schema introspection" do
      result = graphql_post(app, query: "{ __schema { mutationType { fields { name } } } }")

      fields = json(result)["data"]["__schema"]["mutationType"]["fields"].map { |f| f["name"] }
      expect(fields).to contain_exactly("createNotes", "updateNotes", "deleteNotes")
    end

    it "returns an errors entry (not a 500) for a missing item" do
      result = graphql_post(app, query: '{ notes(id: "99") { title } }')

      expect(result[:status]).to eq(200)
      expect(json(result)["errors"].first["message"]).to include("no item 99")
    end

    it "returns an errors entry for unknown fields" do
      result = graphql_post(app, query: "{ notes { bogus } }")

      expect(json(result)["errors"].first["message"]).to include("bogus")
    end
  end

  describe "mutations" do
    it "creates, updates and deletes items, hot-swap visible" do
      created = graphql_post(app, query: <<~GRAPHQL)
        mutation { createNotes(item: {id: "g1", title: "GraphQL", body: "x"}) { id title } }
      GRAPHQL
      expect(json(created)["data"]["createNotes"]).to eq("id" => "g1", "title" => "GraphQL")

      list = json(graphql_post(app, query: "{ notes { id } }"))["data"]["notes"]
      expect(list.map { |item| item["id"] }).to include("g1")

      updated = graphql_post(app, query: <<~GRAPHQL)
        mutation { updateNotes(id: "g1", item: {id: "g1", title: "GraphQL 2"}) { title } }
      GRAPHQL
      expect(json(updated)["data"]["updateNotes"]).to eq("title" => "GraphQL 2")

      deleted = graphql_post(app, query: 'mutation { deleteNotes(id: "g1") }')
      expect(json(deleted)["data"]["deleteNotes"]).to be(true)
      expect(json(graphql_post(app, query: '{ notes(id: "g1") { id } }'))["errors"])
        .not_to be_empty
    end

    it "returns an errors entry for schema violations (422 analog)" do
      result = graphql_post(app, query: <<~GRAPHQL)
        mutation { createNotes(item: {body: "no title"}) { id } }
      GRAPHQL

      expect(result[:status]).to eq(200)
      expect(json(result)["errors"].first["message"]).to include("title")
    end

    it "returns an errors entry for missing items (404 analog)" do
      result = graphql_post(app, query: <<~GRAPHQL)
        mutation { updateNotes(id: "99", item: {title: "T"}) { id } }
      GRAPHQL

      expect(json(result)["errors"].first["message"]).to include("no item 99")

      result = graphql_post(app, query: 'mutation { deleteNotes(id: "99") }')
      expect(json(result)["errors"].first["message"]).to include("no item 99")
    end

    it "returns an errors entry for duplicate ids (409 analog)" do
      result = graphql_post(app, query: <<~GRAPHQL)
        mutation { createNotes(item: {id: "1", title: "Dupe"}) { id } }
      GRAPHQL

      expect(json(result)["errors"].first["message"]).to include("already exists")
    end
  end

  describe "read-only packages" do
    let(:app) { build_reactor(readonly_source) }

    it "serves queries but rejects mutations with an errors entry" do
      result = graphql_post(app, query: "{ notes }")
      expect(json(result)["data"]["notes"].size).to eq(1)

      mutation = graphql_post(app, query: 'mutation { createNotes(item: {title: "T"}) }')
      expect(json(mutation)["errors"].first["message"]).to include("read-only")
    end
  end

  describe "request handling" do
    it "returns 400 for an invalid JSON body or a missing query" do
      request = instance_double(WEBrick::HTTPRequest, path: "/graphql",
                                                      request_method: "POST",
                                                      body: "not json{")
      expect(capture(app, request)[:status]).to eq(400)

      expect(graphql_post(app, variables: {})[:status]).to eq(400)
    end

    it "returns 405 for unsupported methods" do
      expect(graphql_request(app, "DELETE")[:status]).to eq(405)
    end
  end
end
