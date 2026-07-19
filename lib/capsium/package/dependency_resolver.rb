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
    # store: circularity checks plus store lookup. Package loads the
    # resolved .cap itself (recursively, with an extended chain).
    class DependencyResolver
      attr_reader :store

      def initialize(store)
        if store.nil?
          raise DependencyError,
                "metadata.dependencies declared but no package store " \
                "configured (set CAPSIUM_STORE or pass store:)"
        end

        @store = store.is_a?(Store) ? store : Store.new(store.to_s)
      end

      # The newest store .cap satisfying the dependency. Raises
      # CircularDependencyError when the GUID is already being resolved
      # up-chain, DependencyNotFoundError when the store has no package
      # for it and UnsatisfiableDependencyError when no stored version
      # satisfies the range.
      def resolve_path(guid, range, chain:)
        if chain.include?(guid)
          raise CircularDependencyError,
                "circular dependency: #{(chain + [guid]).join(' -> ')}"
        end

        @store.find(guid, range)
      end
    end
  end
end
