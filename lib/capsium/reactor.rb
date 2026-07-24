# frozen_string_literal: true

require "fileutils"
require "json"
require "listen"
require "tmpdir"
require "webrick"

# WEBrick's ProcHandler only dispatches do_GET/do_POST/do_PUT; the
# writable-package API (REST CRUD, content writes) also needs DELETE
# and PATCH. AbstractServlet#service looks the do_<METHOD> up per
# request, so aliasing the missing verbs routes them to the same proc.
# rubocop:disable Style/OneClassPerFile
module WEBrick
  module HTTPServlet
    class ProcHandler < AbstractServlet
      alias do_DELETE do_GET # rubocop:disable Naming/MethodName
      alias do_PATCH do_GET # rubocop:disable Naming/MethodName
    end
  end
end

module Capsium
  class Reactor
    autoload :Authenticator, "capsium/reactor/authenticator"
    autoload :ContentApi, "capsium/reactor/content_api"
    autoload :DataApi, "capsium/reactor/data_api"
    autoload :Deploy, "capsium/reactor/deploy"
    autoload :Endpoints, "capsium/reactor/endpoints"
    autoload :GraphqlApi, "capsium/reactor/graphql_api"
    autoload :GraphqlSchema, "capsium/reactor/graphql_schema"
    autoload :Htpasswd, "capsium/reactor/htpasswd"
    autoload :Introspection, "capsium/reactor/introspection"
    autoload :Metrics, "capsium/reactor/metrics"
    autoload :Mount, "capsium/reactor/mount"
    autoload :MountConflictError, "capsium/reactor/mount"
    autoload :OAuth2, "capsium/reactor/oauth2"
    autoload :Overlay, "capsium/reactor/overlay"
    autoload :PackageSaver, "capsium/reactor/package_saver"
    autoload :Responses, "capsium/reactor/responses"
    autoload :Serving, "capsium/reactor/serving"
    autoload :Session, "capsium/reactor/session"

    include Responses
    include Endpoints
    include Serving

    DEFAULT_PORT = 8864
    DEFAULT_CACHE_CONTROL = "public, max-age=31536000"
    PACKAGE_SAVE_PATTERN = %r{\A/package/(?<name>[^/]+)/save\z}

    attr_reader :package, :package_path, :routes, :port, :cache_control,
                :server, :server_thread, :introspection, :authenticator,
                :store, :registry, :started_at, :metrics, :log_buffer,
                :mounts, :workdir

    # Serves one or more packages: either a single `package` (directory,
    # .cap file or Package, mounted at "/") or a list of `mounts`
    # (Reactor::Mount) resolved by longest-prefix matching. `workdir`
    # holds the writable overlays (ARCHITECTURE.md section 5a) and
    # saved packages; it defaults to a temporary directory the reactor
    # removes on cleanup. `read_only: true` forces every mount
    # read-only regardless of package metadata (the operator override
    # documented in issue #27).
    def initialize(package: nil, mounts: nil, port: DEFAULT_PORT,
                   cache_control: DEFAULT_CACHE_CONTROL, do_not_listen: false,
                   store: nil, deploy: nil, registry: nil, workdir: nil,
                   read_only: false)
      @store = store
      @registry = registry
      @workdir = workdir || Dir.mktmpdir("capsium-reactor-")
      @own_workdir = workdir.nil?
      @mounts = mounts || [Mount.new(path: Mount::ROOT_PATH, package: package,
                                     store: store, registry: registry)]
      apply_read_only if read_only
      @mounts.each { |mount| mount.attach_workdir(@workdir) }
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

    # Cleans up every mounted package (Package#cleanup for all) and the
    # workdir when the reactor created it.
    def cleanup
      @mounts.each { |mount| mount.package.cleanup }
      FileUtils.remove_entry(@workdir) if @own_workdir && File.directory?(@workdir)
    end

    private

    # Applies the global --read-only override: every mount becomes
    # read-only regardless of its package metadata or per-mount config.
    def apply_read_only
      @mounts.each { |mount| mount.writable_override = false }
    end

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

    def dispatch_request(request, response)
      if @authenticator.endpoint?(request.path)
        @authenticator.serve_endpoint(request, response)
        return
      end

      identity = @authenticator.authenticate(request)
      return @authenticator.challenge(response) if @authenticator.enabled? && identity.nil?
      return serve_introspection(request, response) if @introspection.endpoint?(request.path)
      return serve_package_save(request, response) if PACKAGE_SAVE_PATTERN.match?(request.path)

      mount = resolve_mount(request.path)
      return respond_not_found(response) unless mount

      serve_mounted_request(mount, identity, request, response)
    end
  end
end

# rubocop:enable Style/OneClassPerFile
