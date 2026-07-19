# frozen_string_literal: true

require "json"
require "lutaml/model"

module Capsium
  class Package
    # The "basicAuth" object of authentication.json (ARCHITECTURE.md
    # section 4b): Apache-style Basic authentication verified against an
    # htpasswd file. "passwdFile" is a package-relative path (password
    # hashes, not plaintext secrets, so it may ship in the package);
    # deploy.json may override it with a reactor-side file.
    class BasicAuthConfig < Lutaml::Model::Serializable
      attribute :enabled, :boolean, default: false
      attribute :passwd_file, :string
      attribute :realm, :string, default: "capsium"

      json do
        map :enabled, to: :enabled
        map "passwdFile", to: :passwd_file
        map :realm, to: :realm
      end

      def enabled?
        !!enabled
      end
    end

    # The "oauth2" object of authentication.json: an OAuth2
    # authorization-code flow. The client secret is NEVER read from the
    # package — it comes from deploy.json or reactor configuration.
    class OAuth2Config < Lutaml::Model::Serializable
      attribute :enabled, :boolean, default: false
      attribute :provider, :string
      attribute :client_id, :string
      attribute :authorization_url, :string
      attribute :token_url, :string
      attribute :userinfo_url, :string
      attribute :redirect_path, :string, default: "/auth/callback"
      attribute :scopes, :string, collection: true, default: []

      json do
        map :enabled, to: :enabled
        map :provider, to: :provider
        map "clientId", to: :client_id
        map "authorizationUrl", to: :authorization_url
        map "tokenUrl", to: :token_url
        map "userinfoUrl", to: :userinfo_url
        map "redirectPath", to: :redirect_path
        map :scopes, to: :scopes
      end

      def enabled?
        !!enabled
      end
    end

    # The "authentication" object of authentication.json.
    class AuthenticationData < Lutaml::Model::Serializable
      attribute :basic_auth, BasicAuthConfig
      attribute :oauth2, OAuth2Config

      json do
        map "basicAuth", to: :basic_auth
        map :oauth2, to: :oauth2
      end
    end

    # Canonical authentication.json model (ARCHITECTURE.md section 4b).
    class AuthenticationConfig < Lutaml::Model::Serializable
      attribute :authentication, AuthenticationData

      json do
        map :authentication, to: :authentication
      end
    end
  end
end
