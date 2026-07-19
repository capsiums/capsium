# frozen_string_literal: true

require "json"
require "net/http"
require "securerandom"
require "uri"

module Capsium
  class Reactor
    # OAuth2 authorization-code flow client (05x-authentication), used by
    # the Authenticator. Talks to the provider over net/http; the client
    # secret never comes from the package. State is a random nonce signed
    # with the session HMAC key (CSRF protection, self-contained).
    class OAuth2
      # The token exchange or userinfo fetch failed at the provider.
      class FlowError < Capsium::Error; end

      GRANT_TYPE = "authorization_code"

      attr_reader :config

      def initialize(config, client_secret:, session:, base_url: nil)
        @config = config
        @client_secret = client_secret
        @session = session
        @base_url = base_url
      end

      # The provider URL the login endpoint redirects the browser to.
      def authorization_url(request)
        params = {
          "response_type" => "code",
          "client_id" => @config.client_id,
          "redirect_uri" => callback_uri(request),
          "state" => generate_state
        }
        params["scope"] = @config.scopes.join(" ") unless @config.scopes.empty?
        "#{@config.authorization_url}?#{URI.encode_www_form(params)}"
      end

      def valid_state?(state)
        nonce, signature = state.to_s.split(".", 2)
        return false if nonce.nil? || nonce.empty? || signature.nil?

        Reactor.secure_compare(@session.sign(nonce), signature)
      end

      # Exchanges the authorization code and fetches the userinfo claims.
      # Returns the raw userinfo hash; raises FlowError on provider
      # errors.
      def complete(code, request)
        userinfo(exchange_code(code, callback_uri(request)))
      end

      def callback_uri(request)
        "#{base_url_for(request)}#{@config.redirect_path}"
      end

      private

      def generate_state
        nonce = SecureRandom.hex(16)
        "#{nonce}.#{@session.sign(nonce)}"
      end

      def base_url_for(request)
        @base_url || "http://#{request['Host']}"
      end

      def exchange_code(code, redirect_uri)
        response = Net::HTTP.post_form(
          URI(@config.token_url),
          "grant_type" => GRANT_TYPE, "code" => code,
          "redirect_uri" => redirect_uri, "client_id" => @config.client_id,
          "client_secret" => @client_secret
        )
        unless response.is_a?(Net::HTTPSuccess)
          raise FlowError, "token exchange failed (HTTP #{response.code})"
        end

        JSON.parse(response.body).fetch("access_token") do
          raise FlowError, "token response without access_token"
        end
      rescue JSON::ParserError
        raise FlowError, "token response was not JSON"
      end

      def userinfo(access_token)
        uri = URI(@config.userinfo_url)
        response = Net::HTTP.start(uri.host, uri.port,
                                   use_ssl: uri.scheme == "https") do |http|
          http.get(uri.request_uri,
                   "authorization" => "Bearer #{access_token}",
                   "accept" => "application/json")
        end
        unless response.is_a?(Net::HTTPSuccess)
          raise FlowError, "userinfo request failed (HTTP #{response.code})"
        end

        JSON.parse(response.body)
      rescue JSON::ParserError
        raise FlowError, "userinfo response was not JSON"
      end
    end
  end
end
