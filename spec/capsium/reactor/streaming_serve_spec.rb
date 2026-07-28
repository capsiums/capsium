# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "webrick"
require "zip"

RSpec.describe "Reactor streaming serve (read directly from the .cap zip)" do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "..", "fixtures")) }
  let(:cap_source) { File.join(fixtures_path, "data-package-0.1.0.cap") }
  let(:directory_source) { File.join(fixtures_path, "data-package") }
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

  def build_streaming_reactor(source)
    entries = [Capsium::Reactor::Mount::Entry.new(path: nil, source: source,
                                                  store: nil)]
    mounts = Capsium::Reactor::Mount.build(entries, streaming: true)
    Capsium::Reactor.new(mounts: mounts, do_not_listen: true, streaming: true)
  end

  def request_to(app, path, method: "GET")
    request = instance_double(WEBrick::HTTPRequest, path: path,
                                                    request_method: method,
                                                    body: nil)
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

  describe "streaming extraction (config files only)" do
    it "exposes the .cap path as zip_source_path" do
      app = build_streaming_reactor(cap_source)
      expect(app.package.zip_source_path.to_s).to eq(cap_source)
      app.cleanup
    end

    it "does not extract content/ files into the package tempdir" do
      app = build_streaming_reactor(cap_source)
      extracted_content = File.join(app.package.path, "content")
      # The content/ directory may exist (mkdir during package load), but
      # it must hold no extracted files in streaming mode — content is
      # read directly from the .cap zip on each request.
      files = Dir.glob(File.join(extracted_content, "**", "*")).select { |f| File.file?(f) }
      expect(files).to be_empty
      app.cleanup
    end

    it "does extract config files into the package tempdir" do
      app = build_streaming_reactor(cap_source)
      expect(File.file?(File.join(app.package.path, "metadata.json"))).to be(true)
      expect(File.file?(File.join(app.package.path, "manifest.json"))).to be(true)
      expect(File.file?(File.join(app.package.path, "routes.json"))).to be(true)
      app.cleanup
    end

    it "does extract structured data/ files into the package tempdir" do
      app = build_streaming_reactor(cap_source)
      expect(File.file?(File.join(app.package.path, "data/animals.yaml"))).to be(true)
      app.cleanup
    end

    it "forces the mount read-only (writable? returns false)" do
      app = build_streaming_reactor(cap_source)
      root_mount = app.mounts.first
      expect(root_mount.writable?).to be(false)
      app.cleanup
    end
  end

  describe "serving content from the zip" do
    it "serves a static HTML route from the .cap without extraction" do
      app = build_streaming_reactor(cap_source)
      expected = Zip::File.open(cap_source) do |zip|
        zip.find_entry("content/index.html").get_input_stream.read
      end

      result = request_to(app, "/index.html")
      expect(result[:status]).to eq(200)
      expect(result[:headers]["Content-Type"]).to eq("text/html")
      expect(result[:body]).to eq(expected)
      app.cleanup
    end

    it "serves a CSS asset from the .cap" do
      app = build_streaming_reactor(cap_source)
      expected = Zip::File.open(cap_source) do |zip|
        zip.find_entry("content/example.css").get_input_stream.read
      end

      result = request_to(app, "/example.css")
      expect(result[:status]).to eq(200)
      expect(result[:headers]["Content-Type"]).to eq("text/css")
      expect(result[:body]).to eq(expected)
      app.cleanup
    end

    it "serves a JS asset from the .cap" do
      app = build_streaming_reactor(cap_source)
      result = request_to(app, "/example.js")
      expect(result[:status]).to eq(200)
      expect(result[:headers]["Content-Type"]).to eq("text/javascript")
      app.cleanup
    end

    it "serves the root index route" do
      app = build_streaming_reactor(cap_source)
      result = request_to(app, "/")
      expect(result[:status]).to eq(200)
      expect(result[:headers]["Content-Type"]).to eq("text/html")
      app.cleanup
    end

    it "returns 404 for an unknown route" do
      app = build_streaming_reactor(cap_source)
      result = request_to(app, "/does-not-exist")
      expect(result[:status]).to eq(404)
      app.cleanup
    end

    it "still serves datasets (datasets use the prepared package, not the zip)" do
      app = build_streaming_reactor(cap_source)
      result = request_to(app, "/api/v1/data/animals")
      expect(result[:status]).to eq(200)
      expect(result[:headers]["Content-Type"]).to eq("application/json")
      expect(JSON.parse(result[:body])["animals"]).to be_an(Array)
      app.cleanup
    end

    it "rejects writes (POST/PUT/DELETE) on datasets in streaming mode" do
      app = build_streaming_reactor(cap_source)
      post = request_to(app, "/api/v1/data/animals", method: "POST")
      expect(post[:status]).to be_between(400, 405).or eq(405)
      expect([405, 403, 404]).to include(post[:status])
      app.cleanup
    end
  end

  describe "parity with non-streaming mode" do
    it "serves identical content from streaming and non-streaming mounts" do
      streaming_app = build_streaming_reactor(cap_source)

      directory_entries = [Capsium::Reactor::Mount::Entry.new(path: nil,
                                                              source: directory_source,
                                                              store: nil)]
      non_streaming_mounts = Capsium::Reactor::Mount.build(directory_entries)
      non_streaming_app = Capsium::Reactor.new(mounts: non_streaming_mounts,
                                               do_not_listen: true)

      streaming_html = request_to(streaming_app, "/index.html")[:body]
      non_streaming_html = request_to(non_streaming_app, "/index.html")[:body]
      expect(streaming_html).to eq(non_streaming_html)

      streaming_css = request_to(streaming_app, "/example.css")[:body]
      non_streaming_css = request_to(non_streaming_app, "/example.css")[:body]
      expect(streaming_css).to eq(non_streaming_css)

      streaming_app.cleanup
      non_streaming_app.cleanup
    end
  end
end
