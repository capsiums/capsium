# frozen_string_literal: true

require "json"
require "listen"
require "webrick"

module Capsium
  class Reactor
    DEFAULT_PORT = 8864

    attr_reader :package, :package_path, :routes, :port, :server,
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
      trap("INT") { shutdown_server }
      @server_thread = start_server
      start_listener
    end

    def handle_request(request, response)
      route = @routes.resolve(request.path)
      if route
        serve_target(route.target, response)
      else
        respond_not_found(response)
      end
    end

    def mount_routes
      @routes.config.routes.each do |route|
        @server.mount_proc(route.path.to_s) do |req, res|
          handle_request(req, res)
        end
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
      @routes = @package.routes
    end

    def serve_target(target, response)
      if target.dataset
        serve_dataset(target.dataset, response)
      else
        serve_file(target, response)
      end
    end

    def serve_file(target, response)
      content_path = target.fs_path(@package.manifest)
      if content_path && File.exist?(content_path)
        response.status = 200
        response["Content-Type"] = target.mime(@package.manifest)
        response.body = File.read(content_path)
      else
        respond_not_found(response)
      end
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

    def respond_not_found(response)
      response.status = 404
      response["Content-Type"] = "text/plain"
      response.body = "Not Found"
    end
  end
end
