# frozen_string_literal: true

require "webrick"
require "json"
require "listen"
require "capsium/package"

module Capsium
  class Reactor
    DEFAULT_PORT = 8864

    attr_accessor :package, :package_path, :routes, :port, :server,
                  :server_thread

    def initialize(package:, port: DEFAULT_PORT, do_not_listen: false)
      @package = package.is_a?(String) ? Package.new(package) : package
      @package_path = @package.path
      @port = port
      setup_server(do_not_listen)
      @routes = @package.routes
      mount_routes
    end

    def serve
      @server_thread = start_server
      start_listener
    end

    def handle_request(request, response)
      route = @routes.resolve(request.path)
      if route
        target = route.target
        content_path = target.fs_path(@package.manifest)
        if File.exist?(content_path)
          response.status = 200
          response["Content-Type"] = target.mime(@package.manifest)
          response.body = File.read(content_path)
        else
          response.status = 404
          response["Content-Type"] = "text/plain"
          response.body = "Not Found"
        end
      else
        response.status = 404
        response["Content-Type"] = "text/plain"
        response.body = "Not Found"
      end
    end

    private

    def setup_server(do_not_listen)
      server_options = { Port: @port }
      server_options[:DoNotListen] = true if do_not_listen
      @server = WEBrick::HTTPServer.new(server_options)
    end

    def mount_routes
      @routes.config.routes.each do |route|
        path = route.path
        @server.mount_proc(path.to_s) do |req, res|
          handle_request(req, res)
        end
      end
    end

    def start_server
      Thread.new do
        trap("INT") { shutdown_server }
        puts "Starting server on http://localhost:#{@port}"
        @server.start
      end
    end

    def shutdown_server
      puts "\nShutting down server..."
      @server.shutdown
      exit
    end

    def restart_server
      @server.shutdown
      @server_thread&.join
      load_package
      setup_server(false)
      mount_routes
      @server_thread = start_server
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
      @routes = @package.routes
    end
  end
end
