# frozen_string_literal: true

module Capsium
  class Package
    # Composite-package support (ARCHITECTURE.md section 4a), mixed into
    # Package: metadata.dependencies resolution against a package store
    # and load-time validation of dependency resource references.
    module Composition
      private

      # Resolves metadata.dependencies against the package store (the
      # `store` argument, else CAPSIUM_STORE). Each resolved dependency
      # loads recursively with an extended circularity chain; its
      # exported content becomes lower read-only layers of this
      # package's merged view.
      def resolve_dependencies(store, chain)
        declared = @metadata.dependencies
        return [] if declared.empty?

        resolver = DependencyResolver.new(store || Store.default)
        chain += [@metadata.guid]
        declared.map do |guid, range|
          cap_path = resolver.resolve_path(guid, range, chain: chain)
          ResolvedDependency.new(
            guid: guid, range: range, path: cap_path,
            package: Package.new(cap_path, store: resolver.store,
                                           dependency_chain: chain)
          )
        end
      end

      # Every route resource given as a URI ("<dependency-guid>/<path>")
      # must address a resolved dependency and a resource that dependency
      # exports; anything else is a load-time error (section 4a).
      def validate_dependency_references!
        @routes.config.routes.each do |route|
          reference = route.resource
          next unless route.dependency_reference?

          dependency = dependency_for(reference)
          unless dependency
            raise DependencyError,
                  "route #{route.path} references unknown dependency: #{reference}"
          end

          validate_dependency_reference(route, dependency, reference)
        end
      end

      def validate_dependency_reference(route, dependency, reference)
        inner = reference.delete_prefix("#{dependency.guid}/")
        return if dependency.package.merged_view(exported_only: true).resolve(inner)

        if dependency.package.merged_view.resolve(inner)
          raise DependencyVisibilityError,
                "route #{route.path} references a private resource of " \
                "dependency #{dependency.guid}: #{inner}"
        end
        raise DependencyError,
              "route #{route.path} references a resource missing from " \
              "dependency #{dependency.guid}: #{inner}"
      end

      def dependency_for(reference)
        @resolved_dependencies
          .sort_by { |dependency| -dependency.guid.length }
          .find { |dependency| reference.start_with?("#{dependency.guid}/") }
      end

      def dependency_views
        @resolved_dependencies.map do |dependency|
          [dependency.guid, dependency.package.merged_view(exported_only: true)]
        end
      end
    end
  end
end
