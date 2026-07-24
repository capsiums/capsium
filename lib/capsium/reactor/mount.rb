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
      # overrides the global package store for this mount, "writable"
      # optionally forces the mount read-only regardless of package
      # metadata (nil preserves the metadata-driven default per spec).
      Entry = Data.define(:path, :source, :store, :writable) do
        def initialize(path:, source:, store: nil, writable: nil)
          super
        end
      end

      attr_reader :path, :package, :overlay

      # Operator override on writability: nil preserves the spec default
      # (writable unless the package declares "readOnly": true); false
      # forces the mount read-only regardless of metadata. Set by the
      # Reactor when --read-only is passed and by per-mount config.
      attr_writer :writable_override

      # Parses a "--mount PATH=SOURCE" command-line value into an Entry.
      def self.parse_spec(spec)
        path, separator, source = spec.to_s.partition(SPEC_SEPARATOR)
        if separator.empty? || path.empty? || source.empty?
          raise Error, "Invalid mount spec #{spec.inspect} (expected PATH=SOURCE)"
        end

        Entry.new(path: path, source: source, store: nil, writable: nil)
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

          writable = parse_writable(entry["writable"], config_file)
          Entry.new(path: entry["path"], source: entry["source"],
                    store: entry["store"], writable: writable)
        end
      rescue JSON::ParserError => e
        raise Error, "Invalid mount config #{config_file}: #{e.message}"
      end

      # Normalizes a JSON "writable" field into a tri-state usable by
      # Mount#writable?: nil preserves the metadata-driven default;
      # false forces the mount read-only at the operator's request.
      # true is rejected — operators may only opt out of writability,
      # not override a package's own readOnly declaration.
      def self.parse_writable(value, config_file)
        case value
        when nil then nil
        when false then false
        when true
          raise Error, "Invalid mount config #{config_file}: \"writable\": " \
                       "true is not allowed (omit the field or set false; " \
                       "packages opt into writability via metadata)"
        else
          raise Error, "Invalid mount config #{config_file}: \"writable\" " \
                       "must be a boolean, got #{value.inspect}"
        end
      end
      private_class_method :parse_writable

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
                       store: package_store, registry: registry,
                       writable: entry.writable)
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

      def initialize(path:, package:, store: nil, registry: nil, workdir: nil,
                     writable: nil)
        @path = self.class.normalize_path(path)
        @store = store
        @registry = registry
        @writable_override = writable
        @package = self.class.load_package(package, store, registry)
        attach_workdir(workdir) if workdir
      end

      # Attaches the reactor workdir: the writable overlay (topmost
      # layer, ARCHITECTURE.md section 5a) lives under it. Reads always
      # resolve through the overlay; writes require #writable?.
      def attach_workdir(workdir)
        @overlay = Overlay.new(root: File.join(workdir, "overlays", @package.name))
      end

      # Writable unless the operator forced read-only (per-mount config
      # or the reactor --read-only flag) AND the package does not declare
      # "readOnly": true. Operator override can only opt OUT of
      # writability — never back in over a package's own readOnly.
      def writable?
        return false if @writable_override == false

        !@overlay.nil? && @package.metadata.read_only != true
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

      # The merged content view; the overlay is always the topmost
      # layer when a workdir is attached (hot-swap: content writes and
      # tombstones resolve on the next request).
      def merged_view
        @merged_view ||= if @overlay
                           @package.merged_view(extra_layers: [@overlay.layer])
                         else
                           @package.merged_view
                         end
      end

      # The dataset as served: base data merged with the overlay's
      # mutation log.
      def dataset_data(dataset)
        @overlay ? @overlay.dataset_data(dataset) : dataset.data
      end

      def data_api = @data_api ||= DataApi.new(self)

      def content_api = @content_api ||= ContentApi.new(self)

      # Whether this mount exposes a GraphQL API (any file-backed
      # dataset; SQLite datasets are skipped).
      def graphql?
        @package.storage.datasets.any? { |dataset| !dataset.config.sqlite? }
      end

      def graphql_api = @graphql_api ||= GraphqlApi.new(self)

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
      # filesystem listener noticed changes. The overlay survives (it
      # lives in the reactor workdir, not in the package).
      def reload
        @merged_view = nil
        @graphql_api = nil
        @package = Package.new(@package.path, store: @store, registry: @registry)
      end
    end
  end
end
