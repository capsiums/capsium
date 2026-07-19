# frozen_string_literal: true

require "json"
require "listen"
require "webrick"

module Capsium
  class Reactor
    autoload :Introspection, "capsium/reactor/introspection"

    DEFAULT_PORT = 8864
    DEFAULT_CACHE_CONTROL = "public, max-age=31536000"

    attr_reader :package, :package_path, :routes, :port, :cache_control,
                :server, :server_thread, :introspection

    def initialize(package:, port: DEFAULT_PORT,
                   cache_control: DEFAULT_CACHE_CONTROL, do_not_listen: false)
      @package = package.is_a?(String) ? Package.new(package) : package
      @package_path = @package.path
      @port = port
      @cache_control = cache_control
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
      return serve_introspection(request, response) if @introspection.endpoint?(request.path)

      route = @routes.resolve(request.path)
      route ? serve_route(route, response) : respond_not_found(response)
    end

    def mount_routes
      paths = @routes.config.routes.map(&:path) + Introspection::PATHS
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
      @package = Package.new(@package_path)
      load_state
    end

    def load_state
      @routes = @package.routes
      @introspection = Introspection.new(@package)
    end

    def serve_introspection(request, response)
      return respond_method_not_allowed(response) unless request.request_method == "GET"

      response.status = 200
      response["Content-Type"] = "application/json"
      response.body = JSON.generate(@introspection.report_for(request.path))
    end

    def serve_route(route, response)
      case route.kind
      when :dataset then serve_dataset(route.dataset, response)
      when :resource then serve_file(route, response)
      else respond_not_implemented(response)
      end
    end

    def serve_file(route, response)
      content_path = route.fs_path(@package.path)
      if content_path && File.exist?(content_path)
        response.status = 200
        response["Content-Type"] = route.mime(@package.manifest) || "application/octet-stream"
        headers_for(route).each { |name, value| response[name] = value }
        response.body = File.read(content_path)
      else
        respond_not_found(response)
      end
    end

    def headers_for(route)
      route.headers || (@cache_control ? { "Cache-Control" => @cache_control } : {})
    end

    def serve_dataset(dataset_name, response)
      dataset = @package.storage.dataset(dataset_name)
      if dataset
        response.status = 200
        response["Content-Type"] = "application/json"
        response.body = JSON.generate(dataset.data)
      else
        respond_not_found(response)
      end
    end

    def respond_not_found(response) = respond_text(response, 404, "Not Found")

    def respond_not_implemented(response) = respond_text(response, 501, "Not Implemented")

    def respond_method_not_allowed(response) = respond_text(response, 405, "Method Not Allowed")

    def respond_text(response, status, body)
      response.status = status
      response["Content-Type"] = "text/plain"
      response.body = body
    end
  end
end
