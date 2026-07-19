# frozen_string_literal: true

module Capsium
  class Package
    # Base error for composite-package dependency resolution
    # (ARCHITECTURE.md section 4a).
    class DependencyError < Capsium::Error; end

    # No package in the store provides the dependency GUID.
    class DependencyNotFoundError < DependencyError; end

    # The store provides the GUID but no version satisfies the range.
    class UnsatisfiableDependencyError < DependencyError; end

    # A dependency cycle was detected while resolving.
    class CircularDependencyError < DependencyError; end

    # A dependent route references a dependency resource that is not
    # exported (private) and therefore not visible to dependents.
    class DependencyVisibilityError < DependencyError; end

    # One resolved dependency: the declared GUID and range, the .cap it
    # resolved to and the loaded package.
    ResolvedDependency = Data.define(:guid, :range, :path, :package) do
      def version
        package.metadata.version
      end
    end

    # Orchestrates metadata.dependencies resolution against a package
    # store: circularity checks plus store lookup, with a registry
    # (Capsium::Registry) as install fallback for store misses.
    # Package loads the resolved .cap itself (recursively, with an
    # extended chain).
    class DependencyResolver
      attr_reader :store, :registry

      def initialize(store, registry: nil)
        if store.nil?
          raise DependencyError,
                "metadata.dependencies declared but no package store " \
                "configured (set CAPSIUM_STORE or pass store:)"
        end

        @store = store.is_a?(Store) ? store : Store.new(store.to_s)
        @registry = if registry.nil? || registry.is_a?(Capsium::Registry)
                      registry
                    else
                      Capsium::Registry.fetch(registry)
                    end
        @registry ||= Capsium::Registry.default
      end

      # The newest store .cap satisfying the dependency. Falls back to
      # installing from the configured registry when the store has no
      # package for the GUID. Raises CircularDependencyError when the
      # GUID is already being resolved up-chain,
      # DependencyNotFoundError when neither the store nor a registry
      # provides it and UnsatisfiableDependencyError when no available
      # version satisfies the range.
      def resolve_path(guid, range, chain:)
        if chain.include?(guid)
          raise CircularDependencyError,
                "circular dependency: #{(chain + [guid]).join(' -> ')}"
        end

        @store.find(guid, range)
      rescue DependencyNotFoundError => e
        resolve_from_registry(guid, range, e)
      end

      private

      # Registry fallback for store misses (fallback chain: store ->
      # registry -> typed error). Installs the newest satisfying version
      # into the store and returns its path; re-raises the store error
      # when no registry is configured.
      def resolve_from_registry(guid, range, store_error)
        raise store_error if @registry.nil?

        @registry.install(guid, range, store: @store)
      rescue Registry::PackageNotFoundError
        raise DependencyNotFoundError,
              "#{store_error.message}; no package #{guid} in registry " \
              "#{@registry.location} either"
      rescue Registry::UnsatisfiableConstraintError => e
        raise UnsatisfiableDependencyError, e.message
      end
    end
  end
end
