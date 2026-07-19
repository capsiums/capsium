# frozen_string_literal: true

require "spec_helper"
require "digest"
require "json"
require "openssl"
require "time"
require "yaml"

RSpec.describe Capsium::Reactor do
  let(:fixtures_path) { File.expand_path(File.join(__dir__, "..", "fixtures")) }
  let(:port) { Capsium::Reactor::DEFAULT_PORT }
  let(:mock_server) { instance_double(WEBrick::HTTPServer) }
  let(:new_mock_server) { instance_double(WEBrick::HTTPServer) }

  before do
    allow(WEBrick::HTTPServer).to receive(:new).and_return(mock_server,
                                                           new_mock_server)
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
    lambda { |package_name, path|
      File.read(File.join(fixtures_path, package_name, path))
    }
  end

  shared_examples "a reactor" do |package_name, request_path, expected_status,
                                  expected_content_type, expected_body_path|
    let(:package_path) { File.join(fixtures_path, package_name) }
    let(:package) { Capsium::Package.new(package_path) }
    let(:app) { described_class.new(package: package, do_not_listen: true) }
    let(:expected_body) do
      if expected_body_path
        read_fixture_file.call(package_name,
                               expected_body_path)
      end
    end

    it "returns the correct response for #{request_path}" do
      request = instance_double(WEBrick::HTTPRequest, path: request_path)
      response = instance_double(WEBrick::HTTPResponse)
      allow(response).to receive(:[]=)
      allow(response).to receive(:body=)
      allow(response).to receive(:status=)

      app.handle_request(request, response)

      expect(response).to have_received(:[]=).with("Content-Type",
                                                   expected_content_type)
      expect(response).to have_received(:body=).with(expected_body) if expected_body
      expect(response).to have_received(:status=).with(expected_status)
    end
  end

  context "with a bare package" do
    it_behaves_like "a reactor", "bare-package", "/", 200, "text/html",
                    "content/index.html"
    it_behaves_like "a reactor", "bare-package", "/index", 200, "text/html",
                    "content/index.html"
    it_behaves_like "a reactor", "bare-package", "/index.html", 200,
                    "text/html", "content/index.html"
    it_behaves_like "a reactor", "bare-package", "/example.css", 200,
                    "text/css", "content/example.css"
    it_behaves_like "a reactor", "bare-package", "/example.js", 200,
                    "text/javascript", "content/example.js"
    it_behaves_like "a reactor", "bare-package", "/nonexistent", 404,
                    "text/plain", nil
  end

  context "with a data package" do
    it_behaves_like "a reactor", "data-package", "/", 200, "text/html",
                    "content/index.html"
    it_behaves_like "a reactor", "data-package", "/index", 200, "text/html",
                    "content/index.html"
    it_behaves_like "a reactor", "data-package", "/index.html", 200,
                    "text/html", "content/index.html"
    it_behaves_like "a reactor", "data-package", "/example.css", 200,
                    "text/css", "content/example.css"
    it_behaves_like "a reactor", "data-package", "/example.js", 200,
                    "text/javascript", "content/example.js"
    it_behaves_like "a reactor", "data-package", "/nonexistent", 404,
                    "text/plain", nil
  end

  context "with a layered package (ARCHITECTURE.md section 5a)" do
    # updates/ is the topmost layer and wins over base/ and content/.
    it_behaves_like "a reactor", "layered-package", "/shared.css", 200,
                    "text/css", "updates/shared.css"
    it_behaves_like "a reactor", "layered-package", "/extra.js", 200,
                    "text/javascript", "updates/extra.js"
    it_behaves_like "a reactor", "layered-package", "/base-only.txt", 200,
                    "text/plain", "base/base-only.txt"
    it_behaves_like "a reactor", "layered-package", "/local.txt", 200,
                    "text/plain", "content/local.txt"
    # index.html exists in content/ but is tombstoned in updates/.
    it_behaves_like "a reactor", "layered-package", "/index.html", 404,
                    "text/plain", nil
    it_behaves_like "a reactor", "layered-package", "/", 404,
                    "text/plain", nil
  end

  describe "#mount_routes" do
    let(:package_name) { "bare-package" }
    let(:package_path) { File.join(fixtures_path, package_name) }
    let(:package) { Capsium::Package.new(package_path) }
    let(:app) { described_class.new(package: package, do_not_listen: true) }

    it "mounts routes correctly" do
      expect(mock_server).to receive(:mount_proc).at_least(:once)
      app.mount_routes
    end
  end

  describe "#restart_server" do
    let(:package_name) { "bare-package" }
    let(:package_path) { File.join(fixtures_path, package_name) }
    let(:package) { Capsium::Package.new(package_path) }
    let(:app) { described_class.new(package: package, do_not_listen: true) }

    it "restarts the server correctly" do
      expect(mock_server).to receive(:shutdown).at_least(:once)
      expect(new_mock_server).to receive(:start).at_least(:once)
      app.restart_server.join
    end
  end

  describe "#handle_request" do
    let(:package_name) { "bare-package" }
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
        expect(response).to have_received(:[]=).with("Content-Type",
                                                     "text/html")
      end

      it "returns the correct body content" do
        app.handle_request(request, response)
        expect(response).to have_received(:body=).with(read_fixture_file.call(
                                                         "bare-package", "content/index.html"
                                                       ))
      end

      it "returns cache headers for static resources" do
        app.handle_request(request, response)
        expect(response).to have_received(:[]=).with(
          "Cache-Control", "public, max-age=31536000"
        )
      end
    end

    context "when cache control is disabled" do
      let(:app) do
        described_class.new(package: package, cache_control: nil,
                            do_not_listen: true)
      end

      it "does not set a Cache-Control header" do
        app.handle_request(request, response)
        expect(response).not_to have_received(:[]=).with("Cache-Control",
                                                         anything)
      end
    end

    context "when the route does not exist" do
      let(:request) do
        instance_double(WEBrick::HTTPRequest, path: "/nonexistent")
      end

      it "returns a 404 status" do
        app.handle_request(request, response)
        expect(response).to have_received(:status=).with(404)
      end

      it "returns the correct content type" do
        app.handle_request(request, response)
        expect(response).to have_received(:[]=).with("Content-Type",
                                                     "text/plain")
      end

      it "returns the correct body content" do
        app.handle_request(request, response)
        expect(response).to have_received(:body=).with("Not Found")
      end
    end

    context "when the route targets a dataset" do
      let(:package_name) { "data-package" }
      let(:request) do
        instance_double(WEBrick::HTTPRequest, path: "/api/v1/data/animals")
      end
      let(:expected_body) do
        JSON.generate(YAML.load_file(File.join(fixtures_path, package_name,
                                               "data", "animals.yaml")))
      end

      it "returns a 200 status" do
        app.handle_request(request, response)
        expect(response).to have_received(:status=).with(200)
      end

      it "returns a JSON content type" do
        app.handle_request(request, response)
        expect(response).to have_received(:[]=).with("Content-Type",
                                                     "application/json")
      end

      it "returns the dataset serialized as JSON" do
        app.handle_request(request, response)
        expect(response).to have_received(:body=).with(expected_body)
      end
    end
  end

  describe "introspection endpoints (ARCHITECTURE.md section 7)" do
    let(:package_name) { "data-package" }
    let(:package_path) { File.join(fixtures_path, package_name) }
    let(:package) { Capsium::Package.new(package_path) }
    let(:app) { described_class.new(package: package, do_not_listen: true) }

    # Calls the handler directly (rack-free) and captures the response.
    def introspect(app, path, method: "GET")
      request = instance_double(WEBrick::HTTPRequest, path: path,
                                                      request_method: method)
      response = instance_double(WEBrick::HTTPResponse)
      result = { headers: {} }
      allow(response).to receive(:status=) { |value| result[:status] = value }
      allow(response).to receive(:[]=) do |name, value|
        result[:headers][name] = value
      end
      allow(response).to receive(:body=) { |value| result[:body] = value }
      app.handle_request(request, response)
      result
    end

    it "mounts the introspection endpoints on the server" do
      app
      Capsium::Reactor::Introspection::PATHS.each do |path|
        expect(mock_server).to have_received(:mount_proc).with(path)
      end
    end

    describe "GET /api/v1/introspect/metadata" do
      it "returns the package metadata as JSON" do
        result = introspect(app, "/api/v1/introspect/metadata")

        expect(result[:status]).to eq(200)
        expect(result[:headers]["Content-Type"]).to eq("application/json")
        expect(JSON.parse(result[:body])).to eq(
          "packages" => [{
            "name" => "data-package",
            "version" => "0.1.0",
            "author" => "Ribose Inc.",
            "description" => "A package with data"
          }]
        )
      end
    end

    describe "GET /api/v1/introspect/routes" do
      it "returns the package routes as JSON" do
        result = introspect(app, "/api/v1/introspect/routes")

        expect(result[:status]).to eq(200)
        expect(result[:headers]["Content-Type"]).to eq("application/json")
        parsed = JSON.parse(result[:body])
        expect(parsed["routes"].size).to eq(1)
        expect(parsed["routes"].first["package"]).to eq("data-package")
        expect(parsed["routes"].first["routes"]).to include(
          { "method" => "GET", "path" => "/" },
          { "method" => "GET", "path" => "/api/v1/data/animals" }
        )
      end
    end

    describe "GET /api/v1/introspect/content-hashes" do
      it "hashes the canonical content checksums for a directory source" do
        result = introspect(app, "/api/v1/introspect/content-hashes")

        expected = Digest::SHA256.hexdigest(
          JSON.generate(Capsium::Package::Security.checksums_for(package.path))
        )
        expect(result[:status]).to eq(200)
        expect(JSON.parse(result[:body])).to eq(
          "contentHashes" => [{ "package" => "data-package",
                                "hash" => expected }]
        )
      end

      it "hashes the .cap blob for a .cap source" do
        cap_path = File.join(fixtures_path, "data-package-0.1.0.cap")
        cap_package = Capsium::Package.new(cap_path)
        cap_app = described_class.new(package: cap_package,
                                      do_not_listen: true)
        result = introspect(cap_app, "/api/v1/introspect/content-hashes")

        expect(JSON.parse(result[:body])).to eq(
          "contentHashes" => [{
            "package" => "data-package",
            "hash" => Digest::SHA256.file(cap_path).hexdigest
          }]
        )
      ensure
        cap_package.cleanup
      end
    end

    describe "GET /api/v1/introspect/content-validity" do
      it "reports an intact package as valid" do
        result = introspect(app, "/api/v1/introspect/content-validity")

        expect(result[:status]).to eq(200)
        entry = JSON.parse(result[:body]).fetch("contentValidity").first
        expect(entry["package"]).to eq("data-package")
        expect(entry["valid"]).to be(true)
        expect(entry).not_to have_key("reason")
        expect { Time.iso8601(entry["lastChecked"]) }.not_to raise_error
      end

      it "reports tampered content as invalid with a reason" do
        Dir.mktmpdir do |dir|
          tampered = File.join(dir, "data-package")
          FileUtils.cp_r(package_path, tampered)
          tampered_package = Capsium::Package.new(tampered)
          File.write(File.join(tampered, "content", "index.html"),
                     "<html>tampered</html>")
          tampered_app = described_class.new(package: tampered_package,
                                             do_not_listen: true)

          result = introspect(tampered_app,
                              "/api/v1/introspect/content-validity")

          entry = JSON.parse(result[:body]).fetch("contentValidity").first
          expect(entry["valid"]).to be(false)
          expect(entry["reason"]).to include("index.html")
        end
      end

      it "reports signature and encryption status" do
        result = introspect(app, "/api/v1/introspect/content-validity")

        entry = JSON.parse(result[:body]).fetch("contentValidity").first
        expect(entry["signed"]).to be(false)
        expect(entry["encrypted"]).to be(false)
        expect(entry).not_to have_key("signatureValid")
      end

      it "reports a valid signature for a signed package" do
        Dir.mktmpdir do |dir|
          copy = File.join(dir, "bare-package")
          FileUtils.cp_r(File.join(fixtures_path, "bare-package"), copy)
          key_path = File.join(dir, "key.pem")
          File.write(key_path, OpenSSL::PKey::RSA.generate(2048).to_pem)
          Capsium::Package::Signer.sign_package(copy, key_path)
          signed_app = described_class.new(package: Capsium::Package.new(copy),
                                           do_not_listen: true)

          result = introspect(signed_app, "/api/v1/introspect/content-validity")

          entry = JSON.parse(result[:body]).fetch("contentValidity").first
          expect(entry["signed"]).to be(true)
          expect(entry["signatureValid"]).to be(true)
        end
      end

      it "reports a package loaded from an encrypted source as encrypted" do
        Dir.mktmpdir do |dir|
          key = OpenSSL::PKey::RSA.generate(2048)
          public_key_path = File.join(dir, "public.pem")
          private_key_path = File.join(dir, "private.pem")
          File.write(public_key_path, key.public_key.to_pem)
          File.write(private_key_path, key.to_pem)
          encrypted = File.join(dir, "encrypted.cap")
          Capsium::Package::Cipher.new.encrypt(
            File.join(fixtures_path, "bare-package-0.1.0.cap"),
            public_key_path, encrypted
          )
          encrypted_package = Capsium::Package.new(encrypted,
                                                   decryption_key: private_key_path)
          encrypted_app = described_class.new(package: encrypted_package,
                                              do_not_listen: true)

          result = introspect(encrypted_app, "/api/v1/introspect/content-validity")

          entry = JSON.parse(result[:body]).fetch("contentValidity").first
          expect(entry["encrypted"]).to be(true)
        ensure
          encrypted_package&.cleanup
        end
      end
    end

    context "with an unsupported method" do
      it "returns 405 Method Not Allowed" do
        result = introspect(app, "/api/v1/introspect/metadata", method: "POST")

        expect(result[:status]).to eq(405)
        expect(result[:headers]["Content-Type"]).to eq("text/plain")
        expect(result[:body]).to eq("Method Not Allowed")
      end
    end

    context "with an unknown introspection path" do
      it "returns 404 Not Found" do
        result = introspect(app, "/api/v1/introspect/unknown")

        expect(result[:status]).to eq(404)
        expect(result[:headers]["Content-Type"]).to eq("text/plain")
      end
    end
  end
end
