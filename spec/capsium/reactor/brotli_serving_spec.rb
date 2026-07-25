# frozen_string_literal: true

require "spec_helper"
require "brotli"
require "fileutils"
require "json"
require "tmpdir"
require "webrick"

RSpec.describe "Reactor serves brotli sidecars when Accept-Encoding: br" do
  let(:fixtures_path) { File.expand_path("fixtures", File.join(__dir__, "..", "..")) }
  let(:source_path) { File.join(fixtures_path, "bare-package") }
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
      @package_dir = File.join(@workdir, "pkg")
      FileUtils.cp_r(source_path, @package_dir)
      @package = Capsium::Package.new(@package_dir)
      # Brotli.generate extends the manifest with .br entries; the
      # package's existing security.json was built from the original
      # manifest, so regenerate it so integrity verification passes.
      Capsium::Package::Brotli.generate(@package)
      Capsium::Package::Security.generate(@package_dir).save_to_file
      example.run
    end
  end

  def build_reactor
    entries = [Capsium::Reactor::Mount::Entry.new(path: nil, source: @package_dir,
                                                  store: nil)]
    Capsium::Reactor.new(mounts: Capsium::Reactor::Mount.build(entries),
                         workdir: @workdir, do_not_listen: true)
  end

  def request_to(app, path, headers: {})
    request = instance_double(WEBrick::HTTPRequest, path: path,
                                                    request_method: "GET")
    allow(request).to receive(:[]) do |name|
      headers[name]
    end
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

  it "serves the .br sidecar when the client accepts br" do
    result = request_to(app, "/", headers: { "Accept-Encoding" => "br" })
    expect(result[:status]).to eq(200)
    expect(result[:headers]["Content-Encoding"]).to eq("br")
    expect(result[:headers]["Vary"]).to include("Accept-Encoding")

    original = File.read(File.join(@package_dir, "content", "index.html"))
    expect(Brotli.inflate(result[:body])).to eq(original)
  end

  it "serves the original file when the client does not accept br" do
    result = request_to(app, "/", headers: {})
    expect(result[:status]).to eq(200)
    expect(result[:headers]["Content-Encoding"]).to be_nil

    original = File.read(File.join(@package_dir, "content", "index.html"))
    expect(result[:body]).to eq(original)
  end

  it "serves the original when no sidecar exists" do
    # example.js's .br sidecar is generated; remove both the sidecar
    # and its manifest entry so integrity verification stays clean,
    # then request the file. The reactor should fall back to the
    # original (no Content-Encoding).
    File.delete(File.join(@package_dir, "content", "example.js.br"))
    @package.manifest.config.resources.delete("content/example.js.br")
    @package.manifest.save_to_file
    Capsium::Package::Security.generate(@package_dir).save_to_file
    @package = Capsium::Package.new(@package_dir)
    app = build_reactor
    result = request_to(app, "/example.js", headers: { "Accept-Encoding" => "br" })
    expect(result[:headers]["Content-Encoding"]).to be_nil
  end
end
