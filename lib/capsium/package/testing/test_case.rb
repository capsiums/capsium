# frozen_string_literal: true

module Capsium
  class Package
    module Testing
      # Base class for one test of the Capsium testing YAML DSL
      # (05x-testing). Subclasses implement a test kind and register
      # themselves under their DSL type name (open/closed registry).
      class TestCase
        # The outcome of running one test.
        Result = Data.define(:name, :ok, :messages) do
          def ok? = ok
        end

        # Raised for invalid test definitions (unknown type,
        # missing/unknown attributes, non-hash entries).
        class DefinitionError < Capsium::Error; end

        attr_reader :name

        def initialize(name:)
          @name = name
        end

        # Runs the test against the context and returns a Result.
        def run(context)
          raise NotImplementedError
        end

        def self.register(type, klass)
          types[type] = klass
        end

        def self.types
          @types ||= {}
        end

        # Builds a test case from a YAML definition hash (string keys).
        def self.build(definition)
          unless definition.is_a?(Hash)
            raise DefinitionError, "test definition is not a mapping: #{definition.inspect}"
          end

          type = definition["type"] ||
                 raise(DefinitionError, "test #{definition['name'].inspect} has no type")
          klass = types[type] || raise(DefinitionError, "unknown test type: #{type}")
          klass.from_h(definition)
        rescue ArgumentError => e
          raise DefinitionError, "invalid #{type} test #{definition['name'].inspect}: #{e.message}"
        end

        def self.from_h(definition)
          attributes = definition.transform_keys(&:to_sym)
          attributes.delete(:type)
          new(**attributes)
        end
      end
    end
  end
end
