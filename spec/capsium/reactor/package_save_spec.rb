# frozen_string_literal: true

require "spec_helper"
require "digest"
require "json"
require "stringio"
require "tmpdir"
require "webrick"

RSpec.describe "Reactor save composite (POST /package/<name>/save)" do
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

  def build_reactor(sources)
    entries = sources.map do |source|
      Capsium::Reactor::Mount::Entry.new(path: nil, source: source, store: nil)
    end
    Capsium::Reactor.new(mounts: Capsium::Reactor::Mount.build(entries),
                         workdir: @workdir, do_not_listen: true)
  end

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

  def quietly
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end

  let(:app) { build_reactor([writable_source]) }

  def mutate!
    request_to(app, "/api/v1/data/notes", method: "POST",
                                          body: JSON.generate("id" => "saved", "title" => "Saved"))
    request_to(app, "/api/v1/data/notes/2", method: "DELETE")
    request_to(app, "/new-page.txt", method: "PUT", body: "new page body")
    request_to(app, "/styles.css", method: "PUT", body: "body { color: blue; }")
  end

  it "folds base plus overlay into a new versioned .cap that validates" do
    mutate!
    result = quietly { request_to(app, "/package/writable-package/save", method: "POST") }

    expect(result[:status]).to eq(200)
    body = JSON.parse(result[:body])
    expect(body["name"]).to eq("writable-package")
    expect(body["version"]).to eq("0.1.1")
    expect(body["path"]).to eq(File.join(@workdir, "saved", "writable-package-0.1.1.cap"))
    expect(File).to exist(body["path"])
    expect(body["sha256"]).to eq(Digest::SHA256.file(body["path"]).hexdigest)

    results = Capsium::Package::Validator.new(body["path"]).run
    expect(results).to all(be_ok), -> { results.flat_map(&:messages).join("; ") }
  end

  it "folds content writes, tombstones and dataset mutations into the .cap" do
    mutate!
    request_to(app, "/index.html", method: "DELETE")
    saved = JSON.parse(
      quietly { request_to(app, "/package/writable-package/save", method: "POST") }[:body]
    )

    Capsium::Packager.new.with_unpacked_cap(saved["path"]) do |dir|
      expect(File.read(File.join(dir, "content", "new-page.txt"))).to eq("new page body")
      expect(File.read(File.join(dir, "content", "styles.css"))).to include("blue")
      expect(File).not_to exist(File.join(dir, "content", "index.html"))

      notes = JSON.parse(File.read(File.join(dir, "data", "notes.json")))
      expect(notes.map { |item| item["id"] }).to eq(%w[1 saved])

      metadata = JSON.parse(File.read(File.join(dir, "metadata.json")))
      expect(metadata["version"]).to eq("0.1.1")

      routes = JSON.parse(File.read(File.join(dir, "routes.json")))["routes"]
      expect(routes.map { |route| route["path"] }).to include("/new-page.txt")
    end
  end

  it "returns 403 for a read-only package" do
    app = build_reactor([readonly_source])
    result = request_to(app, "/package/readonly-package/save", method: "POST")

    expect(result[:status]).to eq(403)
    expect(JSON.parse(result[:body])["error"]).to include("read-only")
  end

  it "returns 404 for an unknown package name and 405 for non-POST" do
    expect(request_to(app, "/package/nope/save", method: "POST")[:status]).to eq(404)
    expect(request_to(app, "/package/writable-package/save")[:status]).to eq(405)
  end
end
