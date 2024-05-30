# frozen_string_literal: true

# lib/capsium/reactor.rb
require "webrick"
require "json"
require "listen"
require "capsium/package"

module Capsium
  class Reactor
    DEFAULT_PORT = 8864
    attr_accessor :package, :package_path, :routes, :port, :server, :server_thread

    def initialize(package, port = DEFAULT_PORT)
      @package = package
      @package_path = package.path
      @port = port
      @server = WEBrick::HTTPServer.new(Port: @port)
      load_routes
      mount_routes
    end

    def serve
      @server_thread = start_server
      start_listener
    end

    private

    def load_routes
      @routes = @package.routes.routes
    end

    def mount_routes
      @routes.each do |route, target|
        puts "mounting route: #{route} => #{target}"
        @server.mount_proc(route.to_s) do |_req, res|
          res.body = File.read(File.join(@package_path, target))
          res.content_type = mime_type(target)
        end
      end
    end

    def start_server
      @server_thread = Thread.new do
        trap("INT") do
          puts "\nShutting down server..."
          @server.shutdown
          exit
        end

        puts "Starting server on http://localhost:#{@port}"
        @server.start
      end
    end

    def restart_server
      @server.shutdown
      # @server_thread.kill
      load_package
      @server = WEBrick::HTTPServer.new(Port: @port)
      mount_routes
      start_server
    end

    def start_listener
      listener = Listen.to(@package_path) do |_modified, _added, _removed|
        puts "Changes detected, reloading..."
        restart_server
      end

      listener.start
      puts "Listening for changes in #{@package_path}..."

      # Wait for the server thread to finish
      @server_thread.join
    end

    def mime_type(path)
      case File.extname(path)
      when ".html"
        "text/html"
      when ".css"
        "text/css"
      when ".js"
        "application/javascript"
      else
        "text/plain"
      end
    end
  end
end
