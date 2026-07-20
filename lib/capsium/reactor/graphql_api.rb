# frozen_string_literal: true

require "graphql"
require "json"

module Capsium
  class Reactor
    # GraphQL over a mount's datasets (POST and GET <mount>/graphql):
    # executes the schema GraphqlSchema derives from the package's
    # storage and maps the overlay's typed errors into the "errors"
    # array (never a 500 on user error). Query fields read the merged
    # collection; mutations match the REST semantics, schema validation
    # included.
    class GraphqlApi
      include Responses

      PATH = "/graphql"

      def self.path?(inner_path)
        inner_path == PATH
      end

      def initialize(mount)
        @mount = mount
        @schema = GraphqlSchema.new(mount, self).build
      end

      def handle(request, response)
        case request.request_method
        when "POST" then handle_post(request, response)
        when "GET" then handle_get(request, response)
        else respond_method_not_allowed(response, allow: "GET, POST")
        end
      end

      # Query/mutation resolvers (public; called from the derived
      # schema's fields).
      def collection(dataset, id: nil)
        return @mount.overlay.items(dataset) if id.nil?

        [@mount.overlay.item(dataset, id)]
      rescue Overlay::Error => e
        raise execution_error(e)
      end

      def create_item(dataset, item:)
        ensure_writable!
        @mount.overlay.append_item(dataset, item)
        item
      rescue Overlay::Error => e
        raise execution_error(e)
      end

      def update_item(dataset, id:, item:)
        ensure_writable!
        @mount.overlay.replace_item(dataset, id, item)
        item
      rescue Overlay::Error => e
        raise execution_error(e)
      end

      def remove_item(dataset, id:)
        ensure_writable!
        @mount.overlay.delete_item(dataset, id)
        true
      rescue Overlay::Error => e
        raise execution_error(e)
      end

      private

      def handle_post(request, response)
        payload = JSON.parse(request.body.to_s)
        unless payload.is_a?(Hash) && payload["query"].is_a?(String)
          return respond_error(response, 400, "GraphQL POST body must be " \
                                              '{"query": "...", "variables": {...}}')
        end

        execute(response, payload["query"], variables: payload["variables"],
                                            operation_name: payload["operationName"])
      rescue JSON::ParserError => e
        respond_error(response, 400, "invalid JSON body: #{e.message}")
      end

      def handle_get(request, response)
        query = request.query["query"]
        return respond_error(response, 400, "missing GraphQL query") if query.nil?

        execute(response, query, variables: parse_variables(request.query["variables"]),
                                 operation_name: request.query["operationName"])
      end

      def parse_variables(raw)
        return nil if raw.nil?

        JSON.parse(raw)
      rescue JSON::ParserError
        nil
      end

      def execute(response, query, variables:, operation_name:)
        result = @schema.execute(query, variables: variables || {},
                                        operation_name: operation_name)
        respond_json(response, 200, result.to_h)
      end

      def ensure_writable!
        return if @mount.writable?

        raise GraphQL::ExecutionError, "package #{@mount.package.name} is read-only"
      end

      def execution_error(error)
        message = if error.is_a?(Overlay::SchemaViolationError)
                    error.messages.join("; ")
                  else
                    error.message
                  end
        GraphQL::ExecutionError.new(message)
      end
    end
  end
end
