# frozen_string_literal: true

# spec/capsium/packager_spec.rb
require "spec_helper"
require "capsium/package"
require "capsium/packager"
require "capsium/protector"

RSpec.describe Capsium::Packager do
  let(:package_path) { "spec/fixtures/sample_package" }
  let(:package) { Capsium::Package.new(package_path, metadata) }
  let(:packager) { Capsium::Packager.new(package) }

  let(:metadata) do
    {
      name: "sample_package",
      version: "0.1.0",
      dependencies: {}
    }
  end

  before do
    FileUtils.mkdir_p(package_path)
    File.write(File.join(package_path, "file1.txt"), "This is a test file.")
    File.write(File.join(package_path, "file2.txt"), "This is another test file.")
  end

  after do
    FileUtils.rm_rf(package_path)
  end

  xdescribe "#compress_html" do
    it "compresses HTML files" do
      packager.compress_html
      content = File.read("/tmp/test_package/content/example.html")
      expect(content).to eq("<html><body>Hello</body></html>")
    end
  end

  xdescribe "#minify_css" do
    it "minifies CSS files" do
      packager.minify_css
      content = File.read("/tmp/test_package/content/example.css")
      expect(content).to eq("body{color:red}")
    end
  end

  xdescribe "#minify_js" do
    it "minifies JS files" do
      packager.minify_js
      content = File.read("/tmp/test_package/content/example.js")
      expect(content).to eq("function test(){return true;}")
    end
  end

  xcontext "encrypted package" do
    let(:metadata) do
      {
        name: "sample_package",
        version: "0.1.0",
        dependencies: {},
        compression: {
          algorithm: "zip",
          level: "best"
        },
        signature: {
          algorithm: "RSA-SHA256",
          keyLength: 2048,
          certificateType: "X.509",
          signatureFile: "signature.json"
        },
        encryption: {
          algorithm: "AES-256-CBC",
          keyManagement: "secure"
        }
      }
    end

    let(:package) { Capsium::Package.new(package_path, metadata) }
    let(:packager) { Capsium::Packager.new(package) }

    before do
      FileUtils.mkdir_p(package_path)
      File.write(File.join(package_path, "file1.txt"), "This is a test file.")
      File.write(File.join(package_path, "file2.txt"), "This is another test file.")
    end

    after do
      FileUtils.rm_rf(package_path)
    end

    describe "#package_files" do
      it "creates metadata, compresses, encrypts, and signs the package" do
        expect do
          packager.package_files
        end.to change { File.exist?(File.join(package_path, "metadata.json")) }.from(false).to(true)
                                                                               .and change {
                                                                                      File.exist?(File.join(
                                                                                                    package_path, "manifest.json"
                                                                                                  ))
                                                                                    }.from(false).to(true)
                                                                                                 .and change {
                                                                                                        File.exist?(File.join(
                                                                                                                      package_path, "package.enc"
                                                                                                                    ))
                                                                                                      }.from(false).to(true)
                                                                                                                   .and change {
                                                                                                                          File.exist?(File.join(
                                                                                                                                        package_path, "signature.json"
                                                                                                                                      ))
                                                                                                                        }.from(false).to(true)
                                                                                                                                     .and change {
                                                                                                                                            File.exist?(File.join(
                                                                                                                                                          package_path, "public_key.pem"
                                                                                                                                                        ))
                                                                                                                                          }.from(false).to(true)
      end
    end

    describe "#verify_signature" do
      it "verifies the digital signature of the package" do
        packager.package_files
        protector = Capsium::Protector.new(package, metadata[:encryption], metadata[:digitalSignature])
        expect(protector.verify_signature).to be true
      end
    end
  end
end
