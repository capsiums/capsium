# frozen_string_literal: true

require "json"
require "listen"
require "tmpdir"
require "webrick"

module Capsium
  class Reactor
    autoload :Authenticator, "capsium/reactor/authenticator"
    autoload :Deploy, "capsium/reactor/deploy"
    autoload :Htpasswd, "capsium/reactor/htpasswd"
    autoload :Introspection, "capsium/reactor/introspection"
    autoload :OAuth2, "capsium/reactor/oauth2"
    autoload :Serving, "capsium/reactor/serving"
    autoload :Session, "capsium/reactor/session"

    include Serving

    DEFAULT_PORT = 8864
    DEFAULT_CACHE_CONTROL = "public, max-age=31536000"

    attr_reader :package, :package_path, :routes, :port, :cache_control,
                :server, :server_thread, :introspection, :authenticator

    def initialize(package:, port: DEFAULT_PORT,
                   cache_control: DEFAULT_CACHE_CONTROL, do_not_listen: false,
                   store: nil, deploy: nil)
      @package = package.is_a?(String) ? Package.new(package, store: store) : package
      @package_path = @package.path
      @store = store
      @port = port
      @cache_control = cache_control
      @deploy_config = Deploy.load(deploy)
      setup_server(do_not_listen)
      load_state
      mount_routes
    end

    def serve
      trap("INT") { shutdown_server }
      @server_thread = start_server
      start_listener
    end

    def handle_request(request, response)
      if @authenticator.endpoint?(request.path)
        @authenticator.serve_endpoint(request, response)
        return
      end

      identity = @authenticator.authenticate(request)
      return @authenticator.challenge(response) if @authenticator.enabled? && identity.nil?
      return serve_introspection(request, response) if @introspection.endpoint?(request.path)

      route = @routes.resolve(request.path)
      return respond_not_found(response) unless route

      case @authenticator.authorize(identity, route.access_control)
      when :unauthenticated then return @authenticator.challenge(response)
      when :forbidden then return respond_forbidden(response)
      end

      serve_route(route, response)
    end

    def mount_routes
      paths = @routes.config.routes.map(&:serving_path) +
              Introspection::PATHS + @authenticator.endpoints
      paths.each do |path|
        @server.mount_proc(path.to_s) { |req, res| handle_request(req, res) }
      end
    end

    def restart_server
      @server.shutdown
      @server_thread&.join
      load_package
      setup_server(false)
      mount_routes
      @server_thread = start_server
    end

    private

    def setup_server(do_not_listen)
      server_options = { Port: @port }
      server_options[:DoNotListen] = true if do_not_listen
      @server = WEBrick::HTTPServer.new(server_options)
    end

    def start_server
      Thread.new do
        puts "Starting server on http://localhost:#{@port}"
        @server.start
      end
    end

    def shutdown_server
      puts "\nShutting down server..."
      @server.shutdown
      exit
    end

    def start_listener
      listener = Listen.to(@package_path) do |_modified, _added, _removed|
        puts "Changes detected, reloading..."
        restart_server
      end

      listener.start
      puts "Listening for changes in #{@package_path}..."
      @server_thread.join
    end

    def load_package
      @package = Package.new(@package_path, store: @store)
      load_state
    end

    def load_state
      @routes = @package.routes
      @merged_view = @package.merged_view
      @introspection = Introspection.new(@package)
      @authenticator = Authenticator.new(
        @package.authentication,
        deploy: @deploy_config,
        package_path: @package.path,
        base_url: @deploy_config.base_url,
        state_file: File.join(Dir.tmpdir, "capsium-#{@package.name}-session-secret")
      )
    end

    def serve_introspection(request, response)
      return respond_method_not_allowed(response) unless request.request_method == "GET"

      response.status = 200
      response["Content-Type"] = "application/json"
      response.body = JSON.generate(@introspection.report_for(request.path))
    end

    def respond_not_found(response) = respond_text(response, 404, "Not Found")

    def respond_forbidden(response) = respond_text(response, 403, "Forbidden")

    def respond_not_implemented(response) = respond_text(response, 501, "Not Implemented")

    def respond_method_not_allowed(response) = respond_text(response, 405, "Method Not Allowed")

    def respond_text(response, status, body)
      response.status = status
      response["Content-Type"] = "text/plain"
      response.body = body
    end
  end
end
