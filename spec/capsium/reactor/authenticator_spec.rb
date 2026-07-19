# frozen_string_literal: true

require "spec_helper"
require "webrick"

RSpec.describe Capsium::Reactor::Authenticator do
  let(:fixtures_path) do
    File.expand_path(File.join(__dir__, "..", "..", "fixtures"))
  end
  let(:package_path) { File.join(fixtures_path, "auth-package") }
  let(:package) { Capsium::Package.new(package_path) }
  let(:deploy) do
    { "authentication" => { "roles" => { "alice" => ["admin"] } } }
  end
  let(:mock_server) { instance_double(WEBrick::HTTPServer) }
  let(:reactor) do
    Capsium::Reactor.new(package: package, deploy: deploy, do_not_listen: true)
  end

  before do
    allow(WEBrick::HTTPServer).to receive(:new).and_return(mock_server)
    allow(mock_server).to receive(:mount_proc)
    allow(mock_server).to receive(:start)
    allow(mock_server).to receive(:shutdown)
  end

  # Calls the reactor's handler directly (rack-free) and captures the
  # response, in the style of the reactor introspection specs.
  def request_to(app, path, headers: {})
    request = instance_double(WEBrick::HTTPRequest, path: path,
                                                    request_method: "GET")
    allow(request).to receive(:[]) { |name| headers[name] }
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

  def basic(username, password)
    { "Authorization" => "Basic #{["#{username}:#{password}"].pack('m0')}" }
  end

  describe "basicAuth challenge (05x-authentication)" do
    it "challenges unauthenticated requests with 401 + WWW-Authenticate" do
      result = request_to(reactor, "/")
      expect(result[:status]).to eq(401)
      expect(result[:headers]["WWW-Authenticate"]).to eq('Basic realm="capsium"')
      expect(result[:body]).to eq("Unauthorized")
    end

    it "rejects invalid credentials" do
      result = request_to(reactor, "/", headers: basic("alice", "wrong"))
      expect(result[:status]).to eq(401)
    end

    it "serves valid htpasswd credentials" do
      result = request_to(reactor, "/", headers: basic("alice", "wonderland"))
      expect(result[:status]).to eq(200)
      expect(result[:headers]["Content-Type"]).to eq("text/html")
    end

    it "protects the introspection endpoints when authentication is enabled" do
      expect(request_to(reactor, "/api/v1/introspect/metadata")[:status]).to eq(401)
      result = request_to(reactor, "/api/v1/introspect/metadata",
                          headers: basic("alice", "wonderland"))
      expect(result[:status]).to eq(200)
    end

    it "mounts no OAuth2 endpoints for a basic-only package" do
      expect(reactor.authenticator.endpoints).to eq([])
    end
  end

  describe "dataset accessControl (401 unauthenticated, 403 unauthorized)" do
    it "challenges unauthenticated dataset requests with 401" do
      result = request_to(reactor, "/api/v1/data/animals")
      expect(result[:status]).to eq(401)
    end

    it "serves the dataset to an identity with a required role" do
      result = request_to(reactor, "/api/v1/data/animals",
                          headers: basic("alice", "wonderland"))
      expect(result[:status]).to eq(200)
      expect(result[:headers]["Content-Type"]).to eq("application/json")
    end

    it "forbids an authenticated identity lacking the role with 403" do
      result = request_to(reactor, "/api/v1/data/animals",
                          headers: basic("bob", "builder"))
      expect(result[:status]).to eq(403)
      expect(result[:body]).to eq("Forbidden")
    end
  end

  describe Capsium::Reactor::Session do
    let(:session) { described_class.new(secret: "test-secret") }

    it "round-trips a signed payload and rejects tampering" do
      cookie = session.encode("sub" => "user-1", "roles" => ["admin"])
      expect(session.decode(cookie)).to eq("sub" => "user-1", "roles" => ["admin"])
      expect(session.decode("#{cookie}tampered")).to be_nil
      expect(session.decode("garbage")).to be_nil
    end

    it "builds an HttpOnly session cookie and reads it back from a request" do
      set_cookie = session.cookie_for("sub" => "user-1")
      expect(set_cookie).to start_with("capsium_session=")
      expect(set_cookie).to include("HttpOnly", "SameSite=Lax")

      value = set_cookie.split(";").first.delete_prefix("capsium_session=")
      request = instance_double(WEBrick::HTTPRequest)
      allow(request).to receive(:[]) { |name| name == "Cookie" ? "capsium_session=#{value}" : nil }
      expect(session.identity_from(request)).to eq("sub" => "user-1")
    end

    it "persists a generated secret reactor-side (never in the package)" do
      Dir.mktmpdir do |dir|
        state_file = File.join(dir, "secret")
        first = described_class.new(state_file: state_file)
        second = described_class.new(state_file: state_file)
        expect(first.secret).to eq(second.secret)
        expect(File.stat(state_file).mode & 0o777).to eq(0o600)
      end
    end
  end

  describe Capsium::Reactor::Deploy do
    it "loads from a Hash, a file path and CAPSIUM_DEPLOY" do
      from_hash = described_class.load({ "authentication" => { "sessionSecret" => "s" } })
      expect(from_hash.session_secret).to eq("s")

      Dir.mktmpdir do |dir|
        path = File.join(dir, "deploy.json")
        File.write(path, JSON.generate("baseUrl" => "http://example.test"))
        expect(described_class.load(path).base_url).to eq("http://example.test")

        ENV["CAPSIUM_DEPLOY"] = path
        expect(described_class.load(nil).base_url).to eq("http://example.test")
      ensure
        ENV.delete("CAPSIUM_DEPLOY")
      end
    end

    it "raises for a missing file and defaults to an empty config" do
      expect { described_class.load("/nonexistent/deploy.json") }
        .to raise_error(Capsium::Error, /deploy configuration not found/)
      expect(described_class.load(nil).session_secret).to be_nil
    end
  end
end
