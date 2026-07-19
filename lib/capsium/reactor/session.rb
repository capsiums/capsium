# frozen_string_literal: true

require "base64"
require "json"
require "openssl"
require "securerandom"

module Capsium
  class Reactor
    # HMAC-SHA256 signed session cookies (05x-authentication: "Session
    # via signed cookie"). The cookie value is
    # "base64url(JSON payload).hmac hex" — signed, not encrypted, so it
    # carries only the identity claims. The signing secret comes from
    # deploy.json (sessionSecret) or is generated and persisted
    # reactor-side (never in the package).
    class Session
      COOKIE_NAME = "capsium_session"
      SECRET_BYTES = 32

      def self.hmac(secret, data)
        OpenSSL::HMAC.hexdigest("SHA256", secret, data)
      end

      attr_reader :secret

      def initialize(secret: nil, state_file: nil)
        @secret = secret || self.class.load_or_generate_secret(state_file)
      end

      # HMAC-SHA256 of data with the session secret (hex).
      def sign(data)
        self.class.hmac(@secret, data)
      end

      # The persisted reactor-side secret: loaded from state_file when
      # present, generated and written (mode 0600) otherwise.
      def self.load_or_generate_secret(state_file)
        raise Error, "session secret or state_file is required" unless state_file

        return File.read(state_file).strip if File.file?(state_file)

        secret = SecureRandom.hex(SECRET_BYTES)
        File.write(state_file, secret, perm: 0o600)
        secret
      end

      def encode(payload)
        data = Base64.urlsafe_encode64(JSON.generate(payload), padding: false)
        "#{data}.#{self.class.hmac(@secret, data)}"
      end

      # The verified payload, or nil when the cookie is missing or the
      # signature does not match.
      def decode(cookie_value)
        data, signature = cookie_value.to_s.split(".", 2)
        return if data.nil? || signature.nil?

        expected = self.class.hmac(@secret, data)
        return unless Reactor.secure_compare(expected, signature)

        JSON.parse(Base64.urlsafe_decode64(data))
      rescue JSON::ParserError, ArgumentError
        nil
      end

      # The identity for a request's Cookie header, or nil.
      def identity_from(request)
        cookie = request["Cookie"].to_s.split(/;\s*/).find do |part|
          part.start_with?("#{COOKIE_NAME}=")
        end
        return unless cookie

        decode(cookie.delete_prefix("#{COOKIE_NAME}="))
      end

      # A Set-Cookie value establishing the identity session.
      def cookie_for(identity)
        "#{COOKIE_NAME}=#{encode(identity)}; Path=/; HttpOnly; SameSite=Lax"
      end
    end
  end
end
