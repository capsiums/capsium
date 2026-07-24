# frozen_string_literal: true

require "spec_helper"
require "json"
require "net/http"
require "socket"
require "sqlite3"
require "tmpdir"
require "webrick"

RSpec.describe "Reactor writable packages (REST CRUD over the overlay)" do
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

  def build_reactor(sources, workdir, read_only: false)
    entries = sources.map do |source|
      Capsium::Reactor::Mount::Entry.new(path: nil, source: source, store: nil)
    end
    Capsium::Reactor.new(mounts: Capsium::Reactor::Mount.build(entries),
                         workdir: workdir, do_not_listen: true,
                         read_only: read_only)
  end

  # Calls the handler directly (rack-free) and captures the response.
  def request_to(app, path, method: "GET", body: nil)
    request = instance_double(WEBrick::HTTPRequest, path: path,
                                                    request_method: method,
                                                    body: body)
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

  around do |example|
    Dir.mktmpdir do |dir|
      @workdir = dir
      example.run
    end
  end

  let(:app) { build_reactor([writable_source], @workdir) }

  describe "dataset item CRUD round-trip" do
    it "appends, reads, replaces and deletes an item" do
      item = { "id" => "7", "title" => "Seventh", "body" => "gamma" }
      created = request_to(app, "/api/v1/data/notes", method: "POST",
                                                      body: JSON.generate(item))

      expect(created[:status]).to eq(201)
      expect(created[:headers]["Location"]).to eq("/api/v1/data/notes/7")
      expect(json(created)).to eq(item)

      read = request_to(app, "/api/v1/data/notes/7")
      expect(read[:status]).to eq(200)
      expect(json(read)).to eq(item)

      updated = item.merge("body" => "delta")
      replaced = request_to(app, "/api/v1/data/notes/7", method: "PUT",
                                                         body: JSON.generate(updated))
      expect(replaced[:status]).to eq(200)
      expect(json(request_to(app, "/api/v1/data/notes/7"))).to eq(updated)

      deleted = request_to(app, "/api/v1/data/notes/7", method: "DELETE")
      expect(deleted[:status]).to eq(204)
      expect(request_to(app, "/api/v1/data/notes/7")[:status]).to eq(404)
    end

    it "echoes the id field and assigns 1-based positional ids otherwise" do
      item = { "id" => "x", "title" => "X" }
      with_id = request_to(app, "/api/v1/data/notes", method: "POST",
                                                      body: JSON.generate(item))
      expect(with_id[:headers]["Location"]).to eq("/api/v1/data/notes/x")

      without_id = request_to(app, "/api/v1/data/notes", method: "POST",
                                                         body: JSON.generate("title" => "No id"))
      # base holds two items, the "x" append is third, this is fourth
      expect(without_id[:headers]["Location"]).to eq("/api/v1/data/notes/4")
      expect(json(request_to(app, "/api/v1/data/notes/4"))["title"]).to eq("No id")
    end

    it "reads base items by their ids" do
      expect(json(request_to(app, "/api/v1/data/notes/1"))["title"]).to eq("First note")
    end

    it "returns 409 for a duplicate id on append" do
      dupe = { "id" => "1", "title" => "Dupe" }
      result = request_to(app, "/api/v1/data/notes", method: "POST",
                                                     body: JSON.generate(dupe))
      expect(result[:status]).to eq(409)
      expect(json(result)["error"]).to include("already exists")
    end

    it "returns 409 when the PUT body id does not match the path id" do
      swap = { "id" => "2", "title" => "Swap" }
      result = request_to(app, "/api/v1/data/notes/1", method: "PUT",
                                                       body: JSON.generate(swap))
      expect(result[:status]).to eq(409)
    end

    it "returns 404 for absent items and unknown datasets" do
      expect(request_to(app, "/api/v1/data/notes/99")[:status]).to eq(404)
      put_absent = request_to(app, "/api/v1/data/notes/99", method: "PUT",
                                                            body: JSON.generate("title" => "T"))
      expect(put_absent[:status]).to eq(404)
      expect(request_to(app, "/api/v1/data/notes/99", method: "DELETE")[:status]).to eq(404)
      post_unknown = request_to(app, "/api/v1/data/nope", method: "POST",
                                                          body: JSON.generate("title" => "T"))
      expect(post_unknown[:status]).to eq(404)
      expect(request_to(app, "/api/v1/data/nope/1")[:status]).to eq(404)
    end

    it "returns 405 for wrong verbs on collection and item paths" do
      expect(request_to(app, "/api/v1/data/notes", method: "PUT",
                                                   body: "{}")[:status]).to eq(405)
      expect(request_to(app, "/api/v1/data/notes", method: "DELETE")[:status]).to eq(405)
      expect(request_to(app, "/api/v1/data/notes/1", method: "POST",
                                                     body: "{}")[:status]).to eq(405)
    end

    it "returns 400 for a non-JSON body and 422 for a null body" do
      bad = request_to(app, "/api/v1/data/notes", method: "POST", body: "not json{")
      expect(bad[:status]).to eq(400)

      null = request_to(app, "/api/v1/data/notes", method: "POST", body: "null")
      expect(null[:status]).to eq(422)
    end

    it "returns 422 with the schema errors for schema violations" do
      missing_title = request_to(app, "/api/v1/data/notes", method: "POST",
                                                            body: JSON.generate("body" => "x"))
      expect(missing_title[:status]).to eq(422)
      expect(json(missing_title)["error"]).to eq("schema validation failed")
      expect(json(missing_title)["messages"].join).to include("title")

      bogus = { "title" => "T", "bogus" => 1 }
      extra_property = request_to(app, "/api/v1/data/notes/1", method: "PUT",
                                                               body: JSON.generate(bogus))
      expect(extra_property[:status]).to eq(422)
    end

    it "keeps the base package immutable on disk" do
      before = File.read(File.join(writable_source, "data", "notes.json"))
      request_to(app, "/api/v1/data/notes", method: "POST",
                                            body: JSON.generate("title" => "New"))
      request_to(app, "/api/v1/data/notes/1", method: "DELETE")

      expect(File.read(File.join(writable_source, "data", "notes.json"))).to eq(before)
      expect(json(request_to(app, "/api/v1/data/notes")).size).to eq(2)
      expect(json(request_to(app, "/api/v1/data/notes")).last["title"]).to eq("New")
    end
  end

  describe "hot-swap and overlay persistence" do
    it "serves mutations on the next request without a restart" do
      request_to(app, "/api/v1/data/notes", method: "POST",
                                            body: JSON.generate("id" => "hs", "title" => "Hot"))
      collection = json(request_to(app, "/api/v1/data/notes"))

      expect(collection.map { |item| item["id"] }).to include("hs")
    end

    it "persists the mutation log in the workdir and reloads it" do
      persisted = { "id" => "persisted", "title" => "P" }
      request_to(app, "/api/v1/data/notes", method: "POST",
                                            body: JSON.generate(persisted))
      log = File.join(@workdir, "overlays", "writable-package", "data", "notes.json")
      expect(JSON.parse(File.read(log)))
        .to eq([{ "op" => "append",
                  "item" => { "id" => "persisted", "title" => "P" } }])

      reloaded = build_reactor([writable_source], @workdir)
      expect(json(request_to(reloaded, "/api/v1/data/notes/persisted"))["title"]).to eq("P")
    end
  end

  describe "content writes (PUT/DELETE <route>)" do
    it "creates a new content file and its route on demand" do
      created = request_to(app, "/fresh.txt", method: "PUT", body: "fresh content")
      expect(created[:status]).to eq(200)

      served = request_to(app, "/fresh.txt")
      expect(served[:status]).to eq(200)
      expect(served[:body]).to eq("fresh content")
      expect(served[:headers]["Content-Type"]).to eq("text/plain")
    end

    it "overwrites an existing route's resource" do
      expect(request_to(app, "/styles.css")[:body]).to include("black")

      request_to(app, "/styles.css", method: "PUT", body: "body { color: red; }")
      expect(request_to(app, "/styles.css")[:body]).to eq("body { color: red; }")
      expect(File.read(File.join(writable_source, "content", "styles.css")))
        .to include("black")
    end

    it "tombstones a path so it 404s even though the base has it" do
      deleted = request_to(app, "/styles.css", method: "DELETE")
      expect(deleted[:status]).to eq(204)
      expect(request_to(app, "/styles.css")[:status]).to eq(404)

      tombstones = File.join(@workdir, "overlays", "writable-package",
                             "content", ".capsium-tombstones")
      expect(JSON.parse(File.read(tombstones))).to include("styles.css")
    end

    it "returns 404 when there is nothing to delete" do
      expect(request_to(app, "/never-existed.txt", method: "DELETE")[:status]).to eq(404)
      request_to(app, "/styles.css", method: "DELETE")
      expect(request_to(app, "/styles.css", method: "DELETE")[:status]).to eq(404)
    end

    it "serves a tombstoned path again after a PUT recreates it" do
      request_to(app, "/styles.css", method: "DELETE")
      request_to(app, "/styles.css", method: "PUT", body: "reborn")

      expect(request_to(app, "/styles.css")[:status]).to eq(200)
      expect(request_to(app, "/styles.css")[:body]).to eq("reborn")
    end

    it "rejects unsafe paths with 400" do
      expect(request_to(app, "/../secret.txt", method: "PUT", body: "x")[:status])
        .to eq(400)
    end
  end

  describe "read-only packages" do
    let(:app) { build_reactor([readonly_source], @workdir) }

    it "answers 403 with a clear body for every write" do
      post = request_to(app, "/api/v1/data/notes", method: "POST",
                                                   body: JSON.generate("title" => "T"))
      expect(post[:status]).to eq(403)
      expect(json(post)["error"]).to include("read-only")

      put_ro = request_to(app, "/api/v1/data/notes/1", method: "PUT",
                                                       body: JSON.generate("title" => "T"))
      expect(put_ro[:status]).to eq(403)
      expect(request_to(app, "/api/v1/data/notes/1", method: "DELETE")[:status]).to eq(403)
      expect(request_to(app, "/file.txt", method: "PUT", body: "x")[:status]).to eq(403)
      expect(request_to(app, "/index.html", method: "DELETE")[:status]).to eq(403)
    end

    it "still serves reads, including item reads" do
      expect(request_to(app, "/api/v1/data/notes")[:status]).to eq(200)
      expect(json(request_to(app, "/api/v1/data/notes/1"))["title"]).to eq("Read-only note")
      expect(request_to(app, "/index.html")[:status]).to eq(200)
    end
  end

  describe "SQLite datasets" do
    let(:app) do
      source = File.join(@workdir, "sqlite-package")
      FileUtils.cp_r(writable_source, source)
      db = SQLite3::Database.new(File.join(source, "data", "sales.db"))
      db.execute("CREATE TABLE sales (id INTEGER PRIMARY KEY, total REAL);")
      db.execute("INSERT INTO sales (total) VALUES (9.99);")
      db.close
      storage = JSON.parse(File.read(File.join(source, "storage.json")))
      storage["storage"]["dataSets"]["sales"] = { "databaseFile" => "data/sales.db",
                                                  "table" => "sales" }
      File.write(File.join(source, "storage.json"), JSON.generate(storage))
      build_reactor([source], @workdir)
    end

    it "serves reads from the base DB before any write" do
      result = request_to(app, "/api/v1/data/sales")
      expect(result[:status]).to eq(200)
      rows = json(result)["sales"]
      expect(rows.size).to eq(1)
    end

    it "appends, reads, updates, and deletes via the copy-on-write overlay" do
      created = request_to(app, "/api/v1/data/sales", method: "POST",
                                                      body: JSON.generate("total" => 19.99))
      expect(created[:status]).to eq(201)
      expect(created[:headers]["Location"]).to match(%r{/api/v1/data/sales/\d+})

      collection = json(request_to(app, "/api/v1/data/sales"))["sales"]
      expect(collection.size).to eq(2)
      new_id = created[:headers]["Location"].split("/").last

      updated = request_to(app, "/api/v1/data/sales/#{new_id}",
                           method: "PUT",
                           body: JSON.generate("total" => 29.99))
      expect(updated[:status]).to eq(200)
      expect(json(updated)["total"]).to eq(29.99)

      deleted = request_to(app, "/api/v1/data/sales/#{new_id}", method: "DELETE")
      expect(deleted[:status]).to eq(204)
      expect(request_to(app, "/api/v1/data/sales/#{new_id}")[:status]).to eq(404)
    end

    it "keeps the base database immutable on disk" do
      # Touch app to ensure the source directory (and the SQLite DB
      # created inside it) is laid out before we record its size.
      app
      base_path = File.join(@workdir, "sqlite-package", "data", "sales.db")
      base_size = File.size(base_path)
      request_to(app, "/api/v1/data/sales", method: "POST",
                                            body: JSON.generate("total" => 100.0))
      request_to(app, "/api/v1/data/sales", method: "DELETE")

      expect(File.size(base_path)).to eq(base_size)
    end

    it "returns 404 for an unknown item and 409 for a duplicate id on append" do
      expect(request_to(app, "/api/v1/data/sales/9999")[:status]).to eq(404)
      expect(request_to(app, "/api/v1/data/sales/9999", method: "DELETE")[:status]).to eq(404)

      existing_id = json(request_to(app, "/api/v1/data/sales"))["sales"].first["id"]
      dupe = request_to(app, "/api/v1/data/sales", method: "POST",
                                                   body: JSON.generate("id" => existing_id,
                                                                       "total" => 1.0))
      expect(dupe[:status]).to eq(409)
    end
  end

  describe "multi-package combined (one writable, one readOnly)" do
    let(:app) { build_reactor([writable_source, readonly_source], @workdir) }

    it "writes the writable mount at / and rejects the readOnly mount" do
      created = request_to(app, "/api/v1/data/notes", method: "POST",
                                                      body: JSON.generate("title" => "Root write"))
      expect(created[:status]).to eq(201)

      named = request_to(app, "/readonly-package/api/v1/data/notes",
                         method: "POST", body: JSON.generate("title" => "N"))
      expect(named[:status]).to eq(403)

      expect(json(request_to(app, "/readonly-package/api/v1/data/notes")).size).to eq(1)
      expect(json(request_to(app, "/api/v1/data/notes")).size).to eq(3)
    end

    it "writes content per mount independently" do
      expect(request_to(app, "/only-root.txt", method: "PUT", body: "root")[:status])
        .to eq(200)
      expect(request_to(app, "/readonly-package/only-root.txt", method: "PUT",
                                                                body: "ro")[:status]).to eq(403)
    end
  end

  describe "operator --read-only override (issue #27)" do
    let(:app) { build_reactor([writable_source], @workdir, read_only: true) }

    it "rejects dataset writes with 403 even on a writable package" do
      post = request_to(app, "/api/v1/data/notes", method: "POST",
                                                   body: JSON.generate("title" => "T"))
      expect(post[:status]).to eq(403)
      expect(json(post)["error"]).to include("read-only")

      put_ro = request_to(app, "/api/v1/data/notes/1", method: "PUT",
                                                       body: JSON.generate("title" => "T"))
      expect(put_ro[:status]).to eq(403)
      expect(request_to(app, "/api/v1/data/notes/1", method: "DELETE")[:status])
        .to eq(403)
    end

    it "rejects content writes with 403" do
      expect(request_to(app, "/fresh.txt", method: "PUT", body: "x")[:status])
        .to eq(403)
      expect(request_to(app, "/index.html", method: "DELETE")[:status]).to eq(403)
    end

    it "still serves reads" do
      expect(request_to(app, "/api/v1/data/notes")[:status]).to eq(200)
      expect(json(request_to(app, "/api/v1/data/notes/1"))["title"])
        .to eq("First note")
      expect(request_to(app, "/index.html")[:status]).to eq(200)
    end

    it "leaves the workdir overlay empty (no writes recorded)" do
      request_to(app, "/api/v1/data/notes", method: "POST",
                                            body: JSON.generate("title" => "ignored"))
      overlay = File.join(@workdir, "overlays", "writable-package")
      expect(Dir.exist?(overlay)).to be(false)
    end
  end

  describe "per-mount writable: false config (issue #27)" do
    let(:app) do
      entries = [
        Capsium::Reactor::Mount::Entry.new(path: nil, source: writable_source,
                                           store: nil, writable: false)
      ]
      Capsium::Reactor.new(mounts: Capsium::Reactor::Mount.build(entries),
                           workdir: @workdir, do_not_listen: true)
    end

    it "rejects writes on the overridden mount" do
      post = request_to(app, "/api/v1/data/notes", method: "POST",
                                                   body: JSON.generate("title" => "T"))
      expect(post[:status]).to eq(403)
    end
  end

  describe "live server on an ephemeral port" do
    it "round-trips CRUD over HTTP" do
      allow(WEBrick::HTTPServer).to receive(:new).and_call_original
      probe = TCPServer.new("127.0.0.1", 0)
      port = probe.addr[1]
      probe.close
      live = Capsium::Reactor.new(package: writable_source, port: port,
                                  workdir: @workdir)
      thread = Thread.new { live.server.start }

      created = http_request(port, :post, "/api/v1/data/notes",
                             body: JSON.generate("id" => "live", "title" => "Live"))
      expect(created.code).to eq("201")
      expect(URI(created["Location"]).path).to eq("/api/v1/data/notes/live")

      expect(http_request(port, :get, "/api/v1/data/notes/live").code).to eq("200")

      updated = http_request(port, :put, "/api/v1/data/notes/live",
                             body: JSON.generate("id" => "live", "title" => "Live 2"))
      expect(updated.code).to eq("200")

      deleted = http_request(port, :delete, "/api/v1/data/notes/live")
      expect(deleted.code).to eq("204")
      expect(http_request(port, :get, "/api/v1/data/notes/live").code).to eq("404")

      content = http_request(port, :put, "/live.txt", body: "live content")
      expect(content.code).to eq("200")
      expect(http_request(port, :get, "/live.txt").body).to eq("live content")
    ensure
      live&.server&.shutdown
      thread&.join(5)
      live&.cleanup
    end
  end

  def http_request(port, verb, path, body: nil)
    uri = URI("http://127.0.0.1:#{port}#{path}")
    klass = { get: Net::HTTP::Get, post: Net::HTTP::Post,
              put: Net::HTTP::Put, delete: Net::HTTP::Delete }.fetch(verb)
    20.times do
      return Net::HTTP.start(uri.host, uri.port) do |http|
        request = klass.new(uri)
        request.body = body
        request["Content-Type"] = "application/json" if body
        http.request(request)
      end
    rescue SystemCallError
      sleep(0.1)
    end
    raise "server did not come up"
  end
end
