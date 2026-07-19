# frozen_string_literal: true

require "json"

module Capsium
  class Reactor
    # Raised when two mounts claim the same URL prefix, whether given
    # explicitly or derived from package names.
    class MountConflictError < Capsium::Error; end

    # One mounted package: the URL prefix it answers under plus its
    # serving state (routes, merged view; ARCHITECTURE.md section 7).
    # The reactor serves a list of mounts resolved by longest-prefix
    # matching. Default mount points: the first source at "/", each
    # additional source at "/<metadata.name>/".
    class Mount
      ROOT_PATH = "/"
      SPEC_SEPARATOR = "="

      # A mount entry as accepted from the CLI or a JSON config file:
      # "path" may be nil (the default is assigned on build), "source"
      # is a package directory or .cap file, "store" optionally
      # overrides the global package store for this mount.
      Entry = Data.define(:path, :source, :store)

      attr_reader :path, :package

      # Parses a "--mount PATH=SOURCE" command-line value into an Entry.
      def self.parse_spec(spec)
        path, separator, source = spec.to_s.partition(SPEC_SEPARATOR)
        if separator.empty? || path.empty? || source.empty?
          raise Error, "Invalid mount spec #{spec.inspect} (expected PATH=SOURCE)"
        end

        Entry.new(path: path, source: source, store: nil)
      end

      # The mount entries of a JSON config file:
      # {"mounts": [{"path": "/", "source": "dir-or.cap", "store": "..."}]}
      def self.config_entries(config_file)
        doc = JSON.parse(File.read(config_file))
        mounts = doc.is_a?(Hash) ? doc["mounts"] : nil
        unless mounts.is_a?(Array) && mounts.all?(Hash)
          raise Error, "Invalid mount config #{config_file}: expected " \
                       '{"mounts": [{"path": ..., "source": ...}]}'
        end

        mounts.map do |entry|
          unless entry["source"].is_a?(String)
            raise Error, "Invalid mount config #{config_file}: every mount " \
                         "needs a \"source\""
          end

          Entry.new(path: entry["path"], source: entry["source"],
                    store: entry["store"])
        end
      rescue JSON::ParserError => e
        raise Error, "Invalid mount config #{config_file}: #{e.message}"
      end

      # Builds the mounts for a list of entries: loads each package,
      # assigns default paths (first entry "/", each additional
      # "/<metadata.name>/") and rejects duplicate prefixes with a
      # MountConflictError. On failure every package loaded so far is
      # cleaned up again.
      def self.build(entries, store: nil, registry: nil)
        built = []
        entries.each_with_index do |entry, index|
          package_store = entry.store || store
          package = load_package(entry.source, package_store, registry)
          path = entry.path || default_path(index, package)
          built << new(path: path, package: package,
                       store: package_store, registry: registry)
        end
        check_conflicts!(built)
        built
      rescue StandardError
        built.each { |mount| mount.package.cleanup }
        raise
      end

      # Loads a mount source (a package directory, .cap file or an
      # already-built Package) with the given resolution context.
      def self.load_package(source, store, registry)
        return source unless source.is_a?(String)

        Package.new(source, store: store, registry: registry)
      end

      def self.default_path(index, package)
        index.zero? ? ROOT_PATH : "#{ROOT_PATH}#{package.name}"
      end
      private_class_method :default_path

      def self.check_conflicts!(built)
        paths = built.map(&:path)
        duplicates = paths.tally.select { |_path, count| count > 1 }.keys
        return if duplicates.empty?

        raise MountConflictError,
              "mount path conflict: #{duplicates.join(', ')} is mounted twice"
      end
      private_class_method :check_conflicts!

      # Canonical mount prefix: leading "/", no trailing "/" (except the
      # root itself).
      def self.normalize_path(path)
        return ROOT_PATH if path.nil? || path == ROOT_PATH

        normalized = path.start_with?(ROOT_PATH) ? path : "#{ROOT_PATH}#{path}"
        normalized.chomp(ROOT_PATH)
      end

      def initialize(path:, package:, store: nil, registry: nil)
        @path = self.class.normalize_path(path)
        @store = store
        @registry = registry
        @package = self.class.load_package(package, store, registry)
      end

      # Whether this mount answers the given request path: the prefix
      # itself or anything below it. The root mount answers everything.
      def matches?(request_path)
        path == ROOT_PATH || request_path == path ||
          request_path.start_with?("#{path}#{ROOT_PATH}")
      end

      # The package-local path for a request path under this mount
      # ("/" when the request hits the mount prefix itself).
      def inner_path(request_path)
        inner = request_path.delete_prefix(path)
        return ROOT_PATH if inner.empty?
        return inner if inner.start_with?(ROOT_PATH)

        "#{ROOT_PATH}#{inner}"
      end

      def routes = @package.routes

      def merged_view = @package.merged_view

      # The one-line "name version" summary used in reactor logs.
      def summary = "#{@package.name} #{@package.metadata.version}"

      # The WEBrick mount points serving this mount: every serving path
      # for the root mount (unchanged single-package behavior), the
      # prefix itself for a non-root mount (longest-prefix matching
      # routes everything below it to the reactor).
      def server_paths
        return [path] unless path == ROOT_PATH

        routes.config.routes.map(&:serving_path)
      end

      # Reloads the package from its (prepared) path, e.g. after the
      # filesystem listener noticed changes.
      def reload
        @package = Package.new(@package.path, store: @store, registry: @registry)
      end
    end
  end
end
