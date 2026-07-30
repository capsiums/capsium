# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "webrick"

# Handler routes (CC 62001 §05x-routing "HTTP API") are accepted by the
# Ruby reactor's package model but NOT executed by it (the reactor does
# not claim the handler-routes conformance class). Per the spec, the
# reactor MUST answer every handler route with 501 Not Implemented
# regardless of the request method — POST/PUT/DELETE on a handler route
# is still "not implemented", not "method not allowed".
RSpec.describe "Reactor handler-route responses (501 for every method)" do
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

  # Builds a minimal in-memory package with handler routes. The reactor
  # never loads the handler module — it returns 501 before execution.
  # Security.json is omitted (the package is for serving-route dispatch
  # only, not integrity verification). The tmpdir lives for the whole
  # example so the reactor can read files on demand during the request.
  around do |example|
    Dir.mktmpdir do |dir|
      @workdir = dir
      example.run
    end
  end

  def build_reactor
    work = File.join(@workdir, "pkg")
    FileUtils.mkdir_p(File.join(work, "content"))
    write_metadata(work)
    write_index_html(work)
    write_routes(work)
    package = Capsium::Package.new(work)
    mount = Capsium::Reactor::Mount.new(path: "/", package: package)
    Capsium::Reactor.new(mounts: [mount], do_not_listen: true)
  end

  def write_metadata(work)
    File.write(
      File.join(work, "metadata.json"),
      JSON.generate(
        "name" => "handler-routes-spec",
        "version" => "0.1.0",
        "guid" => "https://github.com/capsiums/handler-routes-spec",
        "uuid" => "123e4567-e89b-12d3-a456-426614174099",
        "author" => "RSpec",
        "license" => "MIT"
      )
    )
  end

  def write_index_html(work)
    File.write(File.join(work, "content/index.html"),
               "<!DOCTYPE html><html><body>index</body></html>")
  end

  def write_routes(work)
    routes = {
      "index" => "content/index.html",
      "routes" => [
        { "path" => "/", "resource" => "content/index.html" },
        { "path" => "/api/v1/handler/echo",
          "method" => "GET", "handler" => "handlers/echo.js" },
        { "path" => "/api/v1/handler/post",
          "method" => "POST", "handler" => "handlers/post.js" }
      ]
    }
    File.write(File.join(work, "routes.json"), JSON.generate(routes))
  end

  def request_to(app, path, method: "GET", body: nil)
    request = instance_double(WEBrick::HTTPRequest, path: path,
                                                    request_method: method,
                                                    body: body)
    allow(request).to receive(:[]).and_return(nil)
    allow(request).to receive(:query).and_return({})
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

  let(:app) { build_reactor }

  it "returns 501 for a GET handler route (handler-routes not claimed)" do
    result = request_to(app, "/api/v1/handler/echo")
    expect(result[:status]).to eq(501)
  end

  it "returns 501 for a POST handler route (not 405 — execution not implemented)" do
    result = request_to(app, "/api/v1/handler/post", method: "POST",
                                                     body: JSON.generate("hello"))
    expect(result[:status]).to eq(501)
  end

  it "returns 501 for a DELETE handler route (handler-routes is method-agnostic)" do
    result = request_to(app, "/api/v1/handler/echo", method: "DELETE")
    expect(result[:status]).to eq(501)
  end

  it "still serves a static GET route alongside the handler routes" do
    result = request_to(app, "/")
    expect(result[:status]).to eq(200)
    expect(result[:headers]["Content-Type"]).to eq("text/html")
  end

  it "still returns 405 for a non-GET method on a STATIC route" do
    result = request_to(app, "/", method: "POST")
    expect(result[:status]).to eq(405)
  end

  it "still returns 404 for an unknown path" do
    result = request_to(app, "/does-not-exist")
    expect(result[:status]).to eq(404)
  end
end
