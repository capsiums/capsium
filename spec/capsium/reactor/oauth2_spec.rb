# frozen_string_literal: true

require "spec_helper"
require "json"
require "net/http"
require "timeout"
require "uri"
require "webrick"

RSpec.describe "OAuth2 authentication (05x-authentication)" do
  let(:workdir) { Dir.mktmpdir }
  let(:mock_server) { instance_double(WEBrick::HTTPServer) }

  # A tiny mock OAuth2 provider: /authorize bounces back a code, /token
  # exchanges it (code "admin-code" yields the admin token), /userinfo
  # returns claims for the bearer token. The admin identity carries no
  # userinfo roles; deploy.json assigns them.
  let(:provider) do
    WEBrick::HTTPServer.new(Port: 0, Logger: WEBrick::Log.new(File::NULL),
                            AccessLog: [])
  end
  let(:provider_port) { provider.listeners[0].addr[1] }
  let(:provider_url) { "http://127.0.0.1:#{provider_port}" }

  let(:deploy) do
    { "authentication" => {
      "oauth2" => { "clientSecret" => "top-secret" },
      "sessionSecret" => "hmac-test-secret",
      "roles" => { "admin@example.com" => ["admin"] }
    } }
  end

  before do
    provider.mount_proc("/authorize") do |request, response|
      redirect = URI(request.query["redirect_uri"])
      redirect.query = URI.encode_www_form(
        "code" => "auth-code-123", "state" => request.query["state"]
      )
      response.status = 302
      response["Location"] = redirect.to_s
    end
    provider.mount_proc("/token") do |request, response|
      if request.query["code"] == "broken-code"
        response.status = 500
        next
      end

      admin = request.query["code"] == "admin-code"
      response["Content-Type"] = "application/json"
      response.body = JSON.generate(
        "access_token" => admin ? "admin-token" : "token-abc"
      )
    end
    provider.mount_proc("/userinfo") do |request, response|
      response["Content-Type"] = "application/json"
      case request["Authorization"]
      when "Bearer token-abc"
        response.body = JSON.generate(
          "sub" => "user-42", "email" => "user@example.com",
          "name" => "Test User", "roles" => ["user"]
        )
      when "Bearer admin-token"
        response.body = JSON.generate(
          "sub" => "user-7", "email" => "admin@example.com",
          "name" => "Admin User"
        )
      else
        response.status = 401
      end
    end
    @provider_thread = Thread.new { provider.start }
    Timeout.timeout(5) { sleep 0.01 until provider.listeners.any? }

    allow(WEBrick::HTTPServer).to receive(:new).and_return(mock_server)
    allow(mock_server).to receive(:mount_proc)
    allow(mock_server).to receive(:start)
    allow(mock_server).to receive(:shutdown)
  end

  after do
    provider.shutdown
    @provider_thread.join(5)
    FileUtils.rm_rf(workdir)
  end

  let(:package_path) { write_oauth_package(workdir) }
  let(:package) { Capsium::Package.new(package_path) }
  let(:reactor) do
    Capsium::Reactor.new(package: package, deploy: deploy, do_not_listen: true)
  end

  after { package&.cleanup }

  def write_oauth_package(dir)
    FileUtils.mkdir_p(File.join(dir, "content"))
    FileUtils.mkdir_p(File.join(dir, "data"))
    oauth_package_files.each do |path, content|
      File.write(File.join(dir, path), content)
    end
    dir
  end

  let(:oauth_package_files) do
    {
      "metadata.json" => JSON.generate(
        "name" => "oauth-package", "version" => "0.1.0",
        "description" => "oauth2 test package",
        "guid" => "https://example.com/capsiums/oauth-package",
        "uuid" => "11111111-2222-3333-4444-555555555555"
      ),
      "authentication.json" => JSON.generate(
        "authentication" => {
          "oauth2" => {
            "enabled" => true, "provider" => "mock", "clientId" => "test-client",
            "authorizationUrl" => "#{provider_url}/authorize",
            "tokenUrl" => "#{provider_url}/token",
            "userinfoUrl" => "#{provider_url}/userinfo",
            "redirectPath" => "/auth/callback", "scopes" => %w[openid email]
          }
        }
      ),
      "storage.json" => JSON.generate(
        "storage" => { "dataSets" => { "animals" => { "source" => "data/animals.json" } } }
      ),
      "routes.json" => JSON.generate(
        "routes" => [
          { "path" => "/", "resource" => "content/index.html" },
          { "path" => "/api/v1/data/animals", "dataset" => "animals",
            "accessControl" => { "roles" => ["admin"], "authenticationRequired" => true } }
        ]
      ),
      "content/index.html" => "<html>oauth</html>",
      "data/animals.json" => '[{"name": "lion"}]'
    }
  end

  # Direct handler call with a captured response (reactor spec style).
  def request_to(app, path, headers: {}, query: {})
    request = instance_double(WEBrick::HTTPRequest, path: path, query: query,
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

  def login_redirect
    request_to(reactor, "/auth/login", headers: { "Host" => "reactor.test" })
  end

  # Runs the login redirect against the mock provider and returns the
  # callback query (code + state) a browser would come back with.
  def provider_callback_query(login_location)
    provider_response = Net::HTTP.get_response(URI(login_location))
    expect(provider_response.code).to eq("302")
    callback = URI(provider_response["Location"])
    expect(callback.path).to eq("/auth/callback")
    URI.decode_www_form(callback.query).to_h
  end

  # Completes the flow with the given authorization code (bypassing the
  # provider's /authorize bounce when a specific code is needed).
  def complete_flow(code: nil)
    query = provider_callback_query(login_redirect[:headers]["Location"])
    query["code"] = code if code
    callback = request_to(reactor, "/auth/callback",
                          headers: { "Host" => "reactor.test" }, query: query)
    callback[:headers]["Set-Cookie"]&.split(";")&.first
  end

  it "challenges unauthenticated requests with 401 (no Basic challenge)" do
    result = request_to(reactor, "/")
    expect(result[:status]).to eq(401)
    expect(result[:headers]).not_to have_key("WWW-Authenticate")
  end

  it "mounts the login and callback endpoints" do
    reactor
    expect(mock_server).to have_received(:mount_proc).with("/auth/login")
    expect(mock_server).to have_received(:mount_proc).with("/auth/callback")
  end

  it "redirects /auth/login to the provider with a signed state" do
    result = login_redirect
    expect(result[:status]).to eq(302)
    location = URI(result[:headers]["Location"])
    expect(location.to_s).to start_with("#{provider_url}/authorize?")
    params = URI.decode_www_form(location.query).to_h
    expect(params["response_type"]).to eq("code")
    expect(params["client_id"]).to eq("test-client")
    expect(params["redirect_uri"]).to eq("http://reactor.test/auth/callback")
    expect(params["scope"]).to eq("openid email")
    expect(params["state"]).to match(/\A[0-9a-f]{32}\.[0-9a-f]{64}\z/)
  end

  it "completes the authorization-code flow and serves with the session cookie" do
    cookie = complete_flow
    expect(cookie).to start_with("capsium_session=")

    content = request_to(reactor, "/", headers: { "Cookie" => cookie })
    expect(content[:status]).to eq(200)
    expect(content[:body]).to eq("<html>oauth</html>")
  end

  it "rejects a callback with a tampered state" do
    query = provider_callback_query(login_redirect[:headers]["Location"])
    query["state"] = "#{query['state']}00"

    callback = request_to(reactor, "/auth/callback",
                          headers: { "Host" => "reactor.test" }, query: query)
    expect(callback[:status]).to eq(401)
    expect(callback[:body]).to eq("Invalid OAuth2 state")
  end

  it "returns 502 when the provider's token exchange fails" do
    query = provider_callback_query(login_redirect[:headers]["Location"])
    query["code"] = "broken-code" # the mock /token responds 500
    callback = request_to(reactor, "/auth/callback",
                          headers: { "Host" => "reactor.test" }, query: query)
    expect(callback[:status]).to eq(502)
    expect(callback[:body]).to include("OAuth2 provider error")
  end

  describe "dataset accessControl with OAuth2 identities" do
    it "forbids an identity whose roles do not include admin (403)" do
      cookie = complete_flow # user@example.com, userinfo roles ["user"]
      result = request_to(reactor, "/api/v1/data/animals",
                          headers: { "Cookie" => cookie })
      expect(result[:status]).to eq(403)
    end

    it "serves an identity mapped to admin via deploy.json roles" do
      cookie = complete_flow(code: "admin-code") # admin@example.com
      result = request_to(reactor, "/api/v1/data/animals",
                          headers: { "Cookie" => cookie })
      expect(result[:status]).to eq(200)
      expect(result[:headers]["Content-Type"]).to eq("application/json")
    end
  end
end
