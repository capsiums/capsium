# frozen_string_literal: true

require "digest"
require "json"
require "time"
require "uri"

module Capsium
  class Reactor
    # Monitoring HTTP API reports for the package this reactor serves
    # (ARCHITECTURE.md section 7): the package-level
    # /api/v1/introspect/* endpoints plus the 07-reactor follow-ons —
    # reactor-level /introspect/* (status, config, metrics) and
    # per-package /package/:id/* (status, metadata, logs).
    class Introspection
      METADATA_PATH = "/api/v1/introspect/metadata"
      ROUTES_PATH = "/api/v1/introspect/routes"
      CONTENT_HASHES_PATH = "/api/v1/introspect/content-hashes"
      CONTENT_VALIDITY_PATH = "/api/v1/introspect/content-validity"
      PATHS = [METADATA_PATH, ROUTES_PATH, CONTENT_HASHES_PATH,
               CONTENT_VALIDITY_PATH].freeze

      STATUS_PATH = "/introspect/status"
      CONFIG_PATH = "/introspect/config"
      METRICS_PATH = "/introspect/metrics"
      REACTOR_PATHS = [STATUS_PATH, CONFIG_PATH, METRICS_PATH].freeze

      # Per-package endpoints: "/package/<name>/status|metadata|logs".
      # PACKAGE_MOUNT is the mount point (WEBrick longest-prefix
      # matching routes all "/package/..." requests to the reactor);
      # the reactor serves one package, so any other name is a 404.
      PACKAGE_MOUNT = "/package"
      PACKAGE_PATH_PATTERN = %r{\A/package/(?<name>[^/]+)/(?<report>status|metadata|logs)\z}
      DEFAULT_LOG_LINES = 100
      MAX_LOG_LINES = 1000

      attr_reader :package

      def initialize(package, reactor: nil)
        @package = package
        @reactor = reactor
      end

      def endpoint?(path)
        PATHS.include?(path) || package_endpoint?(path) ||
          (!@reactor.nil? && REACTOR_PATHS.include?(path))
      end

      # The report body for an endpoint, or nil when the path is not an
      # endpoint or the package name does not match (404).
      def report_for(path, params: {})
        case path
        when METADATA_PATH then metadata_report
        when ROUTES_PATH then routes_report
        when CONTENT_HASHES_PATH then content_hashes_report
        when CONTENT_VALIDITY_PATH then content_validity_report
        when STATUS_PATH then status_report
        when CONFIG_PATH then config_report
        when METRICS_PATH then metrics_report
        else package_report_for(path, params)
        end
      end

      def metadata_report
        metadata = package.metadata
        { packages: [{
          name: metadata.name,
          version: metadata.version,
          author: metadata.author,
          description: metadata.description
        }] }
      end

      def routes_report
        entries = package.routes.config.routes.map do |route|
          { method: route.http_method || "GET", path: route.path }
        end
        { routes: [{ package: package.name, routes: entries }] }
      end

      def content_hashes_report
        { contentHashes: [{ package: package.name, hash: content_hash }] }
      end

      def content_validity_report
        errors = package.verify_integrity
        entry = {
          package: package.name,
          valid: errors.empty?,
          lastChecked: Time.now.utc.iso8601,
          signed: package.signed?,
          encrypted: package.encrypted?
        }
        entry[:signatureValid] = package.verify_signature if package.signed?
        entry[:reason] = errors.map(&:message).join("; ") unless errors.empty?
        { contentValidity: [entry] }
      end

      def status_report = { status: "running", uptime: uptime, packagesLoaded: 1 }

      # Reactor configuration; secrets (deploy.json, registry URL
      # credentials) are never exposed.
      def config_report
        {
          port: @reactor.port,
          storeDir: store_dir,
          cacheControl: @reactor.cache_control,
          authEnabled: @reactor.authenticator.enabled?,
          registry: registry_location
        }
      end

      def metrics_report = @reactor.metrics.snapshot.merge(uptime: uptime)

      private

      def package_endpoint?(path) = !PACKAGE_PATH_PATTERN.match(path).nil?

      def package_report_for(path, params)
        match = PACKAGE_PATH_PATTERN.match(path)
        return nil unless match && match[:name] == package.name

        case match[:report]
        when "status" then package_status_report
        when "metadata" then package_metadata_report
        when "logs" then package_logs_report(params)
        end
      end

      def package_status_report
        {
          package: package.name,
          version: package.metadata.version,
          status: "loaded",
          valid: package.verify_integrity.empty?
        }
      end

      def package_metadata_report
        metadata = package.metadata
        {
          name: metadata.name,
          version: metadata.version,
          description: metadata.description,
          author: metadata.author,
          guid: metadata.guid
        }
      end

      def package_logs_report(params)
        lines = @reactor ? @reactor.log_buffer.lines(log_line_count(params)) : []
        { package: package.name, logs: lines }
      end

      def log_line_count(params)
        Integer(params["lines"] || DEFAULT_LOG_LINES).clamp(1, MAX_LOG_LINES)
      rescue ArgumentError, TypeError
        DEFAULT_LOG_LINES
      end

      def uptime = (Time.now - @reactor.started_at).round

      def store_dir
        store = @reactor.store
        store.is_a?(Package::Store) ? store.dir : store
      end

      def registry_location
        registry = @reactor.registry
        redact(registry.is_a?(Capsium::Registry) ? registry.location : registry)
      end

      # Strips any userinfo (credentials) from a URL reference.
      def redact(ref)
        return ref unless ref.is_a?(String) && ref.match?(%r{\Ahttps?://})

        uri = URI.parse(ref)
        uri.password = nil
        uri.user = nil
        uri.to_s
      rescue URI::InvalidURIError
        ref
      end

      # SHA-256 of the .cap blob when the package was loaded from one.
      # For directory sources there is no blob, so the hash covers a
      # canonical (sorted-key) JSON serialization of the package content
      # checksums — the same data security.json integrityChecks carry.
      def content_hash
        cap_file = package.cap_file_path
        return Digest::SHA256.file(cap_file).hexdigest if cap_file

        checksums = Package::Security.checksums_for(package.path)
        Digest::SHA256.hexdigest(JSON.generate(checksums))
      end
    end
  end
end
