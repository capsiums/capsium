# frozen_string_literal: true

require "spec_helper"
require "capsium/reactor"

RSpec.describe Capsium::Reactor do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "fixtures")) }
  let(:port) { Capsium::Reactor::DEFAULT_PORT }
  let(:mock_server) { instance_double(WEBrick::HTTPServer) }
  let(:new_mock_server) { instance_double(WEBrick::HTTPServer) }

  before do
    allow(WEBrick::HTTPServer).to receive(:new).and_return(mock_server, new_mock_server)
    allow(mock_server).to receive(:mount_proc)
    allow(mock_server).to receive(:start)
    allow(mock_server).to receive(:shutdown)
    allow(new_mock_server).to receive(:mount_proc)
    allow(new_mock_server).to receive(:start)
    allow(new_mock_server).to receive(:shutdown)
  end

  after do
    # Ensure the thread is stopped after each test
    Thread.list.each { |thread| thread.kill if thread != Thread.current }
  end

  let(:read_fixture_file) do
    ->(package_name, path) { File.read(File.join(fixtures_path, package_name, path)) }
  end

  shared_examples "a reactor" do |package_name, request_path, expected_status, expected_content_type, expected_body_path|
    let(:package_path) { File.join(fixtures_path, package_name) }
    let(:package) { Capsium::Package.new(package_path) }
    let(:app) { described_class.new(package: package, do_not_listen: true) }
    let(:expected_body) { expected_body_path ? read_fixture_file.call(package_name, expected_body_path) : nil }

    it "returns the correct response for #{request_path}" do
      request = instance_double(WEBrick::HTTPRequest, path: request_path)
      response = instance_double(WEBrick::HTTPResponse)
      allow(response).to receive(:[]=)
      allow(response).to receive(:body=)
      allow(response).to receive(:status=)

      app.handle_request(request, response)

      expect(response).to have_received(:[]=).with("Content-Type", expected_content_type)
      expect(response).to have_received(:body=).with(expected_body) if expected_body
      expect(response).to have_received(:status=).with(expected_status)
    end
  end

  context "with a bare package" do
    it_behaves_like "a reactor", "bare_package", "/", 200, "text/html", "content/index.html"
    it_behaves_like "a reactor", "bare_package", "/index", 200, "text/html", "content/index.html"
    it_behaves_like "a reactor", "bare_package", "/index.html", 200, "text/html", "content/index.html"
    it_behaves_like "a reactor", "bare_package", "/example.css", 200, "text/css", "content/example.css"
    it_behaves_like "a reactor", "bare_package", "/example.js", 200, "application/javascript", "content/example.js"
    it_behaves_like "a reactor", "bare_package", "/nonexistent", 404, "text/plain", nil
  end

  context "with a data package" do
    it_behaves_like "a reactor", "data_package", "/", 200, "text/html", "content/index.html"
    it_behaves_like "a reactor", "data_package", "/index", 200, "text/html", "content/index.html"
    it_behaves_like "a reactor", "data_package", "/index.html", 200, "text/html", "content/index.html"
    it_behaves_like "a reactor", "data_package", "/example.css", 200, "text/css", "content/example.css"
    it_behaves_like "a reactor", "data_package", "/example.js", 200, "application/javascript", "content/example.js"
    it_behaves_like "a reactor", "data_package", "/nonexistent", 404, "text/plain", nil
  end

  describe "#mount_routes" do
    let(:package_name) { "bare_package" }
    let(:package_path) { File.join(fixtures_path, package_name) }
    let(:package) { Capsium::Package.new(package_path) }
    let(:app) { described_class.new(package: package, do_not_listen: true) }

    it "mounts routes correctly" do
      expect(mock_server).to receive(:mount_proc).at_least(:once)
      app.send(:mount_routes)
    end
  end

  describe "#restart_server" do
    let(:package_name) { "bare_package" }
    let(:package_path) { File.join(fixtures_path, package_name) }
    let(:package) { Capsium::Package.new(package_path) }
    let(:app) { described_class.new(package: package, do_not_listen: true) }

    it "restarts the server correctly" do
      expect(mock_server).to receive(:shutdown).at_least(:once)
      expect(new_mock_server).to receive(:start).at_least(:once)
      app.send(:restart_server)
    end
  end

  describe "#handle_request" do
    let(:package_name) { "bare_package" }
    let(:package_path) { File.join(fixtures_path, package_name) }
    let(:package) { Capsium::Package.new(package_path) }
    let(:app) { described_class.new(package: package, do_not_listen: true) }
    let(:request) { instance_double(WEBrick::HTTPRequest, path: "/") }
    let(:response) { instance_double(WEBrick::HTTPResponse) }

    before do
      allow(response).to receive(:[]=)
      allow(response).to receive(:body=)
      allow(response).to receive(:status=)
    end

    context "when the route exists" do
      it "returns the correct status" do
        app.handle_request(request, response)
        expect(response).to have_received(:status=).with(200)
      end

      it "returns the correct content type" do
        app.handle_request(request, response)
        expect(response).to have_received(:[]=).with("Content-Type", "text/html")
      end

      it "returns the correct body content" do
        app.handle_request(request, response)
        expect(response).to have_received(:body=).with(read_fixture_file.call("bare_package", "content/index.html"))
      end
    end

    context "when the route does not exist" do
      let(:request) { instance_double(WEBrick::HTTPRequest, path: "/nonexistent") }

      it "returns a 404 status" do
        app.handle_request(request, response)
        expect(response).to have_received(:status=).with(404)
      end

      it "returns the correct content type" do
        app.handle_request(request, response)
        expect(response).to have_received(:[]=).with("Content-Type", "text/plain")
      end

      it "returns the correct body content" do
        app.handle_request(request, response)
        expect(response).to have_received(:body=).with("Not Found")
      end
    end
  end
end
