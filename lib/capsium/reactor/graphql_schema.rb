# frozen_string_literal: true

require "graphql"

module Capsium
  class Reactor
    # Builds the GraphQL schema for a mounted package (ARCHITECTURE.md
    # section 5): per dataset a query field "<dataset>" (list, optional
    # "id:" argument for a single item) plus
    # create<Dataset>/update<Dataset>/delete<Dataset> mutations.
    # Item types are inferred from the dataset's JSON schema when
    # present, else map to a permissive JSON scalar. Field resolvers
    # delegate to the given API object's public methods.
    class GraphqlSchema
      # Permissive scalar carrying any JSON value (schema-less items,
      # mutation inputs, nested structures).
      class JsonScalar < GraphQL::Schema::Scalar
        graphql_name("JSON")
        description "An arbitrary JSON value"

        def self.coerce_input(input_value, _context) = input_value

        def self.coerce_result(ruby_value, _context) = ruby_value
      end

      def initialize(mount, api)
        @mount = mount
        @api = api
      end

      def build
        api = @api
        query_type = Class.new(GraphQL::Schema::Object) { graphql_name("Query") }
        mutation_type = Class.new(GraphQL::Schema::Object) { graphql_name("Mutation") }
        @mount.package.storage.datasets.each do |dataset|
          next if dataset.config.sqlite?

          add_dataset_fields(query_type, mutation_type, dataset, api)
        end
        Class.new(GraphQL::Schema) do
          query(query_type)
          mutation(mutation_type)
        end
      end

      private

      def add_dataset_fields(query_type, mutation_type, dataset, api)
        name = graphql_name_for(dataset.name)
        type = item_type_for(dataset, name)
        add_query_field(query_type, name, type, dataset, api)
        add_mutation_fields(mutation_type, name, type, dataset, api)
      end

      # "<dataset>" returns the merged item list; with "id:" the single
      # matching item (a one-element list, not-found in "errors").
      def add_query_field(query_type, name, type, dataset, api)
        query_type.class_eval do
          field name, [type], null: false, camelize: false do
            argument :id, String, required: false
          end
          define_method(name) { |id: nil| api.collection(dataset, id: id) }
        end
      end

      # create<Dataset>/update<Dataset>/delete<Dataset> with the same
      # semantics (and schema validation) as the REST verbs.
      def add_mutation_fields(mutation_type, name, type, dataset, api)
        capitalized = name.sub(/\A./, &:upcase)
        mutation_type.class_eval do
          field "create#{capitalized}", type, null: true, camelize: false do
            argument :item, JsonScalar, required: true
          end
          define_method("create#{capitalized}") { |item:| api.create_item(dataset, item: item) }

          field "update#{capitalized}", type, null: true, camelize: false do
            argument :id, String, required: true
            argument :item, JsonScalar, required: true
          end
          define_method("update#{capitalized}") do |id:, item:|
            api.update_item(dataset, id: id, item: item)
          end

          field "delete#{capitalized}", GraphQL::Types::Boolean, null: false, camelize: false do
            argument :id, String, required: true
          end
          define_method("delete#{capitalized}") { |id:| api.remove_item(dataset, id: id) }
        end
      end

      # The item type inferred from the dataset's JSON schema (the
      # schema describes the collection; its "items" describe an item),
      # else the permissive JSON scalar.
      def item_type_for(dataset, name)
        properties = item_properties(dataset.json_schema)
        return JsonScalar if properties.nil? || properties.empty?

        fields = properties.to_h { |property, spec| [property, graphql_type_for(spec)] }
        Class.new(GraphQL::Schema::Object) do
          graphql_name("#{name.sub(/\A./, &:upcase)}Item")
          fields.each do |property, type|
            field property, type, null: true, camelize: false
            define_method(property) { object[property] }
          end
        end
      end

      def item_properties(schema)
        return nil unless schema.is_a?(Hash)

        if schema["type"] == "array" && schema["items"].is_a?(Hash)
          schema["items"]["properties"]
        elsif schema["type"] == "object"
          schema["properties"]
        end
      end

      def graphql_type_for(spec)
        case spec.is_a?(Hash) ? spec["type"] : nil
        when "string" then String
        when "integer" then Integer
        when "number" then Float
        when "boolean" then GraphQL::Types::Boolean
        when "array" then [graphql_type_for(spec["items"] || {})]
        else JsonScalar
        end
      end

      # Dataset names become GraphQL identifiers ("my-data" -> "myData").
      def graphql_name_for(name)
        parts = name.split(/[^a-zA-Z0-9]+/).reject(&:empty?)
        return "data" if parts.empty?

        parts.first.downcase + parts.drop(1).map(&:capitalize).join
      end
    end
  end
end
