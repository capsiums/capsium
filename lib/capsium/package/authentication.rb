# frozen_string_literal: true

require "forwardable"

module Capsium
  class Package
    # Loads a package's authentication.json (ARCHITECTURE.md section 4b).
    class Authentication
      extend Forwardable

      attr_reader :path, :config

      def_delegators :@config, :to_json, :to_hash

      def initialize(path)
        @path = path
        @config = File.exist?(path) ? AuthenticationConfig.from_json(File.read(path)) : nil
      end

      def present?
        !@config.nil?
      end

      def basic_auth
        @config&.authentication&.basic_auth
      end

      def oauth2
        @config&.authentication&.oauth2
      end

      # Whether any authentication method is enabled.
      def enabled?
        !!(basic_auth&.enabled? || oauth2&.enabled?)
      end
    end
  end
end
