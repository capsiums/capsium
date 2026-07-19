# frozen_string_literal: true

require "json"

module Capsium
  class Package
    # The merged (overlay) view of a package's content, per ARCHITECTURE.md
    # section 5a. Shared by Package (validation) and Reactor (serving).
    #
    # The content/ tree is always the implicit bottom layer; layers from
    # storage.layers stack on top of it, bottom -> top in declaration
    # order. Resolution scans from the TOP down and the first hit wins.
    # Deletions are recorded as tombstones: a `.capsium-tombstones` JSON
    # file in a writable layer listing content/-relative paths; a
    # tombstoned path resolves to nil even when a lower layer (including a
    # dependency's content) holds the file, while a file reappearing in a
    # layer ABOVE the tombstone is served again.
    #
    # With `exported_only: true` (the view a dependent package gets):
    # layers whose visibility is "private" are hidden entirely, and a path
    # resolves only when the manifest lists the resource as "exported".
    class MergedView
      # A single read layer: an absolute root directory mirroring the
      # content/ tree, plus its parsed tombstone set.
      Layer = Data.define(:root, :visibility, :tombstones) do
        def file?(content_relative_path)
          File.file?(absolute(content_relative_path))
        end

        def absolute(content_relative_path)
          File.join(root, content_relative_path)
        end
      end

      TOMBSTONE_FILE = ".capsium-tombstones"
      CONTENT_PREFIX = "#{Package::CONTENT_DIR}/".freeze

      attr_reader :package_path, :layers, :dependency_views

      def initialize(package_path, storage:, manifest:, dependency_views: [],
                     exported_only: false)
        @package_path = package_path
        @storage = storage
        @manifest = manifest
        @exported_only = exported_only
        @dependency_views = dependency_views
        @layers = build_layers
      end

      # The absolute filesystem path serving a package-relative content
      # path ("content/app.js"), or nil when no layer provides it or it is
      # tombstoned. Non-content paths never resolve through the view.
      def resolve(relative_path)
        content_relative = content_relative(relative_path)
        return unless content_relative
        return if content_relative == TOMBSTONE_FILE

        result = resolve_own(content_relative)
        return if result == :tombstoned
        return result if result

        resolve_dependencies(relative_path)
      end

      private

      # The serving path from the package's own layers, :tombstoned when
      # a tombstone at or above the first hit suppresses it (tombstones
      # also suppress the lower dependency layers), or nil when no own
      # layer provides the path.
      def resolve_own(content_relative)
        tombstoned = false
        @layers.reverse_each do |layer|
          tombstoned ||= layer.tombstones.include?(content_relative)
          next unless layer.file?(content_relative)
          return :tombstoned if tombstoned

          return layer.absolute(content_relative)
        end
        tombstoned ? :tombstoned : nil
      end

      def resolve_dependencies(relative_path)
        @dependency_views.each do |view|
          found = view.resolve(relative_path)
          return found if found
        end
        nil
      end

      # Own layers, bottom -> top: the implicit content/ layer plus the
      # configured storage.layers. Private layers are dropped when the view
      # is exported-only (hidden from dependents, section 5a).
      def build_layers
        configs = [nil] + @storage.config.layers
        configs = configs.reject { |config| config&.private? } if @exported_only
        configs.filter_map { |config| build_layer(config) }
      end

      def build_layer(config)
        root = config ? File.join(@package_path, config.path) : content_root
        Layer.new(root: root,
                  visibility: config&.visibility || "exported",
                  tombstones: load_tombstones(root))
      end

      def content_root
        File.join(@package_path, Package::CONTENT_DIR)
      end

      def load_tombstones(root)
        tombstone_path = File.join(root, TOMBSTONE_FILE)
        return Set.new unless File.file?(tombstone_path)

        entries = JSON.parse(File.read(tombstone_path))
        unless entries.is_a?(Array) && entries.all?(String)
          raise Error, "Malformed #{TOMBSTONE_FILE} (expected a JSON array " \
                       "of paths): #{tombstone_path}"
        end

        Set.new(entries)
      rescue JSON::ParserError => e
        raise Error, "Malformed #{TOMBSTONE_FILE}: #{tombstone_path}: #{e.message}"
      end

      def content_relative(relative_path)
        return unless relative_path.is_a?(String)
        return unless relative_path.start_with?(CONTENT_PREFIX)

        content_relative = relative_path.delete_prefix(CONTENT_PREFIX)
        return if @exported_only && !exported?(relative_path)

        content_relative
      end

      def exported?(relative_path)
        resource = @manifest.lookup(relative_path)
        resource&.visibility == "exported"
      end
    end
  end
end
