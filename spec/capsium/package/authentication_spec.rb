# frozen_string_literal: true

require "spec_helper"

RSpec.describe Capsium::Package::Authentication do
  let(:fixtures_path) do
    File.expand_path(File.join(__dir__, "..", "..", "fixtures"))
  end

  context "with a basicAuth package (ARCHITECTURE.md section 4b)" do
    let(:package) { Capsium::Package.new(File.join(fixtures_path, "auth-package")) }
    let(:authentication) { package.authentication }

    it "parses the basicAuth configuration" do
      expect(authentication).to be_present
      expect(authentication).to be_enabled
      expect(authentication.basic_auth).to be_enabled
      expect(authentication.basic_auth.passwd_file).to eq("auth/.htpasswd")
      expect(authentication.basic_auth.realm).to eq("capsium")
      expect(authentication.oauth2).to be_nil
    end

    it "round-trips to JSON" do
      expect(JSON.parse(authentication.to_json)).to eq(
        "authentication" => {
          "basicAuth" => {
            "enabled" => true,
            "passwdFile" => "auth/.htpasswd",
            "realm" => "capsium"
          }
        }
      )
    end
  end

  context "with a package without authentication.json" do
    let(:package) { Capsium::Package.new(File.join(fixtures_path, "bare-package")) }

    it "is absent and disabled" do
      expect(package.authentication).not_to be_present
      expect(package.authentication).not_to be_enabled
      expect(package.authentication.basic_auth).to be_nil
      expect(package.authentication.oauth2).to be_nil
    end
  end
end
