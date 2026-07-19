# frozen_string_literal: true

require "json"

module Capsium
  class Reactor
    # Reactor-side deployment configuration (deploy.json): everything
    # that must NOT ship in the package — OAuth2 client secrets, the
    # session signing secret, role assignments, an alternate htpasswd
    # file, the public base URL. Shape:
    #
    #   {
    #     "baseUrl": "http://localhost:8864",
    #     "authentication": {
    #       "basicAuth": { "passwdFile": "/secure/.htpasswd" },
    #       "oauth2": { "clientSecret": "..." },
    #       "sessionSecret": "...",
    #       "roles": { "alice": ["admin"] }
    #     }
    #   }
    #
    # Loaded from an explicit path, an already-parsed Hash, or the
    # CAPSIUM_DEPLOY environment variable; empty when unconfigured.
    class Deploy
      FILE = "deploy.json"
      ENV_VAR = "CAPSIUM_DEPLOY"

      attr_reader :config

      def self.load(source)
        return new(source) if source.is_a?(Hash)

        path = source || ENV.fetch(ENV_VAR, nil)
        return new({}) if path.nil? || path.to_s.empty?
        raise Error, "deploy configuration not found: #{path}" unless File.file?(path)

        new(JSON.parse(File.read(path)))
      end

      def initialize(config)
        @config = config
      end

      def authentication
        config["authentication"] || {}
      end

      def base_url
        config["baseUrl"]
      end

      def client_secret
        authentication.dig("oauth2", "clientSecret")
      end

      def session_secret
        authentication["sessionSecret"]
      end

      def passwd_file
        authentication.dig("basicAuth", "passwdFile")
      end

      # Role assignments keyed by identity name (basic-auth username,
      # OAuth2 email or subject): {"alice": ["admin", "user"]}.
      def roles
        authentication["roles"] || {}
      end
    end
  end
end
