# frozen_string_literal: true

require "digest"
require "json"
require "time"

module Capsium
  class Reactor
    # Monitoring HTTP API reports for the package this reactor serves
    # (ARCHITECTURE.md section 7). Each report wraps its single entry in
    # the list shape all reactors converge on.
    class Introspection
      METADATA_PATH = "/api/v1/introspect/metadata"
      ROUTES_PATH = "/api/v1/introspect/routes"
      CONTENT_HASHES_PATH = "/api/v1/introspect/content-hashes"
      CONTENT_VALIDITY_PATH = "/api/v1/introspect/content-validity"
      PATHS = [METADATA_PATH, ROUTES_PATH, CONTENT_HASHES_PATH,
               CONTENT_VALIDITY_PATH].freeze

      attr_reader :package

      def initialize(package)
        @package = package
      end

      def endpoint?(path)
        PATHS.include?(path)
      end

      # The report body for an introspection endpoint, or nil when the
      # path is not an introspection endpoint.
      def report_for(path)
        case path
        when METADATA_PATH then metadata_report
        when ROUTES_PATH then routes_report
        when CONTENT_HASHES_PATH then content_hashes_report
        when CONTENT_VALIDITY_PATH then content_validity_report
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

      private

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
