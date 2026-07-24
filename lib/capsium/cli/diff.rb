# frozen_string_literal: true

require "digest"
require "json"

module Capsium
  class Cli
    # `capsium diff A B` — compare two packages at the structural level:
    # routes added/removed/modified, manifest resources added/removed/
    # content-changed, datasets added/removed/changed. Output is a
    # structured report; pass --json for machine consumption.
    class Diff
      Result = Data.define(:left, :right, :routes, :resources, :datasets)

      def self.call(path_a, path_b)
        package_a = Capsium::Package.new(path_a)
        package_b = Capsium::Package.new(path_b)
        Result.new(
          left: package_a.path,
          right: package_b.path,
          routes: RoutesDiff.call(package_a, package_b),
          resources: ResourcesDiff.call(package_a, package_b),
          datasets: DatasetsDiff.call(package_a, package_b)
        )
      end

      # Routes: which URL paths the package answers, keyed by path.
      # Diff is keyed by route path because route ordering is not
      # semantically meaningful (longest-prefix match handles precedence).
      class RoutesDiff
        def self.call(left, right)
          by_path_a = routes_by_path(left)
          by_path_b = routes_by_path(right)
          new(added: diff_keys(by_path_b, by_path_a, by_path_b),
              removed: diff_keys(by_path_a, by_path_a, by_path_b),
              changed: changed_entries(by_path_a, by_path_b))
        end

        attr_reader :added, :removed, :changed

        def initialize(added:, removed:, changed:)
          @added = added
          @removed = removed
          @changed = changed
        end

        def empty?
          added.empty? && removed.empty? && changed.empty?
        end

        def to_h
          { added: added, removed: removed, changed: changed }
        end

        class << self
          private

          def routes_by_path(package)
            package.routes.config.routes.to_h do |route|
              [route.path, route_to_h(route)]
            end
          end

          def route_to_h(route)
            entry = { kind: route.kind.to_s }
            entry[:resource] = route.resource if route.resource
            entry[:dataset] = route.dataset if route.dataset
            entry[:method] = route.http_method if route.http_method
            entry[:handler] = route.handler if route.handler
            entry
          end

          def diff_keys(source, by_a, by_b)
            (source.keys - other_keys(source, by_a, by_b)).sort
              .map do |p|
              {
                path: p, route: source[p]
              }
            end
          end

          def other_keys(source, by_a, by_b)
            # The set NOT in `source`: keys that are in the other hash
            # but not in this one. Equivalent to (other - source.keys).
            source.equal?(by_a) ? by_b.keys : by_a.keys
          end

          def changed_entries(by_a, by_b)
            (by_a.keys & by_b.keys).sort.filter_map do |path|
              next nil if by_a[path] == by_b[path]

              { path: path, from: by_a[path], to: by_b[path] }
            end
          end
        end
      end

      # Resources: the content/ files declared in manifest.json.
      # Diff is content-addressed (sha256 of file bytes) so identical
      # files compare equal regardless of mtime/permissions.
      class ResourcesDiff
        def self.call(left, right)
          checksums_a = resource_checksums(left)
          checksums_b = resource_checksums(right)
          new(added: (checksums_b.keys - checksums_a.keys).sort,
              removed: (checksums_a.keys - checksums_b.keys).sort,
              changed: (checksums_a.keys & checksums_b.keys)
                       .reject { |p| checksums_a[p] == checksums_b[p] }.sort)
        end

        attr_reader :added, :removed, :changed

        def initialize(added:, removed:, changed:)
          @added = added
          @removed = removed
          @changed = changed
        end

        def empty?
          added.empty? && removed.empty? && changed.empty?
        end

        def to_h
          { added: added, removed: removed, changed: changed }
        end

        class << self
          private

          def resource_checksums(package)
            package.manifest.resources.keys.to_h do |resource_path|
              [resource_path, sha256_of(package, resource_path)]
            end
          end

          def sha256_of(package, resource_path)
            full = File.join(package.path, resource_path)
            return nil unless File.file?(full)

            Digest::SHA256.file(full).hexdigest
          rescue StandardError
            nil
          end
        end
      end

      # Datasets: declared in storage.json. Diff is content-addressed
      # against each dataset's source file.
      class DatasetsDiff
        def self.call(left, right)
          names_a = dataset_names(left)
          names_b = dataset_names(right)
          new(added: (names_b - names_a).sort,
              removed: (names_a - names_b).sort,
              changed: (names_a & names_b)
                       .reject { |n| dataset_checksum(left, n) == dataset_checksum(right, n) }.sort)
        end

        attr_reader :added, :removed, :changed

        def initialize(added:, removed:, changed:)
          @added = added
          @removed = removed
          @changed = changed
        end

        def empty?
          added.empty? && removed.empty? && changed.empty?
        end

        def to_h
          { added: added, removed: removed, changed: changed }
        end

        class << self
          private

          def dataset_names(package)
            package.storage.datasets.map(&:name)
          end

          def dataset_checksum(package, name)
            dataset = package.storage.dataset(name)
            return nil unless dataset&.config&.source

            sha256_of(package, dataset.config.source)
          end

          def sha256_of(package, relative_path)
            full = File.join(package.path, relative_path)
            return nil unless File.file?(full)

            Digest::SHA256.file(full).hexdigest
          rescue StandardError
            nil
          end
        end
      end

      # Human-readable rendering of a Report. One section per concern;
      # empty sections are omitted.
      class Format
        SECTION_LABELS = { routes: "Routes", resources: "Resources",
                           datasets: "Datasets" }.freeze

        def initialize(report)
          @report = report
        end

        def render
          sections = [render_section(:routes, @report.routes),
                      render_section(:resources, @report.resources),
                      render_section(:datasets, @report.datasets)].compact
          return "(no differences)" if sections.empty?

          sections.join("\n")
        end

        private

        def render_section(name, diff)
          return nil if diff.empty?

          lines = ["#{SECTION_LABELS[name]}:"]
          diff.added.each { |v| lines << "  + #{label_for(v)}" }
          diff.removed.each { |v| lines << "  - #{label_for(v)}" }
          diff.changed.each { |v| lines << "  ~ #{label_for(v)}" }
          lines.join("\n")
        end

        def label_for(value)
          value.is_a?(String) ? value : (value[:path] || value[:name] || value.to_s)
        end
      end
    end
  end
end
