# frozen_string_literal: true

require "base64"

module Capsium
  class Reactor
    # Request authentication and route authorization for the reactor
    # (05x-authentication, ARCHITECTURE.md section 4b).
    #
    # When the package's authentication.json enables basicAuth, every
    # route is challenged (401 + WWW-Authenticate) until valid htpasswd
    # credentials arrive. When oauth2 is enabled, the login and callback
    # endpoints run the authorization-code flow and establish a signed
    # session cookie. Route-level accessControl is enforced after
    # authentication: 401 when unauthenticated, 403 when the identity
    # lacks a required role.
    class Authenticator
      LOGIN_PATH = "/auth/login"

      attr_reader :authentication, :deploy

      def initialize(authentication, deploy:, package_path:, base_url: nil,
                     state_file: nil)
        @authentication = authentication
        @deploy = deploy
        @package_path = package_path
        @base_url = base_url
        @state_file = state_file
        build_oauth2_flow if oauth2_enabled?
      end

      def enabled?
        @authentication.enabled?
      end

      # The paths this authenticator answers itself (OAuth2 login and
      # callback), mounted by the reactor.
      def endpoints
        oauth2_enabled? ? [LOGIN_PATH, @authentication.oauth2.redirect_path] : []
      end

      def endpoint?(path)
        endpoints.include?(path)
      end

      def serve_endpoint(request, response)
        if request.path == LOGIN_PATH
          response.status = 302
          response["Location"] = @oauth2_flow.authorization_url(request)
          response.body = "Redirecting to the identity provider"
        else
          handle_callback(request, response)
        end
      end

      # The identity for a request — from the session cookie or Basic
      # credentials — or nil. An identity always carries "roles"
      # (possibly empty).
      def authenticate(request)
        identity = @session&.identity_from(request)
        identity || authenticate_basic(request)
      end

      # 401, with a Basic challenge when basicAuth is enabled.
      def challenge(response)
        response.status = 401
        response["Content-Type"] = "text/plain"
        response["WWW-Authenticate"] = %(Basic realm="#{realm}") if basic_enabled?
        response.body = "Unauthorized"
      end

      # :ok, :unauthenticated or :forbidden for a route's accessControl
      # ({"roles": [...], "authenticationRequired": bool}).
      def authorize(identity, access_control)
        return :ok unless access_control
        return :unauthenticated if unauthenticated?(identity, access_control)
        return :forbidden unless roles_allowed?(identity, access_control["roles"])

        :ok
      end

      private

      def unauthenticated?(identity, access_control)
        access_control.fetch("authenticationRequired", true) && identity.nil?
      end

      def roles_allowed?(identity, roles)
        return true if roles.nil? || roles.empty?
        return false if identity.nil?

        roles.intersect?(identity["roles"])
      end

      def basic_enabled? = !!@authentication.basic_auth&.enabled?

      def oauth2_enabled? = !!@authentication.oauth2&.enabled?

      def realm = @authentication.basic_auth&.realm || "capsium"

      def authenticate_basic(request)
        return unless basic_enabled?

        credentials = basic_credentials(request["Authorization"])
        return unless credentials

        username, password = credentials
        return unless htpasswd.verify?(username, password)

        { "name" => username, "roles" => Array(@deploy.roles[username]) }
      end

      def basic_credentials(header)
        return unless header&.start_with?("Basic ")

        Base64.decode64(header.delete_prefix("Basic ")).split(":", 2)
      rescue ArgumentError
        nil
      end

      def htpasswd
        @htpasswd ||= Htpasswd.new(htpasswd_path)
      end

      # deploy.json's basicAuth.passwdFile overrides the package's
      # (reactor-side secret storage); the package's passwdFile is
      # package-relative otherwise.
      def htpasswd_path
        @deploy.passwd_file ||
          File.join(@package_path, @authentication.basic_auth.passwd_file.to_s)
      end

      def build_oauth2_flow
        secret = @deploy.client_secret
        if secret.nil? || secret.empty?
          raise Error,
                "oauth2 is enabled but no clientSecret is configured " \
                "(deploy.json or CAPSIUM_DEPLOY; never in the package)"
        end

        @session = Session.new(secret: @deploy.session_secret,
                               state_file: @state_file)
        @oauth2_flow = OAuth2.new(@authentication.oauth2, client_secret: secret,
                                                          session: @session,
                                                          base_url: @base_url)
      end

      def handle_callback(request, response)
        query = request.query
        return respond_invalid_state(response) unless @oauth2_flow.valid_state?(query["state"])

        userinfo = @oauth2_flow.complete(query["code"], request)
        response.status = 302
        response["Location"] = "/"
        response["Set-Cookie"] = @session.cookie_for(identity_from(userinfo))
        response.body = "Authenticated"
      rescue OAuth2::FlowError => e
        response.status = 502
        response["Content-Type"] = "text/plain"
        response.body = "OAuth2 provider error: #{e.message}"
      end

      def respond_invalid_state(response)
        response.status = 401
        response["Content-Type"] = "text/plain"
        response.body = "Invalid OAuth2 state"
      end

      def identity_from(userinfo)
        name = userinfo["email"] || userinfo["sub"] || userinfo["name"]
        {
          "sub" => userinfo["sub"] || userinfo["id"],
          "email" => userinfo["email"],
          "name" => userinfo["name"],
          "roles" => Array(userinfo["roles"]) | Array(@deploy.roles[name])
        }.compact
      end
    end
  end
end
