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
    autoload :Metrics, "capsium/reactor/metrics"
    autoload :Mount, "capsium/reactor/mount"
    autoload :MountConflictError, "capsium/reactor/mount"
    autoload :OAuth2, "capsium/reactor/oauth2"
    autoload :Responses, "capsium/reactor/responses"
    autoload :Serving, "capsium/reactor/serving"
    autoload :Session, "capsium/reactor/session"

    include Responses
    include Serving

    DEFAULT_PORT = 8864
    DEFAULT_CACHE_CONTROL = "public, max-age=31536000"

    attr_reader :package, :package_path, :routes, :port, :cache_control,
                :server, :server_thread, :introspection, :authenticator,
                :store, :registry, :started_at, :metrics, :log_buffer,
                :mounts

    # Serves one or more packages: either a single `package` (directory,
    # .cap file or Package, mounted at "/") or a list of `mounts`
    # (Reactor::Mount) resolved by longest-prefix matching.
    def initialize(package: nil, mounts: nil, port: DEFAULT_PORT,
                   cache_control: DEFAULT_CACHE_CONTROL, do_not_listen: false,
                   store: nil, deploy: nil, registry: nil)
      @store = store
      @registry = registry
      @mounts = mounts || [Mount.new(path: Mount::ROOT_PATH, package: package,
                                     store: store, registry: registry)]
      @port = port
      @cache_control = cache_control
      @started_at = Time.now
      @metrics = Metrics.new
      @log_buffer = Capsium::LogBuffer.new
      @deploy_config = Deploy.load(deploy)
      setup_server(do_not_listen)
      load_state
      mount_routes
      @log_buffer.add("reactor started: " \
                      "#{@mounts.map(&:summary).join(', ')} on port #{@port}")
    end

    def serve
      trap("INT") { shutdown_server }
      @server_thread = start_server
      start_listener
    end

    # Entry point for every mounted path: dispatches the request, then
    # records it in the request metrics and the log buffer.
    def handle_request(request, response)
      dispatch_request(request, response)
    ensure
      record_request(request, response)
    end

    def mount_routes
      paths = Introspection::PATHS + Introspection::REACTOR_PATHS +
              @authenticator.endpoints
      paths.concat(@mounts.flat_map(&:server_paths))
      paths.each do |path|
        @server.mount_proc(path.to_s) { |req, res| handle_request(req, res) }
      end
      # WEBrick longest-prefix matching: catches every "/package/...".
      @server.mount_proc(Introspection::PACKAGE_MOUNT) do |req, res|
        handle_request(req, res)
      end
    end

    def restart_server
      @server.shutdown
      @server_thread&.join
      load_packages
      setup_server(false)
      mount_routes
      @server_thread = start_server
    end

    # Cleans up every mounted package (Package#cleanup for all).
    def cleanup
      @mounts.each { |mount| mount.package.cleanup }
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

    def load_packages
      @mounts.each do |mount|
        @log_buffer.add("package reloaded: #{mount.reload.name}")
      end
      load_state
    end

    def load_state
      root = root_mount
      @package = root.package
      @package_path = @package.path
      @routes = root.routes
      @merged_view = root.merged_view
      @introspection = Introspection.new(@mounts.map(&:package), reactor: self)
      @authenticator = Authenticator.new(
        @package.authentication,
        deploy: @deploy_config,
        package_path: @package.path,
        base_url: @deploy_config.base_url,
        state_file: File.join(Dir.tmpdir, "capsium-#{@package.name}-session-secret")
      )
    end

    # The mount answering a request path: longest matching prefix wins.
    def resolve_mount(path)
      mounts_by_length.find { |mount| mount.matches?(path) }
    end

    def mounts_by_length
      @mounts_by_length ||= @mounts.sort_by { |mount| -mount.path.length }
    end

    # The root ("/") mount, or the first mount when nothing is mounted
    # at the root: its package drives the single-package readers
    # (package, routes, merged_view), authentication and the
    # reactor-level introspection.
    def root_mount
      @mounts.find { |mount| mount.path == Mount::ROOT_PATH } || @mounts.first
    end

    def dispatch_request(request, response)
      if @authenticator.endpoint?(request.path)
        @authenticator.serve_endpoint(request, response)
        return
      end

      identity = @authenticator.authenticate(request)
      return @authenticator.challenge(response) if @authenticator.enabled? && identity.nil?
      return serve_introspection(request, response) if @introspection.endpoint?(request.path)

      mount = resolve_mount(request.path)
      return respond_not_found(response) unless mount

      serve_mounted_request(mount, identity, request, response)
    end

    # One request metric and one log line per served request.
    def record_request(request, response)
      status = response.status
      return if status.nil?

      @metrics.record(status)
      @log_buffer.add("#{request.request_method} #{request.path} -> #{status}")
    end

    def serve_introspection(request, response)
      return respond_method_not_allowed(response) unless request.request_method == "GET"

      report = @introspection.report_for(request.path, params: request.query)
      return respond_not_found(response) if report.nil?

      respond_json(response, 200, report)
    end
  end
end
